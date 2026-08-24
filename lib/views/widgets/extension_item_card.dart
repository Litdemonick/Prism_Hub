import 'package:flutter/material.dart';
import 'package:prismhub/models/extension.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/utils/forma_portada.dart';
import 'package:prismhub/utils/platform_tv.dart';
import 'package:prismhub/views/widgets/grid_item_tile.dart';
import 'package:prismhub/views/widgets/platform_widget.dart';
import 'package:prismhub/views/widgets/tv/focusable_card.dart';

class ExtensionItemCard extends StatefulWidget {
  const ExtensionItemCard({
    super.key,
    required this.title,
    required this.url,
    required this.package,
    this.cover,
    this.update,
    this.headers,
    this.type,
    this.isAdultOption = false,
  });
  final String title;
  final String? cover;
  final String? update;
  final String url;
  final String package;
  final Map<String, String>? headers;
  // Solo se pasa desde Home — en el resto de la app queda null.
  final ExtensionType? type;
  // Zona +18: true cuando este resultado vino de la opción "adultos" de un
  // filtro de una extensión mixta (ver
  // ExtensionSearcherPage._adultOptionSelected). Viaja hasta DetailPage
  // para que el Favorite/History que se guarde desde ahí quede marcado +18.
  final bool isAdultOption;

  @override
  State<ExtensionItemCard> createState() => _ExtensionItemCardState();
}

class _ExtensionItemCardState extends State<ExtensionItemCard> {
  Widget _buildAndroid(BuildContext context) {
    // Sin Hero: envolvía toda la tarjeta (imagen + título + badge +
    // degradado) pero del otro lado (detail_appbar_flexible_space.dart) el
    // Hero es solo una imagen chica sin texto — Flutter tenía que
    // transformar una forma en la otra durante el vuelo, y esa mezcla de
    // formas tan distintas se veía como que las tarjetas "se movían" mal
    // al entrar/salir del detalle.
    return GridItemTile(
      title: widget.title,
      cover: widget.cover,
      subtitle: widget.update,
      headers: widget.headers,
      type: widget.type,
      // Se aprovecha la portada que ya se descargó para saber si esta
      // extensión publica pósters verticales o fotogramas apaisados, y armar
      // la grilla con la forma que le corresponde. Ver FormaPortada.
      onTamanoReal: (ancho, alto) =>
          FormaPortada.anotar(widget.package, ancho, alto),
      onTap: () => ExtensionUtils.openExtensionDetail(
        context,
        package: widget.package,
        url: widget.url,
        isAdultOption: widget.isAdultOption,
        // La portada de esta tarjeta ya está descargada y a la vista. Se la
        // pasa para que la ficha abra con imagen en vez de esperar a que la
        // extensión conteste y recién ahí empezar a bajar otra.
        cover: widget.cover,
        coverHeaders: widget.headers,
      ),
    );
  }

  Widget _buildDesktop(BuildContext context) {
    return GridItemTile(
      title: widget.title,
      cover: widget.cover,
      subtitle: widget.update,
      headers: widget.headers,
      type: widget.type,
      // Se aprovecha la portada que ya se descargó para saber si esta
      // extensión publica pósters verticales o fotogramas apaisados, y armar
      // la grilla con la forma que le corresponde. Ver FormaPortada.
      onTamanoReal: (ancho, alto) =>
          FormaPortada.anotar(widget.package, ancho, alto),
      onTap: () => ExtensionUtils.openExtensionDetail(
        context,
        package: widget.package,
        url: widget.url,
        isAdultOption: widget.isAdultOption,
        // La portada de esta tarjeta ya está descargada y a la vista. Se la
        // pasa para que la ficha abra con imagen en vez de esperar a que la
        // extensión conteste y recién ahí empezar a bajar otra.
        cover: widget.cover,
        coverHeaders: widget.headers,
      ),
    );
  }

  /// Abre la ficha de este ítem. Es lo mismo que hace el `onTap` de las dos
  /// variantes de arriba — extraído para que la envoltura de foco de TV no
  /// tenga que repetir la lista de argumentos.
  void _abrir(BuildContext context) => ExtensionUtils.openExtensionDetail(
        context,
        package: widget.package,
        url: widget.url,
        isAdultOption: widget.isAdultOption,
        cover: widget.cover,
        coverHeaders: widget.headers,
      );

  @override
  Widget build(BuildContext context) {
    final tarjeta = PlatformBuildWidget(
      androidBuilder: _buildAndroid,
      desktopBuilder: _buildDesktop,
    );
    if (!PlatformTv.esTelevisionSync) return tarjeta;
    // En TV la tarjeta se envuelve para que el D-pad pueda enfocarla. El
    // `IgnorePointer` apaga el `onTap` que la tarjeta ya trae adentro: con
    // los dos activos, un solo click abría la ficha DOS veces (ninguno de
    // los dos gestos "gana" — no compiten por un arrastre, así que ambos
    // reconocen el toque).
    return FocusableCard(
      borderRadius: 10,
      onTap: () => _abrir(context),
      child: IgnorePointer(child: tarjeta),
    );
  }
}
