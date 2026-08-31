import 'package:flutter/material.dart';
import 'package:prismhub/utils/encabezado_de_sesion.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/platform_tv.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';

/// La ficha del aparato: marca, modelo, memoria, pantalla, sistema.
///
/// ── Qué había acá antes, y por qué se sacó ──────────────────────────────
///
/// Esto era la pantalla de PrismHub+: explicaba qué es, qué había ajustado
/// por este aparato (calidad de vídeo, turno de peticiones, animaciones,
/// listas) y traía dos botones — limpiar temporales y volver a medir.
///
/// Pedido explícito, repetido: PrismHub+ no se muestra ni se toca. Lo que
/// hace se decide solo al abrir la app, mirando el aparato, y ahí se queda.
/// Un botón para limpiar o para volver a medir es una manera de que alguien
/// desarme sin querer lo único que hace que la app ande bien en su aparato,
/// y una lista de «qué ajusté» invita a buscarle el interruptor a cada cosa.
///
/// Lo que SÍ se deja es esto: que uno pueda ver qué aparato tiene. Eso es
/// información, no una perilla — no hay nada que tocar en esta pantalla.
///
/// ── De dónde salen los datos ────────────────────────────────────────────
///
/// De `EncabezadoDeSesion.fichaEnPares()`, exactamente lo mismo que se
/// escribe al principio del registro. Es a propósito: si alguien manda un
/// reporte, lo que vio en pantalla y lo que llegó en el registro dicen lo
/// mismo, siempre.
///
/// ── El mismo diseño en las tres plataformas ─────────────────────────────
///
/// Solo cambian los tamaños: desde el sillón un texto de 13 no se lee. No
/// hay nada enfocable adentro, así que con el mando alcanza con la flecha
/// de volver — no hace falta recorrer nada.
class InfoDelAparatoPage extends StatelessWidget {
  const InfoDelAparatoPage({super.key});

  @override
  Widget build(BuildContext context) {
    final tv = PlatformTv.esTelevisionSync;
    final tituloSz = tv ? 22.0 : 16.0;
    final textoSz = tv ? 17.0 : 14.0;
    final chicoSz = tv ? 15.0 : 12.0;
    return Scaffold(
      backgroundColor: HomeTheme.bg,
      appBar: AppBar(
        backgroundColor: HomeTheme.bg,
        elevation: 0,
        title: Text(
          'settings.mas-tu-aparato'.i18n,
          style: TextStyle(
            fontSize: tituloSz,
            fontWeight: FontWeight.w700,
            color: HomeTheme.textPrimary,
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          // Acotado y centrado: en un PC a pantalla completa o en una tablet
          // apaisada, una lista de punta a punta deja la etiqueta pegada a un
          // borde y el valor al otro, con medio metro de nada en medio.
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: ListView(
              padding: EdgeInsets.all(tv ? 28 : 16),
              children: [
                _Tarjeta(
                  tv: tv,
                  hijos: [
                    for (final p in EncabezadoDeSesion.fichaEnPares())
                      _Fila(
                        etiqueta: p.etiqueta,
                        valor: p.valor,
                        tamano: textoSz,
                        tamanoChico: chicoSz,
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'settings.aparato-nota'.i18n,
                    style: TextStyle(
                      fontSize: chicoSz,
                      height: 1.5,
                      color: HomeTheme.textMuted,
                    ),
                  ),
                ),
                const SizedBox(height: 28),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Tarjeta extends StatelessWidget {
  const _Tarjeta({required this.hijos, required this.tv});

  final List<Widget> hijos;
  final bool tv;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.all(tv ? 20 : 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Color.alphaBlend(
            Colors.white.withValues(alpha: 0.05),
            HomeTheme.bg,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: hijos,
        ),
      );
}

class _Fila extends StatelessWidget {
  const _Fila({
    required this.etiqueta,
    required this.valor,
    required this.tamano,
    required this.tamanoChico,
  });

  final String etiqueta;
  final String valor;
  final double tamano;
  final double tamanoChico;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: tamano * 6.5,
              child: Text(
                etiqueta,
                style: TextStyle(
                  fontSize: tamanoChico,
                  fontWeight: FontWeight.w600,
                  color: HomeTheme.textMuted,
                ),
              ),
            ),
            Expanded(
              child: Text(
                valor,
                style: TextStyle(
                  fontSize: tamano,
                  height: 1.35,
                  color: HomeTheme.textPrimary,
                ),
              ),
            ),
          ],
        ),
      );
}
