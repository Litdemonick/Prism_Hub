import 'package:flutter/material.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';

/// El panel de info que aparece al pasar el mouse sobre una portada:
/// título, de qué extensión viene, fecha, descripción y "Ver detalles".
///
/// Antes vivía escrito una sola vez, adentro de `TarjetaDeCatalogo`. Pedido
/// explícito: el carrusel de Inicio (`_TarjetaGrande` en
/// `home_page_android.dart`) tiene que mostrar lo mismo al pasar el mouse
/// — reusando este widget en los dos lugares en vez de escribirlo de
/// nuevo, así una mejora acá vale para las dos tarjetas.
///
/// Cada dato es OPCIONAL a propósito: `latest()`/`search()` de una
/// extensión no siempre trae fecha o descripción, y el panel se acomoda
/// solo — nunca deja un hueco reservado para algo que no llegó.
class PanelInfoHover extends StatelessWidget {
  const PanelInfoHover({
    super.key,
    required this.titulo,
    this.encabezado,
    this.fecha,
    this.descripcion,
    this.acento,
    this.onTap,
    this.compacto = false,
  });

  final String titulo;
  final String? encabezado;
  final String? fecha;
  final String? descripcion;
  final Color? acento;
  final VoidCallback? onTap;

  /// El panel se ajusta a lo que tiene adentro, en vez de estirarse para
  /// llenar el alto que le den.
  ///
  /// ── Para qué ────────────────────────────────────────────────────────
  ///
  /// En su uso normal (el hover de mouse) el panel cubre el póster entero y
  /// puede repartir el espacio con un `Expanded`: la descripción se queda
  /// con todo lo que sobre. En televisor no cubre el póster entero —taparlo
  /// sería esconder justo lo que el usuario está mirando— así que se le da
  /// una franja de abajo, y ahí un `Expanded` no sirve: obliga a fijar un
  /// alto de antemano, y lo que no entra se corta.
  ///
  /// Reportado en vivo con foto: "al seleccionar se corta en vez de subir
  /// la info". Con esto el panel mide lo que de verdad necesita y crece
  /// hacia arriba lo justo, sea un título de una línea o de tres.
  final bool compacto;

  Color get _acento => acento ?? HomeTheme.accentPink;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      // ── El degradado arranca TRANSPARENTE ─────────────────────────────
      //
      // Arrancaba en 0xA6 —un 65 % de opacidad— y eso, cuando el panel no
      // cubre la tarjeta entera, se ve como una línea recta cortándola por la
      // mitad. Reportado con foto en un televisor: «sale cortado, sale por la
      // mitad en vez de ser toda la tarjeta».
      //
      // Con el primer tramo en transparente puro no hay borde que ver: el
      // panel se funde con la portada y solo se oscurece donde hay texto.
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0x00101019),
            Color(0xC2101019),
            Color(0xF2101019),
          ],
          stops: [0.0, 0.42, 1.0],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: compacto ? MainAxisSize.min : MainAxisSize.max,
          children: [
            if (encabezado != null) ...[
              Text(
                encabezado!.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9.5,
                  letterSpacing: 0.9,
                  fontWeight: FontWeight.w700,
                  color: HomeTheme.textMuted,
                ),
              ),
              const SizedBox(height: 6),
            ],
            Text(
              titulo,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.25,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            if (fecha != null) ...[
              const SizedBox(height: 5),
              Row(
                children: [
                  Icon(Icons.calendar_today_rounded,
                      size: 11, color: HomeTheme.textMuted),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      fecha!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: HomeTheme.textMuted),
                    ),
                  ),
                ],
              ),
            ],
            if (descripcion != null) ...[
              const SizedBox(height: 8),
              // Expanded y no un alto fijo: la descripción usa lo que sobre
              // después del título y la fecha. Con alto fijo, un título de
              // tres líneas la empujaba fuera del panel.
              Expanded(
                child: Text(
                  descripcion!,
                  overflow: TextOverflow.fade,
                  style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.35,
                    color: Color(0xFFC9C4D4),
                  ),
                ),
              ),
            ] else
              const Spacer(),
            const SizedBox(height: 6),
            // El ÚNICO que abre la ficha cuando el panel está abierto. Tocar
            // en cualquier otro lado lo cierra, así el panel no es una
            // trampa.
            //
            // GestureDetector propio y opaco: sin esto el toque se lo
            // llevaba la tarjeta de atrás y el botón no hacía nada.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: Padding(
                // Aire de sobra alrededor del texto: es el objetivo más
                // chico del panel y en un teléfono tiene que poder tocarse
                // sin apuntar.
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(Icons.play_arrow_rounded, size: 17, color: _acento),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'home.view-detail'.i18n.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          letterSpacing: 0.6,
                          fontWeight: FontWeight.w800,
                          color: _acento,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
