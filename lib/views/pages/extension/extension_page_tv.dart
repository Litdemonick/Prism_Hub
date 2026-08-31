import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:get/get.dart';
import 'package:prismhub/controllers/extension/extension_controller.dart';
import 'package:prismhub/controllers/main_controller.dart';
import 'package:prismhub/data/services/extension_service.dart';
import 'package:prismhub/models/extension.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/prismhub_mas.dart';
import 'package:prismhub/utils/search_text.dart';
import 'package:prismhub/views/pages/extension/acciones_masivas.dart';
import 'package:prismhub/views/pages/extension/extension_repo_page.dart';
import 'package:prismhub/views/pages/extension/extension_settings_page.dart';
import 'package:prismhub/views/widgets/cache_network_image.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/messenger.dart';
import 'package:prismhub/views/widgets/tv/columna_de_acciones.dart';
import 'package:prismhub/views/widgets/tv/focusable_card.dart';
import 'package:prismhub/views/widgets/tv/pantalla_tv.dart';
import 'package:prismhub/views/widgets/tv/teclado_tv.dart';

/// Las extensiones instaladas, para televisor.
///
/// ── Por qué no es la de teléfono con retoques ───────────────────────────
///
/// Porque lo era, y no alcanzaba. `ExtensionPage` está pensada para el dedo:
/// una lista paginada que se cambia deslizando, una barra de chips arriba que
/// se parte en dos renglones, un menú de tres puntitos con las acciones
/// masivas adentro, y un interruptor Material de 40 px por fila. Con un mando
/// eso son decenas de pulsaciones para llegar a cualquier cosa, y desde el
/// sillón los chips y el interruptor directamente no se leen. Reportado en
/// vivo, dos veces: «me voy a la zona de extensiones y es la misma verga, los
/// mismos botones arriba, no cambiaste ni mierda».
///
/// ── La forma ────────────────────────────────────────────────────────────
///
/// El molde de televisor de esta app, el mismo que ya usan el registro y el
/// historial: título arriba a la izquierda con su flecha de volver, las
/// funciones en una columna al costado izquierdo, y el contenido ocupando
/// todo lo que queda a la derecha.
///
/// Con un mando eso vale más que en pantalla táctil: desde cualquier punto de
/// la lista, IZQUIERDA cae en los filtros y las acciones y DERECHA vuelve.
/// Una pulsación, esté donde esté el desplazamiento. Sin eso, llegar a un
/// filtro desde el final de una lista de diecinueve son diecinueve flechas
/// hacia arriba.
///
/// ── Y por qué la lista es de filas anchas y no de tarjetas ──────────────
///
/// Porque lo que se hace acá es leer un nombre y prender o apagar. Una
/// cuadrícula de tarjetas obliga a moverse en dos ejes para recorrer algo que
/// es una lista, y encima achica el nombre — que es el único dato que
/// importa. Las filas usan el ancho entero: nombre grande a la izquierda,
/// estado a la derecha, y de un vistazo se ve la columna de encendidas.
class ExtensionPageTv extends StatefulWidget {
  const ExtensionPageTv({super.key});

  @override
  State<ExtensionPageTv> createState() => _ExtensionPageTvState();
}

/// Los filtros de la columna. Menos que los de teléfono a propósito.
///
/// En televisor no hay lectura —regla del rediseño: acá solo se ve vídeo— así
/// que «Manga» y «Lectura» no tienen para qué estar. Lo que queda es lo que
/// alguien busca de verdad desde el sillón: por zona, y las dos listas que
/// contestan «¿qué dejó de andar?».
enum _Filtro {
  todas,
  peliculas,
  series,
  anime,
  apagadas,
  inestables;

  String get etiqueta => switch (this) {
        _Filtro.todas => 'extension.filter-all'.i18n,
        _Filtro.peliculas => 'home.zona-peliculas'.i18n,
        _Filtro.series => 'home.zona-series'.i18n,
        _Filtro.anime => 'home.zona-anime'.i18n,
        _Filtro.apagadas => 'extension.filter-disabled'.i18n,
        _Filtro.inestables => 'extension.filter-unstable'.i18n,
      };

