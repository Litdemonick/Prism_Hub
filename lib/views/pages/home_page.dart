import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:prismhub/controllers/catalogo_extensiones_controller.dart';
import 'package:prismhub/controllers/main_controller.dart';
import 'package:prismhub/controllers/zona_catalogo_controller.dart';
import 'package:prismhub/models/index.dart';
import 'package:prismhub/router/router.dart';
import 'package:prismhub/utils/breakpoints.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/platform_tv.dart';
import 'package:prismhub/utils/zonas_preferidas.dart';
import 'package:prismhub/views/pages/extension/extension_repo_page.dart';
import 'package:prismhub/views/pages/history_page.dart';
import 'package:prismhub/views/pages/library_page.dart';
import 'package:prismhub/views/pages/search/search_page.dart';
import 'package:prismhub/views/widgets/cache_network_image.dart';
import 'package:prismhub/views/pages/home/ultimas_actualizaciones_mangadex_page.dart';
import 'package:prismhub/views/widgets/home/animated_background_glow.dart';
import 'package:prismhub/views/widgets/home/esqueleto.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/home/indicadores_de_pagina.dart';
import 'package:prismhub/views/widgets/home/panel_info_hover.dart';
import 'package:prismhub/views/widgets/home/refresh_button.dart';
import 'package:prismhub/views/widgets/home/tarjeta_de_catalogo.dart';
import 'package:prismhub/views/widgets/tv/focusable_card.dart';
import 'package:prismhub/views/widgets/home/zona_sin_clasificar.dart';
import 'package:prismhub/views/widgets/zona_en_creacion.dart';

// ── Por qué está partido en tres archivos ───────────────────────────────────
//
// Celular y escritorio no son la misma pantalla con distinto ancho: son dos
// aparatos distintos. En uno se toca con el pulgar, la pantalla es alta y
// angosta y no hay dónde apoyar el cursor; en el otro hay mouse, sobra ancho y
// pasar por encima de algo es un gesto que existe. Meter los dos en el mismo
// widget terminaba en un `if` por cada propiedad, y cada arreglo de un lado era
// un riesgo del otro.
//
// Así que cada uno tiene sus widgets, en su archivo:
//
//   home_page_android.dart   celular y tablet: se desliza con el dedo
//   home_page_windows.dart   escritorio: fondo a sangre y filas con flechas
//
// Son `part` de esta misma biblioteca y no archivos sueltos, a propósito: así
// comparten las piezas de abajo —los indicadores, la fila inactiva, el margen—
// sin tener que volverlas públicas ni armar un tercer archivo de utilidades que
// nadie sabría dónde buscar.
part 'home_page_android.dart';
part 'home_page_windows.dart';
part 'home_page_tv.dart';

/// El Home: **descubrir, con lo que traen tus extensiones**.
///
/// ── Por qué está partido de la Biblioteca ─────────────────────────────────
///
/// Antes Home era «lo mío»: Continuar viendo y Favoritos. Eso pasó tal cual a
/// `library_page.dart`. Lo que cambió es que ahora cada pantalla tiene una
/// regla clara sobre estar vacía:
///
///   Biblioteca vacía  →  está bien. Todavía no viste nada.
///   Home vacío        →  está mal. Es la pantalla de descubrir.
///
/// Acá NO va «Seguir viendo»: eso ya vive en Biblioteca y repetirlo sería
/// gastar la mejor franja de la pantalla en algo que el usuario ya tiene a un
/// toque.
///
/// ── Cómo aguanta muchas extensiones ───────────────────────────────────────
///
/// Todo el trabajo pesado está en [CatalogoExtensionesController]: nada se
/// pide hasta que se ve, ninguna fila espera a otra, tope de tres a la vez,
/// caché en disco y una fila caída no rompe el resto. Acá solo se dibuja.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  // Se reusa si ya existe: en Android, cambiar de pestaña reconstruye la
  // página entera, y crear otro tiraría el catálogo ya cargado.
  late final CatalogoExtensionesController c =
      Get.isRegistered<CatalogoExtensionesController>()
          ? Get.find<CatalogoExtensionesController>()
          : Get.put(CatalogoExtensionesController());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Reportado en vivo en un Samsung A54: a veces, al volver la app de segundo
  // plano, el scroll del Home queda "pegado" y no responde más al dedo. No se
  // pudo reproducir acá (funciona en PC y en los Android de prueba), así que
  // no hay forma de confirmar la causa exacta — pero es un síntoma conocido
  // en Android cuando el sistema (más agresivo en algunas capas como One UI)
  // suspende la superficie de dibujo en segundo plano y Flutter no siempre
  // la relayoutea sola al volver.
  //
  // Un setState acá fuerza un relayout/repintado completo del árbol al
  // volver a primer plano. Es de bajo riesgo (un solo rebuild extra, nunca en
  // primer plano) aunque no esté confirmado que sea LA causa — si el reporte
  // vuelve a repetirse después de esto, hace falta más detalle de en qué
  // momento pasa para seguir buscando.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: HomeTheme.bg,
      child: Stack(
        children: [
          const Positioned.fill(child: AnimatedBackgroundGlow()),
          // El fondo animado es el mismo para las tres. De acá para abajo,
          // cada plataforma arma su Home entero.
          //
          // TV primero: un Android TV sigue siendo `Platform.isAndroid ==
          // true`, así que si no se pregunta ACÁ primero, `_esTactil` se lo
          // lleva puesto y termina en HomeAndroid, con controles pensados
          // para el dedo y nada de foco D-pad.
          _esTelevision
              ? HomeTV(c: c)
              : (_esTactil ? HomeAndroid(c: c) : HomeWindows(c: c)),
        ],
      ),
    );
  }
}

