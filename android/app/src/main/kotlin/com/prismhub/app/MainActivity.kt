package com.prismhub.app

import android.app.UiModeManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.view.WindowManager
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
                    "ajustarFrecuenciaDePantalla" -> {
                        val fps = call.argument<Double>("fps")
                        result.success(ajustarFrecuenciaDePantalla(fps))
                    }
                    "soltarFrecuenciaDePantalla" -> {
                        soltarFrecuenciaDePantalla()
                        result.success(null)
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

    // UiModeManager es la forma "oficial" de Google, pero NO alcanza sola:
    // reportado en un televisor real donde la app entraba como si fuera un
    // teléfono (todo el layout de teléfono, y el reproductor con controles
    // táctiles que un mando no puede tocar — pantalla negra, nada responde).
    // Fire OS (Amazon) es el caso conocido: es un fork de Android, y en
    // varias versiones NO deja `currentModeType` en UI_MODE_TYPE_TELEVISION
    // aunque el aparato sea, de hecho, un televisor — el propio Amazon
    // documenta que hay que revisar el FEATURE_LEANBACK del sistema en vez
    // de (o además de) UiModeManager. Cualquier TV box genérico con una capa
    // propia encima de Android puede tener el mismo problema.
    //
    // Con las tres condiciones en OR, alcanza con que UNA sola diga la
    // verdad — FEATURE_LEANBACK es el que Google exige declarar para
    // publicar en la Play Store de TV, así que un Android TV/Google TV real
    // (Fire TV incluido, que también lo requiere para su tienda) lo trae
    // sí o sí, incluso cuando UiModeManager se equivoca.
    private fun isTelevision(): Boolean {
        val uiModeManager = getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager
        if (uiModeManager?.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION) {
            return true
        }
        return packageManager.hasSystemFeature(android.content.pm.PackageManager.FEATURE_LEANBACK) ||
            packageManager.hasSystemFeature("android.hardware.type.television")
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
    // ── Poner la pantalla a la frecuencia del contenido ─────────────────────
    //
    // El problema, y es de aritmetica, no de potencia: casi todo el anime y las
    // peliculas van a 23,976 o 24 cuadros por segundo, y un televisor va a 60
    // Hz. Sin pedirle que cambie de modo, esos 24 cuadros hay que repartirlos
    // en 60 refrescos: unos duran dos y otros tres. Eso es un tiron visible en
    // cualquier movimiento lateral de camara, y NO mejora con un televisor mas
    // potente — por eso el usuario lo reporta tambien en los buenos.
    //
    // Es lo que hacen YouTube y Netflix en Android TV, y por eso se ven fluidos.
    //
    // Se elige el modo que MEJOR divide con los cuadros del contenido, no el
    // mas parecido: 24 en una pantalla de 48 Hz va perfecto (cada cuadro dura
    // dos refrescos exactos), y 24 en una de 50 no, aunque 50 este mas cerca
    // de 48.
    //
    // preferredDisplayModeId y no setFrameRate(): el segundo existe recien
    // desde Android 11 y es una SUGERENCIA que muchos televisores ignoran. El
    // modo preferido de la ventana esta desde Android 6 y es lo que de verdad
    // hace renegociar el HDMI.
    //
    // Devuelve la frecuencia que quedo puesta, o null si no se pudo. Que no se
    // pueda es normal —hay televisores con un solo modo— y no es un error: se
    // sigue reproduciendo igual, solo que con el tiron de siempre.
    private fun ajustarFrecuenciaDePantalla(fps: Double?): Double? {
        if (fps == null || fps <= 0) return null
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return null
        return try {
            val display = window?.decorView?.display ?: return null
            val actual = display.mode ?: return null
            val modos = display.supportedModes ?: return null

            // Solo modos con la MISMA resolucion que la puesta. Cambiar de
            // resolucion por un tema de cuadros seria cambiar dos cosas a la
            // vez, y bajar de 4K a 1080p sin que nadie lo pidiera.
            val candidatos = modos.filter {
                it.physicalWidth == actual.physicalWidth &&
                    it.physicalHeight == actual.physicalHeight
            }
            if (candidatos.size < 2) return null

            // Cuantos refrescos dura cada cuadro. Si da entero, cada cuadro
            // dura lo mismo y no hay tiron; cuanto mas se aleja de un entero,
            // peor se ve.
            fun desajuste(hz: Float): Double {
                val refrescosPorCuadro = hz / fps
                if (refrescosPorCuadro < 0.99) return Double.MAX_VALUE
                return kotlin.math.abs(
                    refrescosPorCuadro - kotlin.math.round(refrescosPorCuadro)
                )
            }

            val mejor = candidatos.minByOrNull { desajuste(it.refreshRate) }
                ?: return null
            // Si el que ya esta puesto es igual de bueno, no se toca: cambiar de
            // modo hace parpadear la pantalla mientras el HDMI renegocia.
            if (desajuste(mejor.refreshRate) >= desajuste(actual.refreshRate)) {
                return null
            }

            val params: WindowManager.LayoutParams = window.attributes
            if (modoOriginal == null) modoOriginal = actual.modeId
            params.preferredDisplayModeId = mejor.modeId
            window.attributes = params
            mejor.refreshRate.toDouble()
        } catch (e: Exception) {
            // Un instrumento para que se vea mejor no puede impedir que se vea.
            null
        }
    }

    // El modo que tenia la pantalla antes de que la app lo tocara.
    private var modoOriginal: Int? = null

    // Devuelve la pantalla a su modo de siempre.
    //
    // Hace falta si o si: sin esto el televisor queda a 24 Hz para TODO el
    // sistema al salir del video, y el menu del propio televisor se ve a
    // tirones. Se llama al cerrar el reproductor y tambien al irse la app.
    private fun soltarFrecuenciaDePantalla() {
        val original = modoOriginal ?: return
        try {
            val params: WindowManager.LayoutParams = window.attributes
            params.preferredDisplayModeId = original
            window.attributes = params
        } catch (e: Exception) {
            // Nada que hacer; el sistema lo recupera al cerrar la app.
        } finally {
            modoOriginal = null
        }
    }

    // Red de seguridad: si la app se va sin pasar por el cierre del
    // reproductor, la pantalla no puede quedarse en el modo del video.
    override fun onDestroy() {
        soltarFrecuenciaDePantalla()
        super.onDestroy()
    }

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

    // Tres intentos, cada vez mas generico -y el ultimo SIEMPRE existe en
    // cualquier Android, TV o no. Reportado en vivo: en algunas cajas ni
    // ACTION_MANAGE_UNKNOWN_APP_SOURCES ni ACTION_APPLICATION_DETAILS_SETTINGS
    // abren nada (capas propias de Ajustes que no traen esas pantallas), y
    // sin un ultimo fallback garantizado esta funcion terminaba sin abrir
    // NADA visible -del lado de Flutter se veia como que la actualizacion
    // "no hacia nada" y habia que tocar Actualizar una segunda vez, porque
    // para entonces el usuario habia entrado a Ajustes por su cuenta y ya
    // tenia el permiso dado.
    private fun openInstallSettings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val intentos = listOf(
            Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:$packageName")
            ),
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:$packageName")
            ),
            // Sin URI de paquete: la pantalla de Ajustes general, que existe
            // en TODO Android. Peor experiencia (el usuario tiene que
            // navegar el resto a mano) pero nunca deja al botón sin abrir
            // nada.
            Intent(Settings.ACTION_SETTINGS)
        )
        for (intent in intentos) {
            try {
                startActivity(intent.apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK })
                return
            } catch (e: ActivityNotFoundException) {
                continue
            }
        }
    }

    private fun installApk(apkPath: String) {
        val file = File(apkPath)
        if (!file.exists()) {
            throw Exception("APK file not found: $apkPath")
        }

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

        // ── Dos formas de pedirlo, no una ────────────────────────────────
        //
        // Reportado en vivo: en un televisor, tocar Actualizar bajaba el
        // APK y se quedaba en la misma pantalla, sin abrir el instalador.
        // ACTION_VIEW + FileProvider es la forma moderna y la que anda en
        // cualquier telefono, pero algunas cajas de Android TV con el
        // instalador de paquetes recortado o reemplazado por el fabricante
        // no tienen NINGUNA actividad registrada para ese intent puntual —
        // ahi startActivity no crashea la app (eso ya se atajaba del lado
        // de Flutter) pero tampoco abre nada, y antes se quedaba ahi.
        //
        // ACTION_INSTALL_PACKAGE es la forma vieja, previa a Android N, pero
        // sigue viva y en varias de esas cajas es la UNICA que su launcher
        // conoce. Costo de probarla: nulo si la primera ya funciono, porque
        // ahi ni se llega a intentar.
        val intentos = listOf(
            Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION
            },
            Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION
                putExtra(Intent.EXTRA_NOT_UNKNOWN_SOURCE, true)
            }
        )
        for (intent in intentos) {
            try {
                startActivity(intent)
                return
            } catch (e: ActivityNotFoundException) {
                continue
            }
        }
        // Las dos formas fallaron: este aparato de verdad no tiene con qué
        // instalar un APK. Un mensaje que lo diga, no la excepcion cruda —
        // eso es lo que dejaba ver del lado de Flutter "fallo la descarga"
        // sobre una descarga que habia terminado bien.
        throw Exception("NO_INSTALLER_AVAILABLE")
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
