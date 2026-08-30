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
 * ── Dónde se dibuja: los dos caminos ────────────────────────────────────────
 *
 * **Capa aparte.** El vídeo va a una `SurfaceView`, que el compositor del
 * aparato pone en su propia capa. La interfaz se redibuja solo cuando cambia
 * algo, y el vídeo avanza a su ritmo sin tocarla. Es lo que hacen las apps de
 * vídeo del sistema, y lo que habilita la tunelización.
 *
 * **Textura.** El decodificador escribe en un búfer que Flutter compone junto
 * con el resto. Cada cuadro de vídeo obliga a una pasada de dibujado de la
 * interfaz entera — a 24 cuadros por segundo, 24 pasadas por segundo aunque no
 * haya cambiado un píxel.
 *
 * La capa aparte es lo que se quiere, y la textura sigue estando porque la capa
 * aparte ya falló una vez en un televisor con Android 9: audio bien, posición
 * avanzando, pantalla negra. Que el camino bueno pueda fallar en un aparato
 * concreto obliga a poder volver al otro sin actualizar la app.
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
                "crear" -> resultado.success(
                    crear(llamada.argument<Boolean>("capaAparte") ?: false)
                )
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
     * Arma el reproductor y le dice dónde pintar.
     *
     * Con [capaAparte] el vídeo va a una `SurfaceView` —una capa del sistema,
     * separada de la interfaz— y se devuelve -1, porque no hay textura que
     * dibujar: la pone Flutter como vista de plataforma. Sin ella se crea una
     * textura y se devuelve su número.
     *
     * Los dos caminos conviven a propósito. La capa aparte es lo que se quiere,
     * pero ya falló una vez en un televisor con Android 9 (pantalla negra con
     * el audio andando), así que la textura tiene que seguir estando para poder
     * volver a ella sin actualizar la app.
     */
    private fun crear(capaAparte: Boolean): Long {
        soltar()
        val r = ReproductorMedia3(contexto, ::emitir)
        reproductor = r
        if (capaAparte) {
            // La superficie llega cuando Flutter monta la vista, que puede ser
            // antes o después de esto. Si ya llegó, se entrega ahora; si no, la
            // entrega ponerSuperficieNativa cuando aparezca.
            superficieNativa?.let { r.ponerSuperficie(it) }
            return -1L
        }
        val entrada = texturas.createSurfaceTexture()
        textura = entrada
        val s = Surface(entrada.surfaceTexture())
        superficie = s
        r.ponerSuperficie(s)
        return entrada.id()
    }

    /** La superficie de la `SurfaceView`, cuando se dibuja en capa aparte. */
    private var superficieNativa: Surface? = null

    /**
     * La vista de plataforma avisa por acá cuando su superficie nace, cambia o
     * muere.
     *
     * Se guarda además de entregarla porque el orden no está garantizado: la
     * vista puede montarse antes de que exista el reproductor, y al revés.
     */
    fun ponerSuperficieNativa(s: Surface?) {
        superficieNativa = s
        reproductor?.ponerSuperficie(s)
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
        // Solo se suelta la superficie de la textura, que es nuestra. La de la
        // SurfaceView la maneja su propia vista: soltarla acá se la sacaría de
        // abajo a un widget que sigue montado.
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
