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

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.sizeOf(context).width;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    return Scaffold(
      backgroundColor: _fondo,
      body: SizedBox.expand(
        child: Image.asset(
          'assets/banner_cargando_launch.jpg',
          fit: BoxFit.cover,
          cacheWidth: (ancho * dpr).round(),
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }
}
