package com.prismhub.app

import android.app.UiModeManager
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
// AudioServiceFragmentActivity y no FlutterFragmentActivity a secas.
//
// Hacen falta las dos cosas a la vez y esta clase es justo la que las junta:
//
//  - Es una FragmentActivity, que es lo que necesita local_auth para mostrar el
//    diálogo de huella con BiometricPrompt. Con la actividad normal ese plugin
//    falla en tiempo de ejecución.
//  - Comparte el motor de Flutter con el servicio de la notificación
//    (audio_service). Sin esto, tocar la notificación cuando la app ya no está
//    en memoria levantaría un motor NUEVO: la app arrancaría de cero y los
//    botones quedarían hablándole a un reproductor que ya no existe.
import com.ryanheise.audioservice.AudioServiceFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity: AudioServiceFragmentActivity() {
    private val CHANNEL = "com.example.prismhub/update"

    // Enlaces compartidos (prismhub://detail?...). En Android no llegan como
    // argumentos del proceso —eso es cosa de escritorio— sino dentro del
    // Intent que abre la actividad, asi que hay que leerlos aca y pasarlos.
    private val CANAL_ENLACES = "com.prismhub.app/enlaces"
    private var canalEnlaces: MethodChannel? = null

    // El enlace con el que se abrio la app. Se guarda porque el Intent llega
    // antes de que Dart este listo para escuchar: cuando Dart pregunta, ya
    // paso. Se entrega una sola vez y se limpia, para que volver a la app no
    // reabra la misma ficha.
    private var enlaceInicial: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        canalEnlaces = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, CANAL_ENLACES
        ).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "enlaceInicial" -> {
                        // Si todavia no se guardo, se lee del Intent AHORA.
                        //
                        // No sobra: el motor de Flutter ahora se comparte con
                        // el servicio de la notificacion, asi que Dart puede
                        // arrancar ANTES de que esta actividad se enganche y
                        // ejecute la linea de abajo que guarda el enlace. Sin
                        // esto, abrir un enlace con la app cerrada la abria
                        // pero no llevaba a la ficha: cuando Dart preguntaba,
                        // enlaceInicial todavia era null.
                        val hay = enlaceInicial ?: enlaceDe(intent)
                        result.success(hay)
                        enlaceInicial = null
                    }
                    else -> result.notImplemented()
                }
            }
        }
        enlaceInicial = enlaceDe(intent)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canInstallApks" -> {
                        result.success(canInstallApks())
                    }
                    "isTelevision" -> {
                        result.success(isTelevision())
                    }
                    "perfilDelAparato" -> {
                        result.success(perfilDelAparato())
                    }
                    "openInstallSettings" -> {
                        openInstallSettings()
                        result.success(null)
                    }
                    "installApk" -> {
                        val apkPath = call.argument<String>("apkPath")
                        if (apkPath != null) {
                            try {
                                installApk(apkPath)
                                result.success(null)
                            } catch (e: Exception) {
                                result.error("INSTALL_FAILED", e.message, null)
                            }
                        } else {
                            result.error("INVALID_ARGS", "apkPath is required", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // Es la forma oficial de saber si esto es un Android TV (o una caja
    // Google TV/leanback) en vez de un teléfono o tablet: el sistema mismo
    // reporta el "modo de UI" actual, y UI_MODE_TYPE_TELEVISION es el valor
    // que usa cualquier launcher de TV real.
    private fun isTelevision(): Boolean {
        val uiModeManager = getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager
        return uiModeManager?.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION
    }

    // Todo lo que hace falta saber del aparato para decidir cuánto puede
    // gastar la app, en UNA sola llamada.
    //
    // ── Por qué no alcanza con isTelevision() ──────────────────────────────
    //
    // Un Chromecast con Google TV 4K y un stick de 1 GB contestan los dos "soy
    // un televisor", y no se les puede pedir lo mismo: al segundo, el techo de
    // memoria de imágenes que le viene bien a un teléfono actual se le come el
    // heap entero y el sistema lo mata. Con esto Dart puede bajar el gasto solo
    // donde hace falta, en vez de castigar a todos por igual.
    //
    // isLowRamDevice() es la respuesta oficial de Android a "esto es un aparato
    // modesto" (la fija el fabricante) — pero no todos los sticks baratos la
    // declaran, así que además se manda la memoria total y los núcleos, y del
    // lado de Dart se decide con los tres.
    private fun perfilDelAparato(): Map<String, Any> {
        val am = getSystemService(Context.ACTIVITY_SERVICE) as? android.app.ActivityManager
        var memoriaTotalMb = 0L
        var bajaMemoria = false
        if (am != null) {
            try {
                val info = android.app.ActivityManager.MemoryInfo()
                am.getMemoryInfo(info)
                memoriaTotalMb = info.totalMem / (1024L * 1024L)
            } catch (e: Exception) {
                // Sin memoria total no se rompe nada: del lado de Dart un 0 se
                // trata como "no se sabe" y deciden los otros dos datos.
                memoriaTotalMb = 0L
            }
            bajaMemoria = am.isLowRamDevice
        }
        return mapOf(
            "esTelevision" to isTelevision(),
            "bajaMemoria" to bajaMemoria,
            "memoriaTotalMb" to memoriaTotalMb,
            "nucleos" to Runtime.getRuntime().availableProcessors()
        )
    }

    private fun canInstallApks(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            packageManager.canRequestPackageInstalls()
    }

    private fun openInstallSettings() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val intent = Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:$packageName")
            ).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            startActivity(intent)
        }
    }

    private fun installApk(apkPath: String) {
        val file = File(apkPath)
        if (!file.exists()) {
            throw Exception("APK file not found: $apkPath")
        }

        val intent = Intent(Intent.ACTION_VIEW).apply {
            val uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                // Android 7.0+: usar FileProvider para seguridad
                FileProvider.getUriForFile(
                    this@MainActivity,
                    "${packageName}.fileprovider",
                    file
                )
            } else {
                // Android < 7.0: usar file:// URI
                Uri.fromFile(file)
            }
            setDataAndType(uri, "application/vnd.android.package-archive")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION
        }

        startActivity(intent)
    }

    // La actividad es singleTop: con la app ya abierta, un enlace nuevo NO
    // crea otra instancia, entra por aca. Sin esto, compartir algo mientras
    // PrismHub esta abierto no hacia absolutamente nada.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val enlace = enlaceDe(intent) ?: return
        // Si Dart todavia no engancho el canal, se guarda para cuando pregunte.
        if (canalEnlaces == null) {
            enlaceInicial = enlace
        } else {
            canalEnlaces?.invokeMethod("enlaceNuevo", enlace)
        }
    }

    private fun enlaceDe(intent: Intent?): String? {
        if (intent?.action != Intent.ACTION_VIEW) return null
        val data = intent.data ?: return null
        // Se aceptan las dos formas: el esquema propio y el https de la
        // pagina puente, que es el que se comparte por chat.
        val s = data.scheme
        val esPropio = s == "prismhub"
        val esPuente = (s == "https" || s == "http") &&
            data.host == "litdemonick.github.io" &&
            (data.path ?: "").endsWith("/abrir")
        return if (esPropio || esPuente) data.toString() else null
    }
}
