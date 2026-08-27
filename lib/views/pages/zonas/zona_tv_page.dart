import 'package:flutter/material.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/zona_en_creacion.dart';

/// TV/streaming en vivo — todavía no hay ninguna extensión que declare este
/// tipo de contenido, así que por ahora solo se deja el lugar puesto (mismo
/// criterio que ya usa Android TV con `_CategoriaTV.tv`, `home_page_tv.dart`).
///
/// En PC se llega por ruta (`/tv`) dentro del shell — ahí la flecha de
/// volver ya la pone la barra superior de Fluent, así que no hace falta
/// ninguna acá. En Android no es una pestaña —se llega desde los "..." del
/// riel, no del bottom-nav, para no sumarle un ícono más a una barra que ya
/// viene justa de espacio— y se empuja con `Get.to`, así que ahí SÍ hace
/// falta una salida propia. `Navigator.canPop` distingue los dos casos sin
/// necesidad de un parámetro aparte.
class ZonaTvPage extends StatelessWidget {
  const ZonaTvPage({super.key});

  @override
  Widget build(BuildContext context) {
    final puedeVolver = Navigator.of(context).canPop();
    return Scaffold(
      backgroundColor: HomeTheme.bg,
      body: SafeArea(
        child: Stack(
          children: [
            Center(child: ZonaEnCreacion(titulo: 'home.tv-canales'.i18n)),
            if (puedeVolver)
              Positioned(
                left: 4,
                top: 4,
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.arrow_back_rounded,
                      color: HomeTheme.textPrimary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
