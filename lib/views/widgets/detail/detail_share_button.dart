import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:prismhub/controllers/detail_controller.dart';
import 'package:prismhub/utils/compartir.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/views/widgets/messenger.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/platform_widget.dart';

/// Botón de compartir de la ficha. Vale igual para lectura y para vídeo: lo
/// que se comparte es la obra, no cómo se consume.
///
/// Calcado de DetailFavoriteButton para que entre en el mismo lugar sin tocar
/// el diseño de la ficha en ninguna de las dos plataformas.
class DetailShareButton extends StatelessWidget {
  const DetailShareButton({super.key, this.tag, this.compacto = false});

  final String? tag;

  /// Solo el icono, sin texto ni ancho propio.
  ///
  /// En la cabecera de la ficha de Android este boton comparte fila con
  /// "Continuar" y "Favorito", que ya se reparten el ancho. Puesto ahi como
  /// boton normal —con ancho minimo infinito, como el de favorito— desbordaba
  /// la fila y no se veia en pantalla.
  final bool compacto;

  DetailPageController get _c => Get.find<DetailPageController>(tag: tag);

  /// El rectángulo del propio botón: el menú del sistema se ancla ahí en vez
  /// de aparecer en una esquina cualquiera (y en iPad, sin esto, revienta).
  Rect? _origen(BuildContext context) {
    final caja = context.findRenderObject() as RenderBox?;
    if (caja == null || !caja.hasSize) return null;
    return caja.localToGlobal(Offset.zero) & caja.size;
  }

  Future<void> _compartir(BuildContext context) async {
    final copiado = await Compartir.compartirDetalle(
      titulo: _c.detail?.title ?? '',
      package: _c.package,
      url: _c.url,
      // Se marca en el enlace para que, al abrirlo, el otro app sepa que hay
      // que pedir permiso ANTES de mostrar nada. Ver la puerta en el router.
      adulto: _c.isAdultOption,
      // Para redactar el mensaje según con qué se abre esto: no es lo mismo
      // "disfrutá esta lectura" que "disfrutá este vídeo".
      tipo: _c.type,
      portada: _c.detail?.cover ?? '',
      origen: _origen(context),
    );
    // En escritorio no hay menú de compartir, así que el enlace queda copiado
    // y hay que decirlo: sin aviso, el botón parece que no hizo nada.
    if (copiado && context.mounted) {
      showPlatformSnackbar(
        context: context,
        content: 'detail.share-copied'.i18n,
      );
    }
  }

  Widget _buildAndroid(BuildContext context) {
    if (compacto) {
      // Mismo molde que el compacto de favorito: los dos viven en la barra de
      // arriba y tienen que medir igual.
      return IconButton(
        tooltip: 'detail.share'.i18n,
        color: HomeTheme.textPrimary,
        icon: const Icon(Icons.share_outlined),
        onPressed: () => _compartir(context),
      );
    }
    return OutlinedButton.icon(
      icon: const Icon(Icons.share_outlined),
      label: Text('detail.share'.i18n),
      style: ButtonStyle(
        minimumSize: WidgetStateProperty.all(const Size(double.infinity, 42)),
      ),
      onPressed: () => _compartir(context),
    );
  }

  Widget _buildDesktop(BuildContext context) {
    // Compacto: solo el icono, para la barra de arriba de la ficha. Ver el
    // mismo caso en DetailFavoriteButton.
    if (compacto) {
      return fluent.IconButton(
        icon: const Icon(fluent.FluentIcons.share, size: 18),
        onPressed: () => _compartir(context),
      );
    }
    return fluent.Button(
      style: fluent.ButtonStyle(
        backgroundColor: fluent.WidgetStateProperty.all(HomeTheme.cardSurface),
        foregroundColor: fluent.WidgetStateProperty.all(HomeTheme.textPrimary),
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
