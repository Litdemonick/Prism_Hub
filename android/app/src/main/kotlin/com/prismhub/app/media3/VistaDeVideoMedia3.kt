package com.prismhub.app.media3

import android.content.Context
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import androidx.media3.common.util.UnstableApi
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/**
 * El vídeo dibujado en una `SurfaceView` de verdad, en su propia capa.
 *
 * ── Qué cambia respecto de la textura ───────────────────────────────────────
 *
 * Con textura, el decodificador escribe en un búfer que después Flutter compone
 * junto con el resto de la interfaz. O sea que cada cuadro de vídeo obliga a una
 * pasada de dibujado de la interfaz entera: a 24 cuadros por segundo, la
 * interfaz se redibuja 24 veces por segundo aunque no haya cambiado un píxel. Es
 * lo que se medía como cuadros lentos en un televisor.
 *
 * Con `SurfaceView`, el compositor del propio aparato pone el vídeo en una capa
 * aparte. La interfaz se redibuja solo cuando algo cambia, y el vídeo avanza a
 * su ritmo sin tocarla. Es lo que hacen las apps de vídeo del sistema.
 *
 * Y habilita la tunelización, que es lo que le saca el desfase de audio a un
 * televisor: el decodificador necesita una superficie de verdad para escribir
 * directo al hardware.
 *
 * ── Por qué esto ya salió mal una vez ───────────────────────────────────────
 *
 * Se intentó antes por el atajo: el modo de superficie nativa del complemento
 * `video_player`. En un televisor con Android 9 el resultado fue audio bien,
 * posición avanzando y la pantalla NEGRA. El propio complemento lo advierte en
 * su README (flutter/flutter#164899).
 *
 * Por eso acá no se da por sentado que funcione. Media3 avisa cuando pinta el
 * primer cuadro, y ese aviso viaja a Dart: si el vídeo está andando y ese aviso
 * no llega, la app se da cuenta sola y vuelve a la textura. Ver el vigilante del
 * lado de Dart.
 */
@UnstableApi
class VistaDeVideoMedia3(
    contexto: Context,
    private val puente: PuenteMedia3,
) : PlatformView, SurfaceHolder.Callback {

    private val vista = SurfaceView(contexto).apply {
        // El fondo en negro y no transparente: mientras el decodificador no
        // haya escrito nada, una superficie transparente deja ver lo que haya
        // detrás —la pantalla anterior— en vez de un marco negro, y eso se lee
        // como un parpadeo al entrar al reproductor.
        setZOrderMediaOverlay(false)
        holder.addCallback(this@VistaDeVideoMedia3)
    }

    override fun getView(): View = vista

    override fun surfaceCreated(holder: SurfaceHolder) {
        puente.ponerSuperficieNativa(holder.surface)
    }

    override fun surfaceChanged(
        holder: SurfaceHolder,
        formato: Int,
        ancho: Int,
        alto: Int,
    ) {
        // Al rotar o al entrar en pantalla completa la superficie se rehace, y
        // la que tenía el reproductor deja de servir. Sin volver a entregarla
        // el vídeo se queda congelado en el último cuadro, con el audio
        // siguiendo — que es un fallo muy parecido al de la pantalla negra y
        // se confundiría con él.
        puente.ponerSuperficieNativa(holder.surface)
    }

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        puente.ponerSuperficieNativa(null)
    }

    override fun dispose() {
        vista.holder.removeCallback(this)
        puente.ponerSuperficieNativa(null)
    }
}

/**
 * Arma la vista cuando Flutter la pide.
 *
 * Hay una sola por vez —no se reproducen dos vídeos a la vez— y por eso la
 * fábrica se queda con el puente en vez de recibirlo en cada creación.
 */
@UnstableApi
class FabricaDeVistaMedia3(
    private val puente: PuenteMedia3,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(contexto: Context, id: Int, argumentos: Any?): PlatformView {
        return VistaDeVideoMedia3(contexto, puente)
    }

    companion object {
        const val TIPO = "com.prismhub.app/media3/vista"
    }
}
