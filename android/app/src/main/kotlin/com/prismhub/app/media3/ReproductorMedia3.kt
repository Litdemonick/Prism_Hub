package com.prismhub.app.media3

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.view.Surface
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import androidx.media3.common.VideoSize
import androidx.media3.common.text.CueGroup
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector

/**
 * El reproductor de Android, hecho directo contra Media3.
 *
 * ── Por qué no alcanzaba con el complemento `video_player` ───────────────────
 *
 * `video_player` también usa ExoPlayer por debajo, así que la idea era usarlo y
 * no escribir nada nativo. No alcanzó, y las tres razones se midieron:
 *
 *  1. **No entrega los subtítulos.** Ni los que trae el archivo ni los que
 *     manda la extensión aparte. En la app eso se vio como que en Android, con
 *     ExoPlayer, no se veía ni un subtítulo: el `SubtitleView` que los dibuja
 *     está atado al reproductor de media_kit, que con este motor nunca recibe
 *     la fuente.
 *  2. **No deja elegir pista de audio.** Un archivo con japonés y castellano
 *     se queda con la que el sistema decida.
 *  3. **No expone la tunelización**, que es lo que le saca el desfase de audio
 *     a un televisor.
 *
 * Las tres son de la API del complemento, no de ExoPlayer: ExoPlayer sabe hacer
 * las tres. Por eso se habla con Media3 directo.
 *
 * ── Qué NO decide esta clase ────────────────────────────────────────────────
 *
 * Dónde se dibuja. Recibe una [Surface] y pinta ahí. Hoy esa superficie viene
 * de una textura de Flutter; la idea es que después venga de una `SurfaceView`
 * de verdad, que es lo que pone el vídeo en una capa aparte del sistema. Ese
 * cambio no toca nada de este archivo, y por eso está separado.
 */
