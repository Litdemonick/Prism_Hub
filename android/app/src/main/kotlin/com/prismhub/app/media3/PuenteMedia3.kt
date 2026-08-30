package com.prismhub.app.media3

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.view.Surface
import androidx.media3.common.C
import androidx.media3.common.util.UnstableApi
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry

/**
 * El paso entre Dart y [ReproductorMedia3].
 *
 * ── Dos canales, y por qué ──────────────────────────────────────────────────
 *
 * Los mandos van por un canal de métodos —Dart pregunta, Kotlin contesta— y el
 * estado sale por uno de eventos, que empuja sin que nadie pregunte.
 *
 * Podría ser todo por el de métodos, con Dart preguntando cada tanto. No: eso
 * es exactamente lo que hace `video_player` con su latido a 4 Hz, que despierta
 * a media app para decirle que nada cambió. Acá el que sabe que algo cambió es
 * el que avisa, y en pausa no se cruza el puente ni una vez.
 *
 * ── Dónde se dibuja hoy ─────────────────────────────────────────────────────
 *
 * En una textura de Flutter. Es el mismo camino que `video_player` y que
 * media_kit, o sea que el vídeo se compone junto con la interfaz y cada cuadro
 * de vídeo es una pasada de dibujado.
 *
 * Se empieza por acá a propósito: es el camino conocido y comparable. Lo otro
 * —una `SurfaceView` de verdad, con el vídeo en una capa aparte del sistema— se
 * apoya en esta misma clase cambiando solo de dónde sale la [Surface], y va
 * aparte para poder medir una cosa por vez. Poner las dos juntas dejaría sin
 * saber cuál de las dos arregló o rompió qué.
 */
@UnstableApi
class PuenteMedia3(
    private val contexto: Context,
    mensajero: BinaryMessenger,
    private val texturas: TextureRegistry,
) {
    private val mano = Handler(Looper.getMainLooper())
    private var salida: EventChannel.EventSink? = null

    private var reproductor: ReproductorMedia3? = null
    private var textura: TextureRegistry.SurfaceTextureEntry? = null
    private var superficie: Surface? = null

    private val canal = MethodChannel(mensajero, CANAL)
    private val avisos = EventChannel(mensajero, CANAL_AVISOS)

    init {
        canal.setMethodCallHandler(::atender)
        avisos.setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(argumentos: Any?, sink: EventChannel.EventSink?) {
                    salida = sink
                }

                override fun onCancel(argumentos: Any?) {
                    salida = null
                }
            }
        )
    }

    private fun atender(llamada: MethodCall, resultado: MethodChannel.Result) {
        try {
            when (llamada.method) {
                "crear" -> resultado.success(crear())
                "abrir" -> {
                    val r = reproductor
                    if (r == null) {
                        resultado.error(SIN_REPRODUCTOR, "no se creó todavía", null)
                        return
                    }
                    r.abrir(
                        url = llamada.argument<String>("url").orEmpty(),
                        cabeceras = llamada.argument<Map<String, String>>("cabeceras")
                            ?: emptyMap(),
                        subtitulos =
                            llamada.argument<List<Map<String, String>>>("subtitulos")
                                ?: emptyList(),
                        arrancar = llamada.argument<Boolean>("arrancar") ?: true,
                        perfil = llamada.argument<String>("perfil") ?: "alto",
                        tunelizar = llamada.argument<Boolean>("tunelizar") ?: false,
                    )
                    resultado.success(null)
                }
                "reproducir" -> {
                    reproductor?.reproducir()
                    resultado.success(null)
                }
                "pausar" -> {
                    reproductor?.pausar()
                    resultado.success(null)
                }
                "parar" -> {
                    reproductor?.parar()
                    resultado.success(null)
                }
                "saltar" -> {
                    reproductor?.saltarA(llamada.argument<Int>("ms")?.toLong() ?: 0L)
                    resultado.success(null)
                }
                "volumen" -> {
                    reproductor?.ponerVolumen(
                        (llamada.argument<Double>("valor") ?: 1.0).toFloat()
                    )
                    resultado.success(null)
                }
                "velocidad" -> {
                    reproductor?.ponerVelocidad(
                        (llamada.argument<Double>("valor") ?: 1.0).toFloat()
                    )
                    resultado.success(null)
                }
                "elegirPista" -> {
                    val tipo = if (llamada.argument<String>("tipo") == "audio") {
                        C.TRACK_TYPE_AUDIO
                    } else {
                        C.TRACK_TYPE_TEXT
                    }
                    reproductor?.elegirPista(tipo, llamada.argument<String>("id"))
                    resultado.success(null)
                }
                "estado" -> resultado.success(reproductor?.estado())
                "soltar" -> {
                    soltar()
                    resultado.success(null)
                }
                else -> resultado.notImplemented()
            }
        } catch (e: Exception) {
            // Nada que pase acá puede tumbar la app: del lado de Dart un error
            // del canal se trata como «este motor no pudo», y hay a dónde caer.
            resultado.error(FALLO, e.message, null)
        }
    }

    /**
     * Arma el reproductor y su textura, y devuelve el número con el que Flutter
     * la dibuja.
     */
    private fun crear(): Long {
        soltar()
        val entrada = texturas.createSurfaceTexture()
        textura = entrada
        val s = Surface(entrada.surfaceTexture())
        superficie = s
        val r = ReproductorMedia3(contexto, ::emitir)
        r.ponerSuperficie(s)
        reproductor = r
        return entrada.id()
    }

    /**
     * Manda un aviso a Dart, siempre desde el hilo principal.
     *
     * El canal de eventos EXIGE que se le hable desde ahí. Hoy todo lo que
     * llama a esto ya viene del hilo principal —ExoPlayer se construyó en él,
     * así que sus avisos salen por ahí—, pero eso es una consecuencia de cómo
     * está armado hoy y no una garantía del contrato. Reenviar cuesta nada y
     * saca de encima un fallo que aparecería recién el día que algo se mueva.
     */
    private fun emitir(dato: Map<String, Any?>) {
        // El tamaño de la textura tiene que seguir al del vídeo. Sin esto se
        // queda en el de fábrica y la imagen sale borrosa o recortada.
        if (dato["que"] == "medidas") {
            val ancho = (dato["ancho"] as? Int) ?: 0
            val alto = (dato["alto"] as? Int) ?: 0
            if (ancho > 0 && alto > 0) {
                textura?.surfaceTexture()?.setDefaultBufferSize(ancho, alto)
            }
        }
        if (Looper.myLooper() == Looper.getMainLooper()) {
            salida?.success(dato)
        } else {
            mano.post { salida?.success(dato) }
        }
    }

    fun soltar() {
        reproductor?.soltar()
        reproductor = null
        superficie?.release()
        superficie = null
        textura?.release()
        textura = null
    }

    /** Se llama al irse la actividad: sin esto quedan el decodificador y la
     * textura tomados hasta que el sistema mate el proceso. */
    fun desenchufar() {
        soltar()
        canal.setMethodCallHandler(null)
        avisos.setStreamHandler(null)
        salida = null
    }

    private companion object {
        const val CANAL = "com.prismhub.app/media3"
        const val CANAL_AVISOS = "com.prismhub.app/media3/avisos"
        const val SIN_REPRODUCTOR = "SIN_REPRODUCTOR"
        const val FALLO = "FALLO_MEDIA3"
    }
}