/// Qué Home se dibuja.
///
/// Va por plataforma y NO por ancho de pantalla, y es a propósito: son
/// diseños distintos, no uno que se estira. El ancho sigue mandando ADENTRO de
/// cada uno —cuántas columnas entran, qué tan grande es el título— y para eso
/// está `Ancho`.
///
/// En escritorio el Home queda exactamente como estaba, se achique la ventana
/// hasta donde se achique.
/// Una sola definición, en `platform_tv.dart`. Estaba escrita también en
/// `tarjeta_de_catalogo.dart`, con el mismo cuerpo copiado.
bool get _esTactil => esPantallaTactil;

/// Si esto es un Android TV. Se pregunta ANTES que [_esTactil] en el
/// bifurcado de arriba — ver el comentario ahí.
bool get _esTelevision => PlatformTv.esTelevisionSync;

// ─── Piezas compartidas ──────────────────────────────────────────────────────

/// No hay ninguna extensión que pueda traer contenido.
class _SinExtensiones extends StatelessWidget {
  const _SinExtensiones();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.extension_outlined,
                size: 44, color: HomeTheme.textMuted),
            const SizedBox(height: 14),
            Text(
              'home.sin-extensiones'.i18n,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.45,
                color: HomeTheme.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Una extensión que el usuario tiene apagada, o que ni instaló.
///
/// Sale en el Home igual que las demás, y es a propósito: escondidas, nadie se
/// entera de que existen. Lo que cambia es que en lugar de portadas lleva una
/// línea con lo único que falta para que traigan contenido — prenderla o
/// instalarla.
///
/// Ocupa poco: van al final de la lista y no tienen que competir con las que sí
/// están andando.
class _FilaInactiva extends StatelessWidget {
  const _FilaInactiva({required this.fila, required this.c});

  final FilaDeExtension fila;
  final CatalogoExtensionesController c;

  bool get _sinInstalar => fila.estadoExt == EstadoExtension.noInstalada;

  Future<void> _accion(BuildContext context) async {
    if (_sinInstalar) {
      // No se instala desde acá: instalar pide bajar el guion y verificar su
      // firma, y eso ya vive —bien hecho— en el repositorio. Se lleva al
      // usuario ahí, con la extensión ya buscada para que no tenga que
      // encontrarla entre decenas.
      ExtensionUtils.filtroPendiente = fila.nombre;
      if (Platform.isAndroid) {
        Get.find<MainController>().changeTab(MainController.tabExtensiones);
      } else {
        router.go('/extension_repo');
      }
      return;
    }
    // Prender sí se puede desde acá: es un interruptor, no una descarga.
    await ExtensionUtils.setExtensionEnabled(fila.package, true);
    await c.recargar();
  }

  @override
  Widget build(BuildContext context) {
    final margen = _margen(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(margen, 10, margen, 0),
      child: Row(
        children: [
          Icon(
            _sinInstalar ? Icons.download_outlined : Icons.toggle_off_outlined,
            size: 18,
            color: HomeTheme.textMuted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              fila.nombre,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: HomeTheme.textMuted,
              ),
            ),
          ),
          TextButton(
            onPressed: () => _accion(context),
            child: Text(
              _sinInstalar ? 'common.install'.i18n : 'home.activar'.i18n,
            ),
          ),
        ],
      ),
    );
  }
}

/// La extensión no respondió y no hay nada guardado que mostrar.
///
/// Se deja una línea discreta con su botón: esconderla del todo haría que el
/// usuario no entienda por qué falta una extensión que sabe que instaló.
class _SinRespuesta extends StatelessWidget {
  const _SinRespuesta({required this.fila, required this.c});

  final FilaDeExtension fila;
  final CatalogoExtensionesController c;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(_margen(context), 22, _margen(context), 0),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, size: 16, color: HomeTheme.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${fila.nombre} · ${'home.fila-sin-respuesta'.i18n}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: HomeTheme.textMuted),
            ),
          ),
          TextButton(
            onPressed: () => c.pedirSiHaceFalta(fila, forzar: true),
            child: Text('common.retry'.i18n),
          ),
        ],
      ),
    );
  }
}

/// El margen lateral, por ancho de pantalla.
///
/// En una ventana ancha el contenido pegado al borde se ve barato; en un
/// teléfono cada píxel cuenta. Va por ancho y no por sistema operativo para
/// que también acompañe al achicar la ventana en escritorio.
double _margen(BuildContext context) =>
    Ancho.de(context).elegir(compacto: 14, medio: 20, amplio: 32, enorme: 48);

Map<String, String>? _cabeceras(String package) {
  final sitio = ExtensionUtils.runtimes[package]?.extension.webSite;
  if (sitio == null || sitio.isEmpty) return null;
  return {'Referer': sitio};
}

void _abrir(BuildContext context, ExtensionListItem item, String package) {
  ExtensionUtils.openExtensionDetail(
    context,
    package: package,
    url: item.url,
    // La portada que la tarjeta YA está mostrando: así la ficha abre con
    // imagen en vez de con un hueco mientras la extensión contesta.
    cover: item.cover,
    coverHeaders: _cabeceras(package),
  );
}