  IconData get icono => switch (this) {
        _Filtro.todas => Icons.apps_rounded,
        _Filtro.peliculas => Icons.movie_outlined,
        _Filtro.series => Icons.tv_rounded,
        _Filtro.anime => Icons.animation_rounded,
        _Filtro.apagadas => Icons.toggle_off_outlined,
        _Filtro.inestables => Icons.warning_amber_rounded,
      };

  bool alcanza(Extension ext) => switch (this) {
        _Filtro.todas => true,
        _Filtro.peliculas =>
          ExtensionUtils.zonasDe(ext.package).contains(ZonaPrincipal.peliculas),
        _Filtro.series =>
          ExtensionUtils.zonasDe(ext.package).contains(ZonaPrincipal.series),
        _Filtro.anime =>
          ExtensionUtils.zonasDe(ext.package).contains(ZonaPrincipal.anime),
        _Filtro.apagadas => !ExtensionUtils.isEnabled(ext.package),
        _Filtro.inestables =>
          ExtensionUtils.isRemoteUnstableCached(ext.package),
      };
}

class _ExtensionPageTvState extends State<ExtensionPageTv>
    with AccionesMasivasDeExtensiones<ExtensionPageTv> {
  late final ExtensionPageController c =
      Get.isRegistered<ExtensionPageController>()
          ? Get.find<ExtensionPageController>()
          : Get.put(ExtensionPageController());

  @override
  ExtensionPageController get instaladas => c;

  _Filtro _filtro = _Filtro.todas;

  /// Lo escrito en el buscador. Vacío = no se está filtrando por nombre.
  String _busqueda = '';

  /// El teclado ocupa el sitio de los filtros mientras se escribe.
  ///
  /// No abre otra pantalla ni se superpone: en televisor una capa encima tapa
  /// justo la lista, que es lo único que hay que mirar mientras se escribe.
  /// La columna ya es del ancho del teclado, así que entra tal cual y la
  /// lista de la derecha se sigue viendo filtrándose en vivo.
  bool _escribiendo = false;

  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    c.isPageOpen = true;
    if (c.needRefresh) c.onRefresh();
  }

  @override
  void dispose() {
    c.isPageOpen = false;
    _scroll.dispose();
    super.dispose();
  }

  List<ExtensionService> get _visibles {
    final todas = c.runtimes.values.toList(growable: false);
    return todas.where((r) {
      final ext = r.extension;
      // Discreción: las +18 no salen en esta lista. En televisor la Zona +18
      // vive aparte, en Ajustes y detrás de su PIN — que aparecieran acá por
      // el simple hecho de estar instaladas sería exponerlas sin que nadie lo
      // haya pedido.
      if (ext.nsfw) return false;
      if (_busqueda.isNotEmpty &&
          !SearchText.matchesQuery(ext.name, _busqueda)) {
        return false;
      }
      return _filtro.alcanza(ext);
    }).toList()
      ..sort((a, b) => a.extension.name
          .toLowerCase()
          .compareTo(b.extension.name.toLowerCase()));
  }

  /// Cuántas caen en cada filtro, para poder mostrarlo al lado del nombre.
  ///
  /// Un filtro que va a dejar la lista vacía tiene que poder verse ANTES de
  /// elegirlo: si no, desde el sillón se siente como que la app se colgó.
  int _cuantasEn(_Filtro f) => c.runtimes.values
      .where((r) => !r.extension.nsfw && f.alcanza(r.extension))
      .length;

  Future<void> _alternar(ExtensionService r) async {
    final ext = r.extension;
    final estaba = ExtensionUtils.isEnabled(ext.package);
    // Una extensión marcada inestable no se puede ACTIVAR: se prendería y
    // recién al abrir su contenido saltaría el aviso, quedando encendida y
    // aportando resultados vacíos a la búsqueda. Apagarla siempre se permite.
    if (!estaba && ExtensionUtils.isRemoteUnstableCached(ext.package)) {
      showPlatformSnackbar(
        context: context,
        title: 'extension.unstable-title'.i18n,
        content: ExtensionUtils.unstableReasonLabel(
          ExtensionUtils.unstableReasonCached(ext.package),
        ),
      );
      return;
    }
    await ExtensionUtils.setExtensionEnabled(ext.package, !estaba);
    if (mounted) setState(() {});
  }

  void _abrirAjustesDe(ExtensionService r) {
    unawaited(
      Get.to(() => ExtensionSettingsPage(package: r.extension.package)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final visibles = _visibles;
      final total = c.runtimes.values.where((r) => !r.extension.nsfw).length;
      final activas = c.runtimes.values
          .where((r) =>
              !r.extension.nsfw &&
              ExtensionUtils.isEnabled(r.extension.package))
          .length;
      return PantallaTv(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_escribiendo) _teclado() else _columna(total, activas),
            const SizedBox(width: 24),
            Expanded(child: _lista(visibles, total)),
          ],
        ),
      );
    });
  }

  // ─── La columna de la izquierda ────────────────────────────────────────

  Widget _columna(int total, int activas) {
    final detalle = FlutterI18n.translate(
      context,
      'extension.tv-cuenta',
      translationParams: {'total': '$total', 'activas': '$activas'},
    );
    return ColumnaDeAcciones(
      titulo: 'common.extension-installed'.i18n,
      detalle: detalle,
      grupos: [
        GrupoDeColumna(opciones: [
          OpcionDeColumna(
            icono: Icons.arrow_back_rounded,
            texto: 'extension.tv-volver'.i18n,
            // Esta pantalla se abre de dos formas: como pestaña desde la
            // barra de arriba del Inicio, o empujada desde Ajustes. `Get.back`
            // a secas solo cubre la segunda — reportado en vivo: "le doy a
            // volver y no hace nada". Ver MainController.volver.
            onTap: () => MainController.volver(context),
          ),
        ]),
        GrupoDeColumna(
          titulo: 'extension.tv-buscar-y-filtrar'.i18n,
          opciones: [
            OpcionDeColumna(
              id: 'buscar',
              icono: Icons.search_rounded,
              // Con algo escrito, la opción muestra QUÉ se está buscando: si
              // no, una lista corta se lee como «no tengo extensiones» en vez
              // de «hay un texto puesto».
              texto: _busqueda.isEmpty ? 'common.search'.i18n : '«$_busqueda»',
              elegido: _busqueda.isNotEmpty,
              onTap: () => setState(() => _escribiendo = true),
            ),
            for (final f in _Filtro.values)
              OpcionDeColumna(
                id: f.name,
                icono: f.icono,
                texto: '${f.etiqueta}  ·  ${_cuantasEn(f)}',
                elegido: _filtro == f,
                onTap: () => setState(() => _filtro = f),
              ),
          ],
        ),
        GrupoDeColumna(
          titulo: 'extension.acciones'.i18n,
          opciones: [
            OpcionDeColumna(
              id: 'activar',
              icono: Icons.done_all_rounded,
              texto: 'extension.activar-todas'.i18n,
              cargando: masivoEnCurso,
              onTap: () => unawaited(
                conElPasoCerrado(() => cambiarTodas(true)),
              ),
            ),
            OpcionDeColumna(
              id: 'desactivar',
              icono: Icons.remove_done_rounded,
              texto: 'extension.desactivar-todas'.i18n,
              cargando: masivoEnCurso,
              onTap: () => unawaited(
                conElPasoCerrado(() => cambiarTodas(false)),
              ),
            ),
            OpcionDeColumna(
              id: 'actualizar',
              icono: Icons.system_update_alt_rounded,
              texto: 'extension.actualizar-todas'.i18n,
              cargando: masivoEnCurso,
              onTap: () => unawaited(conElPasoCerrado(actualizarTodas)),
            ),
            OpcionDeColumna(
              id: 'repositorio',
              icono: Icons.storefront_rounded,
              texto: 'common.repo'.i18n,
              onTap: () => unawaited(Get.to(() => const ExtensionRepoPage())),
            ),
          ],
        ),
      ],
    );
  }

  /// El teclado, en el sitio de la columna.
  ///
  /// Con una tecla para volver a los filtros: sin ella, entrar a escribir
  /// dejaría los filtros y las acciones sin ninguna forma de volver a
  /// alcanzarlos hasta salir de la pantalla.
  Widget _teclado() {
    return SizedBox(
      width: ColumnaDeAcciones.ancho + 130,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: OpcionDeColumna(
                icono: Icons.arrow_back_rounded,
                texto: 'extension.tv-volver-a-filtros'.i18n,
                onTap: () => setState(() => _escribiendo = false),
              ),
            ),
            TecladoTv(
              texto: _busqueda,
              ancho: ColumnaDeAcciones.ancho + 130,
              onCambio: (t) => setState(() => _busqueda = t),
            ),
          ],
        ),
      ),
    );
  }

  // ─── La lista de la derecha ────────────────────────────────────────────

  Widget _lista(List<ExtensionService> visibles, int total) {
    if (visibles.isEmpty) return _vacio(total);
    return ListView.separated(
      controller: _scroll,
      // Lo que se construye de más lo decide PrismHub+: en un televisor
      // modesto, media pantalla de filas con su icono ya descargado es
      // memoria que el sistema puede venir a pedir en cualquier momento.
      scrollCacheExtent: PrismHubMas.cuantoSeConstruyeDeMas,
      padding: const EdgeInsets.only(top: 4, bottom: 24),
      itemCount: visibles.length,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (context, i) => _FilaDeExtension(
        servicio: visibles[i],
        onAlternar: () => unawaited(_alternar(visibles[i])),
        onAjustes: () => _abrirAjustesDe(visibles[i]),
      ),
    );
  }

  /// La lista vacía dice CUÁL de los tres motivos es.
  ///
  /// Los tres se veían igual y mandaban al mismo sitio: «no tenés
  /// extensiones». Reportado en vivo en el buscador, y acá pasaba lo mismo —
  /// con un filtro puesto que no alcanza a ninguna, la pantalla decía que
  /// había que instalar algo que ya estaba instalado.
  Widget _vacio(int total) {
    final (icono, titulo, detalle) = switch (0) {
      _ when total == 0 => (
          Icons.extension_off_outlined,
          'common.no-extension'.i18n,
          'extension.tv-vacio-detalle'.i18n,
        ),
      _ when _busqueda.isNotEmpty => (
          Icons.search_off_rounded,
          'extension.tv-sin-resultados'.i18n,
          FlutterI18n.translate(
            context,
            'extension.tv-sin-resultados-detalle',
            translationParams: {'texto': _busqueda},
          ),
        ),
      _ => (
          Icons.filter_alt_off_outlined,
          'extension.tv-filtro-vacio'.i18n,
          FlutterI18n.translate(
            context,
            'extension.tv-filtro-vacio-detalle',
            translationParams: {'filtro': _filtro.etiqueta},
          ),
        ),
    };
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 56, color: HomeTheme.textMuted),
            const SizedBox(height: 18),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: HomeTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              detalle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                height: 1.5,
                color: HomeTheme.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Una extensión, en una fila del ancho entero.
