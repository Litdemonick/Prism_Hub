package com.prismhub.app

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
// FlutterFragmentActivity y no FlutterActivity: local_auth muestra el
// diálogo de huella con BiometricPrompt, que necesita una FragmentActivity.
// Con la clase normal el plugin falla en tiempo de ejecución.
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity: FlutterFragmentActivity() {
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
                        result.success(enlaceInicial)
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
        return if (data.scheme == "prismhub") data.toString() else null
    }
}
