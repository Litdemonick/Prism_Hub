import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:prismhub/controllers/detail_controller.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/platform_widget.dart';

class DetailFavoriteButton extends StatefulWidget {
  const DetailFavoriteButton({
    super.key,
    this.tag,
    this.compacto = false,
  });
  final String? tag;

  /// Solo el icono, sin la palabra "Favorito".
  ///
  /// En horizontal el titulo comparte fila con los botones, y este ocupaba 140
  /// puntos para decir algo que el corazon ya dice. Ese ancho es justo el que
  /// le faltaba al titulo para no cortarse.
  final bool compacto;

  @override
  fluent.State<DetailFavoriteButton> createState() =>
      _DetailFavoriteButtonState();
}

class _DetailFavoriteButtonState extends State<DetailFavoriteButton> {
  late DetailPageController c = Get.find<DetailPageController>(tag: widget.tag);

  Widget _buildAndroid(BuildContext context) {
    return Obx(
      () {
        final isFavorite = c.isFavorite.value;
        if (widget.compacto) {
          return IconButton(
            tooltip: isFavorite
                ? 'detail.favorited'.i18n
                : 'detail.favorite'.i18n,
            icon: Icon(
              isFavorite ? Icons.favorite : Icons.favorite_border,
              color: isFavorite ? Theme.of(context).colorScheme.primary : null,
            ),
            onPressed: () async {
              await c.toggleFavorite(context);
            },
          );
        }
        return OutlinedButton.icon(
          icon: Icon(isFavorite ? Icons.favorite : Icons.favorite_border),
          label: Text(
            isFavorite ? 'detail.favorited'.i18n : 'detail.favorite'.i18n,
          ),
          style: ButtonStyle(
            minimumSize: WidgetStateProperty.all(
              const Size(double.infinity, 50),
            ),
            backgroundColor: isFavorite
                ? WidgetStateProperty.all(Theme.of(context).colorScheme.primary)
                : null,
            foregroundColor: isFavorite
                ? WidgetStateProperty.all(
                    Theme.of(context).colorScheme.onPrimary)
                : null,
          ),
          onPressed: () async {
            await c.toggleFavorite(context);
          },
        );
      },
    );
  }

  Widget _buildDesktop(BuildContext context) {
    return Obx(() {
      final isFavorite = c.isFavorite.value;
      return fluent.Button(
        style: fluent.ButtonStyle(
          backgroundColor: fluent.WidgetStateProperty.all(
            isFavorite
                ? HomeTheme.accentPink.withValues(alpha: 0.18)
                : HomeTheme.cardSurface,
          ),
          foregroundColor: fluent.WidgetStateProperty.all(
            isFavorite ? HomeTheme.accentPink : HomeTheme.textPrimary,
          ),
          shape: fluent.WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
              side: BorderSide(
                color: isFavorite ? HomeTheme.accentPink : HomeTheme.border,
              ),
            ),
          ),
        ),
        onPressed: () async {
          await c.toggleFavorite(context);
        },
        child: Padding(
          padding:
              const EdgeInsets.only(left: 10, right: 10, top: 5, bottom: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: isFavorite
                ? [
                    Text('detail.favorited'.i18n),
                    const SizedBox(width: 8),
                    const Icon(fluent.FluentIcons.favorite_star_fill, size: 14)
                  ]
                : [
                    Text('detail.favorite'.i18n),
                    const SizedBox(width: 8),
                    const Icon(fluent.FluentIcons.favorite_star, size: 14)
                  ],
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return PlatformBuildWidget(
      androidBuilder: _buildAndroid,
      desktopBuilder: _buildDesktop,
    );
  }
}