@UnstableApi
class ReproductorMedia3(
    private val contexto: Context,
    private val avisar: (Map<String, Any?>) -> Unit,
) {
    private var player: ExoPlayer? = null
    private val selector = DefaultTrackSelector(contexto)
    private val mano = Handler(Looper.getMainLooper())

    /** Lo último avisado, para no repetir el mismo valor en cada latido. */
    private var ultimaPosicion = -1L
    private var ultimoColchon = -1L

    /**
     * Cada cuánto se avisa la posición mientras rueda.
     *
     * 250 ms, no menos: la barra de progreso no puede mostrar más finito que
     * eso, y cada aviso cruza el puente a Dart y despierta a todo lo que
     * escucha —barra, historial, notificación—. `video_player` late a 4 Hz pase
     * lo que pase, incluso en pausa; acá el latido se para al pausar.
     */
    private val latido = object : Runnable {
        override fun run() {
            val p = player ?: return
            avisarPosicion(p)
            if (p.isPlaying) mano.postDelayed(this, 250)
        }
    }

    // ── Abrir ───────────────────────────────────────────────────────────────

    /**
     * @param perfil "alto", "medio" o "bajo". Decide cuánto se guarda por
     *   delante, que es memoria: en un televisor de 1 GB el colchón de fábrica
     *   de ExoPlayer (50 s) es una mordida grande al montón que le queda a la
     *   app, y de ahí salen los cuadros lentos por recolección de basura.
     * @param subtitulos mapas con `url`, `idioma` y `titulo` — los que entrega
     *   la extensión aparte del vídeo.
     */
    fun abrir(
        url: String,
        cabeceras: Map<String, String>,
        subtitulos: List<Map<String, String>>,
        arrancar: Boolean,
        perfil: String,
        tunelizar: Boolean,
    ) {
        soltarElAnterior()

        val http = DefaultHttpDataSource.Factory()
            .setAllowCrossProtocolRedirects(true)
            // Muchas fuentes contestan que no sin el Referer y el User-Agent:
            // son lo que las convence de entregar el vídeo.
            .setDefaultRequestProperties(cabeceras)
            .setConnectTimeoutMs(20_000)
            .setReadTimeoutMs(20_000)
        cabeceras["User-Agent"]?.let { http.setUserAgent(it) }

        val fuentes = DefaultMediaSourceFactory(
            DefaultDataSource.Factory(contexto, http)
        )

        selector.parameters = selector.buildUponParameters()
            // La tunelización necesita una superficie nativa de verdad. Con una
            // textura de Flutter el decodificador no tiene a dónde escribir
            // directo, y ExoPlayer descarta la pista sin decir nada — la
            // pantalla queda negra con el audio andando. Por eso viene de
            // afuera en vez de encenderse sola.
            .setTunnelingEnabled(tunelizar)
            .build()

        val nuevo = ExoPlayer.Builder(contexto)
            .setTrackSelector(selector)
            .setMediaSourceFactory(fuentes)
            .setLoadControl(colchonPara(perfil))
            .build()

        nuevo.addListener(Escucha())
        nuevo.setMediaItem(itemCon(url, subtitulos))
        nuevo.playWhenReady = arrancar
        nuevo.prepare()
        player = nuevo
        superficie?.let { nuevo.setVideoSurface(it) }
        if (arrancar) mano.post(latido)
    }

    private fun itemCon(
        url: String,
        subtitulos: List<Map<String, String>>,
    ): MediaItem {
        val item = MediaItem.Builder().setUri(url)
        if (subtitulos.isNotEmpty()) {
            item.setSubtitleConfigurations(
                subtitulos.mapNotNull { s ->
                    val u = s["url"] ?: return@mapNotNull null
                    MediaItem.SubtitleConfiguration.Builder(Uri.parse(u))
                        .setMimeType(tipoDeSubtitulo(u))
                        .setLanguage(s["idioma"])
                        .setLabel(s["titulo"])
                        .build()
                }
            )
        }
        return item.build()
    }

    /**
     * Qué clase de subtítulo es, por el final de la dirección.
     *
     * Media3 exige el tipo declarado para un subtítulo externo: a diferencia
     * del vídeo, no lo adivina mirando el contenido. Si no se reconoce se
     * prueba con SubRip, que es lo que entregan casi todas las extensiones.
     */
    private fun tipoDeSubtitulo(url: String): String {
        val limpia = url.substringBefore(SIGNO_PREGUNTA).lowercase()
        return when {
            limpia.endsWith(".vtt") -> MimeTypes.TEXT_VTT
            limpia.endsWith(".ass") || limpia.endsWith(".ssa") -> MimeTypes.TEXT_SSA
            limpia.endsWith(".ttml") || limpia.endsWith(".xml") ->
                MimeTypes.APPLICATION_TTML
            else -> MimeTypes.APPLICATION_SUBRIP
        }
    }

    /**
     * Cuánto se guarda por delante, según lo que aguante el aparato.
     *
     * El de fábrica de ExoPlayer apunta a un teléfono actual. En un televisor
     * modesto ese colchón compite por memoria con las imágenes de la interfaz,
     * y cuando el recolector de basura entra a la mitad de una escena eso se ve
     * como un tirón. Menos colchón es más riesgo de cortarse con una red mala,
     * así que se baja solo donde hace falta.
     */
    private fun colchonPara(perfil: String): DefaultLoadControl {
        val minMs: Int
        val maxMs: Int
        when (perfil) {
            "bajo" -> {
                minMs = 15_000
                maxMs = 30_000
            }
            "medio" -> {
                minMs = 25_000
                maxMs = 50_000
            }
            else -> {
                minMs = 50_000
                maxMs = 50_000
            }
        }
        return DefaultLoadControl.Builder()
            .setBufferDurationsMs(
                minMs,
                maxMs,
                // Cuánto hace falta para empezar, y cuánto para volver después
                // de un corte. Cortos a propósito: son los dos momentos en los
                // que la persona está mirando una rueda girar.
                DefaultLoadControl.DEFAULT_BUFFER_FOR_PLAYBACK_MS,
                DefaultLoadControl.DEFAULT_BUFFER_FOR_PLAYBACK_AFTER_REBUFFER_MS,
            )
            .build()
    }

    // ── La superficie donde se pinta ────────────────────────────────────────

    private var superficie: Surface? = null

    fun ponerSuperficie(s: Surface?) {
        superficie = s
        player?.setVideoSurface(s)
    }

    // ── Mandos ──────────────────────────────────────────────────────────────

    fun reproducir() {
        player?.play()
        mano.post(latido)
    }

    fun pausar() {
        player?.pause()
    }

    fun parar() {
        player?.let {
            it.pause()
            it.seekTo(0)
        }
    }

    fun saltarA(ms: Long) {
        val p = player ?: return
        p.seekTo(ms)
        avisarPosicion(p)
    }

    fun ponerVolumen(v: Float) {
        val p = player ?: return
        p.volume = v.coerceIn(0f, 1f)
        avisar(mapOf("que" to "volumen", "valor" to p.volume.toDouble()))
    }

    fun ponerVelocidad(v: Float) {
        player?.setPlaybackSpeed(v)
    }

    // ── Pistas ──────────────────────────────────────────────────────────────

    /**
     * Elige una pista de las que trae el contenido.
     *
     * [id] es el que se mandó en el aviso de pistas: "grupo:indice". Con null
     * se apaga ese tipo de pista del todo — que para subtítulos es «ninguno», y
     * es lo que hay que poder hacer.
     */
    fun elegirPista(tipo: Int, id: String?) {
        val p = player ?: return
        val armado = p.trackSelectionParameters.buildUpon()
            .clearOverridesOfType(tipo)
            .setTrackTypeDisabled(tipo, id == null)
        if (id != null) {
            val partes = id.split(":")
            val iGrupo = partes.getOrNull(0)?.toIntOrNull()
            val iPista = partes.getOrNull(1)?.toIntOrNull()
            val grupos = p.currentTracks.groups.filter { it.type == tipo }
            if (iGrupo != null && iPista != null && iGrupo < grupos.size) {
                armado.addOverride(
                    TrackSelectionOverride(grupos[iGrupo].mediaTrackGroup, iPista)
                )
            }
        }
        p.trackSelectionParameters = armado.build()
    }

    /**
     * Las pistas de audio y de texto, con el mismo identificador que espera
     * [elegirPista].
     *
     * Se numeran los grupos por tipo y no de corrido: así el identificador de
     * una pista de texto no depende de cuántas de audio haya delante, que es
     * justo lo que cambia entre un archivo y otro.
     */
    private fun listarPistas(pistas: Tracks): List<Map<String, Any?>> {
        val fuera = mutableListOf<Map<String, Any?>>()
        var iAudio = 0
        var iTexto = 0
        for (grupo in pistas.groups) {
            val tipo = grupo.type
            if (tipo != C.TRACK_TYPE_AUDIO && tipo != C.TRACK_TYPE_TEXT) continue
            val iGrupo = if (tipo == C.TRACK_TYPE_AUDIO) iAudio++ else iTexto++
            for (i in 0 until grupo.length) {
                val f = grupo.getTrackFormat(i)
                fuera.add(
                    mapOf(
                        "tipo" to if (tipo == C.TRACK_TYPE_AUDIO) "audio" else "texto",
                        "id" to "$iGrupo:$i",
                        "idioma" to f.language,
                        "titulo" to f.label,
                        "elegida" to grupo.isTrackSelected(i),
                        "sePuede" to grupo.isTrackSupported(i),
                    )
                )
            }
        }
        return fuera
    }

    // ── Estado que sale hacia Dart ──────────────────────────────────────────

    private fun avisarPosicion(p: Player) {
        val pos = p.currentPosition
        if (pos != ultimaPosicion) {
            ultimaPosicion = pos
            avisar(mapOf("que" to "posicion", "valor" to pos))
        }
        val colchon = p.bufferedPosition
        if (colchon != ultimoColchon) {
            ultimoColchon = colchon
            avisar(mapOf("que" to "colchon", "valor" to colchon))
        }
    }

    private inner class Escucha : Player.Listener {
        override fun onPlaybackStateChanged(estado: Int) {
            val p = player ?: return
            avisar(
                mapOf(
                    "que" to "cargando",
                    "valor" to (estado == Player.STATE_BUFFERING),
                )
            )
            if (estado == Player.STATE_READY) {
                val d = p.duration
                // C.TIME_UNSET es lo que devuelve mientras no se sabe, y
                // también en una emisión en vivo, que no tiene largo.
                avisar(
                    mapOf(
                        "que" to "duracion",
                        "valor" to if (d == C.TIME_UNSET) 0L else d,
                    )
                )
            }
            if (estado == Player.STATE_ENDED) {
                avisar(mapOf("que" to "final"))
            }
        }

        override fun onIsPlayingChanged(rodando: Boolean) {
            avisar(mapOf("que" to "reproduciendo", "valor" to rodando))
            if (rodando) mano.post(latido)
        }

        override fun onPlayerError(error: PlaybackException) {
            // Se manda el nombre del código además del mensaje: los mensajes de
            // ExoPlayer son cortos y ambiguos ("Source error"), y el código es
            // lo que distingue una fuente caída de un formato que no se puede
            // decodificar. Sin eso, en el registro los dos se leen igual.
            avisar(
                mapOf(
                    "que" to "error",
                    "valor" to "${error.errorCodeName}: ${error.message}",
                )
            )
        }

        override fun onRenderedFirstFrame() {
            // El aviso que dice que de verdad se ESTA VIENDO algo.
            //
            // Es la unica forma de distinguir «reproduciendo» de «reproduciendo
            // y visible». Con la superficie en capa aparte esa diferencia es
            // todo: el fallo que ya se vio en un televisor era audio andando,
            // posicion avanzando y la pantalla negra — o sea, todo el estado
            // diciendo que si, y nada en pantalla. Del lado de Dart hay un
            // vigilante esperando esto.
            avisar(mapOf("que" to "primerCuadro"))
        }

        override fun onVideoSizeChanged(medidas: VideoSize) {
            avisar(
                mapOf(
                    "que" to "medidas",
                    "ancho" to medidas.width,
                    "alto" to medidas.height,
                )
            )
        }

        override fun onTracksChanged(pistas: Tracks) {
            avisar(mapOf("que" to "pistas", "valor" to listarPistas(pistas)))
        }

        override fun onCues(cues: CueGroup) {
            // El texto sale crudo y lo dibuja Dart, no la vista de Media3.
            //
            // A propósito: la app ya tiene los ajustes de tamaño, color, fondo
            // y alineación de los subtítulos, y están hechos contra el dibujado
            // de Flutter. Devolviendo el texto se usan los mismos en los dos
            // motores, en vez de tener dos aspectos distintos según el aparato.
            avisar(
                mapOf(
                    "que" to "subtitulo",
                    "valor" to cues.cues.mapNotNull { it.text?.toString() },
                )
            )
        }
    }

    // ── Soltar ──────────────────────────────────────────────────────────────

    fun soltar() {
        soltarElAnterior()
        superficie = null
    }

    private fun soltarElAnterior() {
        mano.removeCallbacks(latido)
        val viejo = player
        player = null
        ultimaPosicion = -1L
        ultimoColchon = -1L
        viejo?.let {
            it.setVideoSurface(null)
            it.release()
        }
    }

    // ── Lo que se pregunta de una ───────────────────────────────────────────

    fun estado(): Map<String, Any?> {
        val p = player
        return mapOf(
            "posicion" to (p?.currentPosition ?: 0L),
            "duracion" to (p?.duration?.takeIf { it != C.TIME_UNSET } ?: 0L),
            "colchon" to (p?.bufferedPosition ?: 0L),
            "reproduciendo" to (p?.isPlaying ?: false),
            "cargando" to (p?.playbackState == Player.STATE_BUFFERING),
            "volumen" to ((p?.volume ?: 1f).toDouble()),
        )
    }

    private companion object {
        const val SIGNO_PREGUNTA = '?'
    }
}
