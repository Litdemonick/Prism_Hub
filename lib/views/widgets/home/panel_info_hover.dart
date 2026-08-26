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
  });

  final String titulo;
  final String? encabezado;
  final String? fecha;
  final String? descripcion;
  final Color? acento;
  final VoidCallback? onTap;

  Color get _acento => acento ?? HomeTheme.accentPink;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xA6101019), Color(0xE0101019), Color(0xF2101019)],
          stops: [0.0, 0.45, 1.0],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
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
