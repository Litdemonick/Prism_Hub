import 'package:flutter/material.dart';

/// La pantalla de arranque: un banner ESTÁTICO, pedido explícito —estilo
/// Magis TV—, en las cuatro plataformas.
///
/// ── Por qué no hay más un camino "solo logo" ────────────────────────────
///
/// Existía una versión liviana —solo el logo latiendo, sin el resto— para
/// cuando la app "vuelve" (Android mató el proceso hace poco y el usuario
/// estuvo hace un minuto): mostrarle la presentación completa de nuevo se
/// sentía redundante. Pero de cara al usuario esto se veía como que el
/// splash pedido ni se estaba usando —cada reapertura rápida (típico de
/// estar probando la app) caía en ese camino liviano en vez del banner
/// nuevo. Pedido explícito: siempre el banner, en toda apertura, en toda
/// plataforma.
///
/// Esto se dibuja mientras la app todavía se está inicializando, o sea en
/// el momento en que el hilo de UI está MÁS ocupado. Un tirón acá se ve
/// como una app pesada, aunque después vuele — por eso es un solo
/// `Image.asset`, sin capas que animar, con `cacheWidth` puesto para no
/// decodificar a resolución completa en un aparato de gama baja.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  static const _fondo = Color(0xFF08080F);

  /// El banner panorámico (2752×1536, ~16:9) — para TV, escritorio y
  /// celular en horizontal.
  static const _bannerHorizontal = 'assets/banner_cargando_launch.jpg';

  /// El mismo diseño, recompuesto en vertical (1536×2752, ~9:16).
  ///
  /// ── Por qué dos archivos y no uno recortado por código ───────────────
  ///
  /// Reportado en vivo: con el banner horizontal estirado en un celular
  /// parado, `BoxFit.cover` (el único fit que no deforma la imagen)
  /// dejaba ver apenas una tira angosta y centrada del original —el logo
  /// entraba, pero al lado quedaban fragmentos cortados de las portadas
  /// de las puntas, sin el resto del collage alrededor que les da
  /// sentido. Un recorte por código no soluciona eso: el problema no es
  /// el encuadre, es que el diseño en sí está pensado para 16:9, no para
  /// 9:16. Con un segundo banner compuesto directamente en vertical, cada
  /// forma de pantalla muestra el diseño que le corresponde.
  static const _bannerVertical = 'assets/banner_cargando_launch_vertical.jpg';

  @override
  Widget build(BuildContext context) {
    final tamano = MediaQuery.sizeOf(context);
    final dpr = MediaQuery.of(context).devicePixelRatio;
    // Vertical: la pantalla es más angosta que alta. Es la MISMA cuenta que
    // ya usa el resto de la app para saber si algo es "apaisado"
    // (home_page_windows.dart) — nada nuevo, solo puesta en términos de
    // alto/ancho en vez de ancho/alto. Un televisor SIEMPRE cae en el
    // camino horizontal: no hay forma física de pararlo.
    final esVertical = tamano.height > tamano.width;
    return Scaffold(
      backgroundColor: _fondo,
      body: SizedBox.expand(
        child: Image.asset(
          esVertical ? _bannerVertical : _bannerHorizontal,
          fit: BoxFit.cover,
          cacheWidth: (tamano.width * dpr).round(),
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }
}
