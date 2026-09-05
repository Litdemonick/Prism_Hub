import 'package:flutter/material.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';

/// El giro que carga, para Android TV.
///
/// ── Por qué no el esqueleto brillando ────────────────────────────────────
///
/// El esqueleto (`Esqueleto`/`EsqueletoDeFila`) dibuja bloques con la forma
/// de las tarjetas que van a llegar — pero esa forma es siempre la misma
/// mientras que las portadas reales varían mucho de tamaño y proporción, así
/// que en vez de sentirse rápido se veía como una fila de recuadros grises
/// que no se parecen a nada. Pedido explícito, después de ver esto en vivo:
/// «que no se vea nada hasta que cargue bien, sin esqueleto de cards
/// brillando, mejor un coso dando vueltas».
///
/// Nada que insinúe una forma que después no coincide: solo un giro, y
/// recién cuando el contenido está listo se dibuja de una.
class CargandoTv extends StatelessWidget {
  const CargandoTv({super.key, this.tamano = 34, this.color});

  final double tamano;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: tamano,
      height: tamano,
      child: CircularProgressIndicator(
        strokeWidth: 3,
        valueColor: AlwaysStoppedAnimation(color ?? HomeTheme.accentPink),
      ),
    );
  }
}
