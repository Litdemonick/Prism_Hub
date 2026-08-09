import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:prismhub/controllers/detail_controller.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/platform_widget.dart';

/// Botón para marcar que la OBRA terminó de publicarse.
///
/// No se muestra en contenido de un solo capítulo/episodio (una película):
/// ahí no hay nada que "terminar de publicar". Ver
/// [DetailPageController.isSerialized] — la decisión se toma por el ítem, no
/// por el tipo de extensión, porque hay extensiones de vídeo con películas y
/// mixtas con las dos cosas.
///
/// Es distinto de estar al día: eso lo lleva `watchState` y se calcula solo.
/// Acá el usuario informa algo que la extensión muchas veces no dice, o dice
/// con un vocabulario propio de cada sitio.
class DetailFinishedButton extends StatefulWidget {
  const DetailFinishedButton({super.key, this.tag});
  final String? tag;

  @override
  State<DetailFinishedButton> createState() => _DetailFinishedButtonState();
}

class _DetailFinishedButtonState extends State<DetailFinishedButton> {
  late final DetailPageController c =
      Get.find<DetailPageController>(tag: widget.tag);

  Widget _buildAndroid(BuildContext context) {
    return Obx(() {
      final marcado = c.isSeriesFinished.value;
      return OutlinedButton.icon(
        icon: Icon(marcado
            ? Icons.check_circle_rounded
            : Icons.check_circle_outline_rounded),
        label: Text(
          marcado ? 'detail.finished-marked'.i18n : 'detail.finished'.i18n,
        ),
        // ── Relleno sólido, no contorno pálido ────────────────────────────
        //
        // Estaba con el fondo del acento al 18% y el texto en ese mismo acento.
        // Sobre el fondo oscuro se leía; sobre el claro quedaba un rosa lavado
        // encima de casi blanco, y ni el texto ni el icono se distinguían.
        //
        // Relleno sólido con el texto en el color opuesto: se lee igual en los
        // dos modos y además se ve que es un botón, que antes tampoco quedaba
        // claro. Sin marcar sigue de contorno, que es lo correcto para una
        // acción secundaria.
        style: ButtonStyle(
          minimumSize: WidgetStateProperty.all(const Size(double.infinity, 50)),
          backgroundColor:
              marcado ? WidgetStateProperty.all(HomeTheme.accentPink) : null,
          foregroundColor: WidgetStateProperty.all(
            marcado ? HomeTheme.sobrePortada : HomeTheme.accentPink,
          ),
          side: marcado
              ? null
              : WidgetStateProperty.all(
                  BorderSide(color: HomeTheme.accentPink),
                ),
        ),
        onPressed: () => c.toggleSeriesFinished(context),
      );
    });
  }

  Widget _buildDesktop(BuildContext context) {
    return Obx(() {
      final marcado = c.isSeriesFinished.value;
      return fluent.Button(
        style: fluent.ButtonStyle(
          backgroundColor: fluent.WidgetStateProperty.all(
            marcado
                ? HomeTheme.accentPink.withValues(alpha: 0.18)
                : HomeTheme.cardSurface,
          ),
          foregroundColor: fluent.WidgetStateProperty.all(
            marcado ? HomeTheme.accentPink : HomeTheme.textPrimary,
          ),
          shape: fluent.WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
              side: BorderSide(
                color: marcado ? HomeTheme.accentPink : HomeTheme.border,
              ),
            ),
          ),
        ),
        onPressed: () => c.toggleSeriesFinished(context),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              marcado
                  ? fluent.FluentIcons.completed_solid
                  : fluent.FluentIcons.completed,
              size: 16,
            ),
            const SizedBox(width: 8),
            Text(
              marcado ? 'detail.finished-marked'.i18n : 'detail.finished'.i18n,
            ),
          ],
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // Obx exterior: isSerialized depende del detalle, que llega después del
    // primer build. Sin esto el botón no aparecería nunca en la primera
    // apertura, solo al volver a entrar.
    return Obx(() {
      // Se lee un observable para que este Obx tenga de qué depender: el
      // detalle se carga junto con el favorito, así que sirve de disparador.
      c.isFavorite.value;
      if (!c.isSerialized) return const SizedBox.shrink();
      return PlatformBuildWidget(
        androidBuilder: _buildAndroid,
        desktopBuilder: _buildDesktop,
      );
    });
  }
}
