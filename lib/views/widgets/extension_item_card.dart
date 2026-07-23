import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:prismhub/models/extension.dart';
import 'package:prismhub/views/pages/detail_page.dart';
import 'package:prismhub/router/router.dart';
import 'package:prismhub/views/widgets/grid_item_tile.dart';
import 'package:prismhub/views/widgets/platform_widget.dart';

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
  });
  final String title;
  final String? cover;
  final String? update;
  final String url;
  final String package;
  final Map<String, String>? headers;
  // Solo se pasa desde Home — en el resto de la app queda null.
  final ExtensionType? type;

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
      onTap: () {
        Get.to(DetailPage(
          url: widget.url,
          package: widget.package,
          tag: widget.url,
        ));
      },
    );
  }

  Widget _buildDesktop(BuildContext context) {
    return GridItemTile(
      title: widget.title,
      cover: widget.cover,
      subtitle: widget.update,
      headers: widget.headers,
      type: widget.type,
      onTap: () {
        router.push(
          Uri(
            path: '/detail',
            queryParameters: {
              "url": widget.url,
              "package": widget.package,
            },
          ).toString(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PlatformBuildWidget(
      androidBuilder: _buildAndroid,
      desktopBuilder: _buildDesktop,
    );
  }
}
