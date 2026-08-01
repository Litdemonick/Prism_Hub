import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:prismhub/controllers/detail_controller.dart';
import 'package:prismhub/utils/compartir.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/platform_widget.dart';

/// Botón de compartir de la ficha. Vale igual para lectura y para vídeo: lo
/// que se comparte es la obra, no cómo se consume.
///
/// Calcado de DetailFavoriteButton para que entre en el mismo lugar sin tocar
/// el diseño de la ficha en ninguna de las dos plataformas.
class DetailShareButton extends StatelessWidget {
  const DetailShareButton({super.key, this.tag});

  final String? tag;

  DetailPageController get _c => Get.find<DetailPageController>(tag: tag);

  /// El rectángulo del propio botón: el menú del sistema se ancla ahí en vez
  /// de aparecer en una esquina cualquiera (y en iPad, sin esto, revienta).
  Rect? _origen(BuildContext context) {
    final caja = context.findRenderObject() as RenderBox?;
    if (caja == null || !caja.hasSize) return null;
    return caja.localToGlobal(Offset.zero) & caja.size;
  }

  Future<void> _compartir(BuildContext context) async {
    await Compartir.compartirDetalle(
      titulo: _c.detail?.title ?? '',
      package: _c.package,
      url: _c.url,
      // Se marca en el enlace para que, al abrirlo, el otro app sepa que hay
      // que pedir permiso ANTES de mostrar nada. Ver la puerta en el router.
      adulto: _c.isAdultOption,
      origen: _origen(context),
    );
  }

  Widget _buildAndroid(BuildContext context) {
    return OutlinedButton.icon(
      icon: const Icon(Icons.share_outlined),
      label: Text('detail.share'.i18n),
      style: ButtonStyle(
        minimumSize: WidgetStateProperty.all(const Size(double.infinity, 50)),
      ),
      onPressed: () => _compartir(context),
    );
  }

  Widget _buildDesktop(BuildContext context) {
    return fluent.Button(
      style: fluent.ButtonStyle(
        backgroundColor:
            fluent.WidgetStateProperty.all(HomeTheme.cardSurface),
        foregroundColor:
            fluent.WidgetStateProperty.all(HomeTheme.textPrimary),
        shape: fluent.WidgetStateProperty.all(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
            side: const BorderSide(color: HomeTheme.border),
          ),
        ),
      ),
      onPressed: () => _compartir(context),
      child: Padding(
        padding: const EdgeInsets.only(left: 10, right: 10, top: 5, bottom: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('detail.share'.i18n),
            const SizedBox(width: 8),
            const Icon(fluent.FluentIcons.share, size: 14),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PlatformBuildWidget(
        androidBuilder: _buildAndroid,
        desktopBuilder: _buildDesktop,
      );
}
