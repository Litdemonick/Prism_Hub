import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:get/get.dart';
import 'package:prismhub/controllers/detail_controller.dart';
import 'package:prismhub/models/extension.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/views/widgets/cache_network_image.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';

// Mismos colores que ExtensionTypeBadge (las tarjetas de las listas), para
// que "Vídeo"/"Lectura" se lea igual en toda la app.
Color _typeColor(ExtensionType type) => switch (type) {
      ExtensionType.bangumi => const Color(0xFF3B82F6), // azul — vídeo
      ExtensionType.manga ||
      ExtensionType.fikushon =>
        const Color(0xFFA855F7), // violeta — lectura
      ExtensionType.mixed => const Color(0xFF10B981), // verde — mixta
    };

// Los valores vienen del SDK ('ongoing' | 'completed' | 'upcoming' |
// 'hiatus'). Devuelve null para cualquier otro valor (o null), y ahí no se
// dibuja nada — mejor no mostrar badge que inventar un estado.
String? _statusLabel(String? status) => switch (status) {
      'ongoing' => 'detail.status-ongoing'.i18n,
      'completed' => 'detail.status-completed'.i18n,
      'upcoming' => 'detail.status-upcoming'.i18n,
      'hiatus' => 'detail.status-hiatus'.i18n,
      _ => null,
    };

Color _statusColor(String status) => switch (status) {
      'ongoing' => const Color(0xFF10B981), // verde — publicándose
      'completed' => const Color(0xFF3B82F6), // azul — terminado
      'upcoming' => const Color(0xFFF59E0B), // ámbar — próximamente
      _ => const Color(0xFF9CA3AF), // gris — pausado/desconocido
    };

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      // Fondo SÓLIDO y borde sólido. Antes el relleno iba al 16% y el borde
      // al 70%, así que sobre la portada del detalle —que puede ser clara o
      // de colores fuertes— el distintivo se mezclaba y casi no se leía. Con
      // el color pleno y el texto en blanco se ve igual sobre cualquier
      // imagen, que es lo único que importa acá.
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.55)),
      ),
      child: Text(
        _statusLabel(status)!,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class DetailExtensionTile extends StatelessWidget {
  const DetailExtensionTile({
    super.key,
    this.tag,
  });

  final String? tag;

  @override
  Widget build(BuildContext context) {
    final c = Get.find<DetailPageController>(tag: tag);
    return Obx(() {
      if (c.extension == null) {
        return Text(
          FlutterI18n.translate(
            context,
            'common.extension-missing',
            translationParams: {
              'package': c.package,
            },
          ),
          style: const TextStyle(color: HomeTheme.textMuted),
        );
      }
      // Para una extensión "mixed" (ej. ShadeManga), c.type solo se sabe con
      // certeza una vez que cargó detail() (antes de eso, el getter cae al
      // default bangumi) — mostrarlo antes de tiempo hacía un flash visible
      // "Vídeo" → "Lectura" apenas terminaba de cargar. Extensiones normales
      // no tienen este problema (su tipo es fijo desde el principio), así
      // que solo se oculta el puntito+etiqueta mientras es mixed Y todavía
      // no hay datos.
      final typeKnown =
          c.extension!.type != ExtensionType.mixed || c.detail != null;
      // Wrap, no Row: en celular esta línea (ícono + nombre + tipo + estado)
      // no siempre entra en el ancho disponible junto al thumbnail de la
      // portada — con Row se cortaba el badge de estado fuera de pantalla
      // ("RIGHT OVERFLOWED", reportado en vivo con captura). Con Wrap, lo
      // que no entra baja a una segunda línea en vez de desbordar.
      return Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 4,
        children: [
          if (c.extension!.icon != null)
            Container(
              margin: const EdgeInsets.only(right: 8),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
              ),
              clipBehavior: Clip.antiAlias,
              child: CacheNetWorkImagePic(
                c.extension!.icon!,
                width: 20,
              ),
            ),
          Text(
            c.extension!.name,
            style: const TextStyle(
              color: HomeTheme.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (typeKnown) ...[
            const SizedBox(width: 8),
            const DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: HomeTheme.textMuted,
              ),
              child: SizedBox(width: 4, height: 4),
            ),
            const SizedBox(width: 8),
            // Mismo color que el badge de tipo en las tarjetas (azul para
            // vídeo, morado para lectura) — antes era gris apagado y no se
            // distinguía de un texto secundario cualquiera.
            Text(
              ExtensionUtils.typeToString(c.type),
              style: TextStyle(
                color: _typeColor(c.type),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          // Estado de publicación (en emisión / finalizado / ...). Solo se
          // muestra si la extensión lo manda — ver ExtensionDetail.status.
          if (_statusLabel(c.detail?.status) != null) ...[
            const SizedBox(width: 10),
            _StatusBadge(status: c.detail!.status!),
          ],
        ],
      );
    });
  }
}
