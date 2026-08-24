import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:flutter/material.dart';
import 'package:prismhub/models/extension.dart';
import 'package:prismhub/views/widgets/cover.dart';
import 'package:prismhub/views/widgets/extension_type_badge.dart';
import 'package:prismhub/views/widgets/platform_widget.dart';

class GridItemTile extends StatefulWidget {
  const GridItemTile({
    super.key,
    required this.title,
    this.cover,
    this.subtitle,
    this.onTap,
    this.headers,
    this.type,
    this.onTamanoReal,
  });
  final String title;
  final String? cover;
  final String? subtitle;
  final Function()? onTap;
  final Map<String, String>? headers;
  // Solo se pasa desde Home (Continuar/Favoritos) — en el resto de la app
  // queda null y no se dibuja nada.
  final ExtensionType? type;

  /// El tamaño en píxeles de la portada, para saber qué forma tiene.
  final void Function(int ancho, int alto)? onTamanoReal;

  @override
  State<GridItemTile> createState() => _GridItemTileState();
}

class _GridItemTileState extends State<GridItemTile> {
  bool _isHover = false;

  Widget _buildAndroid(BuildContext context) {
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Cover(
            alt: widget.title,
            url: widget.cover,
            headers: widget.headers,
            onTamanoReal: widget.onTamanoReal,
          ),
        ),
        if (widget.type != null)
          Positioned(
            top: 6,
            left: 6,
            child: ExtensionTypeBadge(type: widget.type!),
          ),
        Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              width: 350,
              height: 60,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.all(Radius.circular(8)),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.8),
                  ],
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  // 文字只显示一行
                  SizedBox(
                    height: 20,
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      // ENCIMA de la portada, y por eso blanco fijo.
                      //
                      // Este bloque es un Positioned dentro del Stack de la
                      // tarjeta: va sobre la imagen, con el degradado negro de
                      // acá arriba como fondo. O sea que el fondo NO es el de
                      // la app y no sigue al modo.
                      //
                      // Estaba en textPrimary, que en modo claro es casi negro:
                      // texto negro sobre el velo negro de la portada. Se leía
                      // como que el título directamente no estaba.
                      //
                      // Ver HomeTheme.sobrePortada, que existe justo para esto.
                      style: const TextStyle(
                        color: HomeTheme.sobrePortada,
                      ),
                    ),
                  ),
                  if (widget.subtitle != null)
                    Text(
                      widget.subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      // Mismo caso que el título: va sobre el velo. Blanco
                      // apagado en vez de textMuted, que en claro es un gris
                      // oscuro y sobre negro tampoco se lee.
                      style: const TextStyle(
                        color: Color(0xCCFFFFFF),
                        fontSize: 10,
                      ),
                    ),
                ],
              ),
            )),
        Positioned.fill(
            child: Container(
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                widget.onTap?.call();
              },
            ),
          ),
        )),
      ],
    );
  }

  Widget _buildDesktop(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (event) {
          setState(() {
            _isHover = true;
          });
        },
        onExit: (event) {
          setState(() {
            _isHover = false;
          });
        },
        child: Column(
          // 居左
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    AnimatedScale(
                      scale: _isHover ? 1.05 : 1,
                      duration: const Duration(milliseconds: 80),
                      child: Cover(
                        alt: widget.title,
                        url: widget.cover,
                        headers: widget.headers,
                        onTamanoReal: widget.onTamanoReal,
                      ),
                    ),
                    if (widget.type != null)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: ExtensionTypeBadge(type: widget.type!),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            // 文字只显示一行
            // Acá SÍ va el color del modo, y con el color puesto a mano.
            //
            // En escritorio el título va DEBAJO de la portada, sobre el fondo
            // de la página: es lo contrario del teléfono, donde va encima de la
            // imagen. Así que el que corresponde es textPrimary.
            //
            // No tenía ningún estilo, y sin color el texto cae en la tipografía
            // de Fluent, que trae la suya según SU tema: quedaba blanco sobre
            // el fondo claro y no se veía ni un título en toda la grilla. Es lo
            // mismo que le pasaba al título de las filas del Inicio.
            SizedBox(
              height: 20,
              child: Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: HomeTheme.textPrimary),
              ),
            ),
            if (widget.subtitle != null)
              Text(
                widget.subtitle.toString(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: HomeTheme.textMuted,
                ),
              ),
          ],
        ),
      ),
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