///
/// Dos cosas enfocables y no una: la fila, que PRENDE Y APAGA —que es a lo
/// que se viene a esta pantalla— y un botón al final para lo demás (sus
/// filtros, su idioma, sus opciones propias). Con una sola habría que elegir
/// cuál de las dos cuesta dos pasos, y prender/apagar es la de todos los días.
///
/// Van una al lado de la otra a propósito: `FocoConTopes` obliga a que un
/// movimiento horizontal se quede en la misma franja, así que DERECHA sobre
/// una fila cae siempre en el botón de ESA fila, nunca en el de la de abajo.
class _FilaDeExtension extends StatelessWidget {
  const _FilaDeExtension({
    required this.servicio,
    required this.onAlternar,
    required this.onAjustes,
  });

  final ExtensionService servicio;
  final VoidCallback onAlternar;
  final VoidCallback onAjustes;

  @override
  Widget build(BuildContext context) {
    final ext = servicio.extension;
    final activa = ExtensionUtils.isEnabled(ext.package);
    final inestable = ExtensionUtils.isRemoteUnstableCached(ext.package);
    return Row(
      children: [
        Expanded(
          child: FocusableCard(
            borderRadius: 12,
            conCrecido: false,
            onTap: onAlternar,
            child: _cuerpo(context, ext, activa, inestable),
          ),
        ),
        const SizedBox(width: 10),
        FocusableCard(
          borderRadius: 12,
          conCrecido: false,
          onTap: onAjustes,
          child: Container(
            width: 62,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: HomeTheme.cardSurface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.tune_rounded,
              size: 24,
              color: HomeTheme.textMuted,
            ),
          ),
        ),
      ],
    );
  }

  Widget _cuerpo(
    BuildContext context,
    Extension ext,
    bool activa,
    bool inestable,
  ) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: HomeTheme.cardSurface,
        borderRadius: BorderRadius.circular(12),
        // Una barra de color a la izquierda y no un fondo teñido: el fondo
        // teñido pelea con el resplandor del foco (que se dibuja debajo del
        // hijo y cuenta con que el hijo sea opaco), y con diecinueve filas
        // encendidas la pantalla entera quedaba de color.
        border: Border(
          left: BorderSide(
            width: 4,
            color: activa
                ? HomeTheme.accentPink
                : HomeTheme.border.withValues(alpha: 0.6),
          ),
        ),
      ),
      child: Row(
        children: [
          _icono(context, ext),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ext.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    // Apagada, el nombre se apaga con ella. Es la señal que
                    // se lee de lejos, antes que cualquier pastilla.
                    color: activa ? HomeTheme.textPrimary : HomeTheme.textMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'v${ext.version} · ${ext.lang.toUpperCase()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: HomeTheme.textMuted),
                ),
              ],
            ),
          ),
          if (inestable) ...[
            Icon(
              Icons.warning_amber_rounded,
              size: 20,
              color: HomeTheme.accentRed,
            ),
            const SizedBox(width: 10),
          ],
          _pastilla(activa),
        ],
      ),
    );
  }

  /// El estado, escrito.
  ///
  /// Un interruptor Material mide 40 px y su diferencia entre puesto y no
  /// puesto es la posición de un círculo: desde tres metros son dos manchas
  /// iguales. Una pastilla con la palabra adentro se lee de una.
  Widget _pastilla(bool activa) {
    final color = activa ? HomeTheme.accentPink : HomeTheme.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        activa ? 'extension.tv-activa'.i18n : 'extension.tv-apagada'.i18n,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: color,
        ),
      ),
    );
  }

  Widget _icono(BuildContext context, Extension ext) {
    const lado = 38.0;
    final url = ext.icon;
    if (url == null || url.isEmpty) {
      return Container(
        width: lado,
        height: lado,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: HomeTheme.bg,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          ext.name.characters.first.toUpperCase(),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: HomeTheme.textMuted,
          ),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: CacheNetWorkImagePic(
        url,
        width: lado,
        height: lado,
        fit: BoxFit.cover,
        // Decodificado al tamaño que se ve: sin esto, diecinueve iconos que
        // llegan en 256×256 se guardan enteros para dibujarse en 38.
        cacheWidth: (lado * MediaQuery.devicePixelRatioOf(context)).ceil(),
      ),
    );
  }
}
