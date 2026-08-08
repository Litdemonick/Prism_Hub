import 'package:easy_refresh/easy_refresh.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:get/get.dart';
import 'package:prismhub/models/extension.dart';
import 'package:prismhub/controllers/extension/extension_repo_controller.dart';
import 'package:prismhub/views/widgets/extension/extension_card.dart';
import 'package:prismhub/views/widgets/home/esqueleto.dart';
import 'package:prismhub/views/widgets/home/animated_background_glow.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/search_text.dart';
import 'package:prismhub/views/widgets/button.dart';
import 'package:prismhub/views/widgets/platform_widget.dart';
import 'package:prismhub/views/widgets/progress.dart';
import 'package:prismhub/views/widgets/search_appbar.dart';
import 'package:prismhub/views/widgets/messenger.dart';

class ExtensionRepoPage extends StatefulWidget {
  const ExtensionRepoPage({super.key});

  @override
  State<ExtensionRepoPage> createState() => _ExtensionRepoPageState();
}

class _ExtensionRepoPageState extends State<ExtensionRepoPage> {
  late ExtensionRepoPageController c;

  // Alias a ExtensionUtils.videoTypes/readingTypes (único lugar con esta
  // regla ahora — antes estaba duplicada acá Y en search_page.dart). Se
  // mantienen estos nombres locales porque el resto del archivo los usa
  // para pattern-matching por identidad de Set más abajo; al ser el MISMO
  // const canonicalizado que expone ExtensionUtils, la identidad se
  // conserva igual.
  static const _videoTypes = ExtensionUtils.videoTypes;
  static const _readingTypes = ExtensionUtils.readingTypes;

  // Uno por dropdown: crearlos de nuevo en cada build (en vez de guardarlos
  // como campos) rompía el flyout a mitad de abrir cuando Obx reconstruía
  // la barra de filtros por un cambio de otro control.
  final _typeFlyoutController = fluent.FlyoutController();
  final _levelFlyoutController = fluent.FlyoutController();
  final _langFlyoutController = fluent.FlyoutController();
  final _nsfwFlyoutController = fluent.FlyoutController();
  final _installedFlyoutController = fluent.FlyoutController();

  // Paginación de "Instaladas"/"Disponibles" — con muchas extensiones el
  // grid/lista se volvía larguísimo de scrollear. Estado local (no en el
  // controller): es puramente de la vista, no necesita sobrevivir a nada.
  int _installedPage = 0;
  int _availablePage = 0;
  int _unstablePage = 0;

  // Sin un controller explícito, el Scrollbar no tiene forma inequívoca de
  // saber a qué Scrollable atarse (mouse-drag del thumb no hacía nada,
  // confirmado en vivo) — pasándoselo a los dos (Scrollbar y
  // SingleChildScrollView, ver desktopBuilder en _content()) queda sin
  // ambigüedad y el arrastre funciona.
  final _desktopScrollController = ScrollController();

  @override
  void initState() {
    // Reusar la instancia si ya existe, en vez de Get.put a secas: Get.put
    // REEMPLAZA la registrada y destruye la anterior. Al reabrir esta pagina
    // rapido —o al saltar entre pestanas en el celular— el refresco que habia
    // quedado en vuelo terminaba escribiendo sobre un controller ya destruido.
    // Mismo criterio que SearchPage y HomePage, que ya lo hacian asi.
    c = Get.isRegistered<ExtensionRepoPageController>()
        ? Get.find<ExtensionRepoPageController>()
        : Get.put(ExtensionRepoPageController());
    // Igual que en la lista de instaladas: si se vino acá desde un aviso que
    // nombraba una extensión, se abre ya buscada en vez de dejar al usuario
    // rastreándola entre decenas.
    final pedido = ExtensionUtils.tomarFiltroPendiente();
    if (pedido != null && pedido.isNotEmpty) c.search.value = pedido;
    super.initState();
  }

  @override
  void dispose() {
    _typeFlyoutController.dispose();
    _levelFlyoutController.dispose();
    _langFlyoutController.dispose();
    _nsfwFlyoutController.dispose();
    _installedFlyoutController.dispose();
    _desktopScrollController.dispose();
    super.dispose();
  }

  // Hoja de filtros del celular.
  //
  // Antes cada control hacia Get.back() al elegir: la hoja se cerraba con el
  // primer filtro y ya no se podian combinar dos, ademas de reconstruir la
  // lista entera en cada toque. Ahora se elige todo sobre una copia local y
  // recien al confirmar se vuelca al controller, o sea UNA sola reconstruccion.
  _filterDialog() {
    // Copia de trabajo: mientras la hoja esta abierta no se toca el estado
    // real, asi que cancelar (o deslizar para cerrar) deja todo como estaba.
    Set<ExtensionType>? tipo = c.searchType.value;
    var nivel = c.searchLevel.value;
    var contenido = c.searchNsfw.value;
    var estado = c.searchInstalled.value;

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Widget grupo<T>({
              required String titulo,
              required List<(T, String)> opciones,
              required T seleccion,
              required void Function(T) alElegir,
            }) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: const TextStyle(
                      color: HomeTheme.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<T>(
                      segments: [
                        for (final (valor, etiqueta) in opciones)
                          ButtonSegment(value: valor, label: Text(etiqueta)),
                      ],
                      selected: <T>{seleccion},
                      onSelectionChanged: (v) =>
                          setSheetState(() => alElegir(v.first)),
                      showSelectedIcon: false,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              );
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  grupo<Set<ExtensionType>?>(
                    titulo: 'extension-repo.filter-type'.i18n,
                    opciones: [
                      (null, 'common.show-all'.i18n),
                      (_videoTypes, 'extension-type.video'.i18n),
                      (_readingTypes, 'extension-type.reading'.i18n),
                    ],
                    seleccion: tipo,
                    alElegir: (v) => tipo = v,
                  ),
                  grupo<String>(
                    titulo: 'extension-repo.filter-level'.i18n,
                    opciones: [
                      for (final v in ['all', 'stable', 'unstable'])
                        (v, 'extension-repo.level-$v'.i18n),
                    ],
                    seleccion: nivel,
                    alElegir: (v) => nivel = v,
                  ),
                  grupo<String>(
                    titulo: 'extension-repo.filter-nsfw'.i18n,
                    opciones: [
                      for (final v in ['all', 'sfw', 'nsfw'])
                        (v, 'extension-repo.nsfw-$v'.i18n),
                    ],
                    seleccion: contenido,
                    alElegir: (v) => contenido = v,
                  ),
                  grupo<String>(
                    titulo: 'extension-repo.filter-installed'.i18n,
                    opciones: [
                      for (final v in ['all', 'installed', 'available', 'new'])
                        (v, 'extension-repo.installed-$v'.i18n),
                    ],
                    seleccion: estado,
                    alElegir: (v) => estado = v,
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => setSheetState(() {
                            tipo = null;
                            nivel = 'all';
                            contenido = 'all';
                            estado = 'all';
                          }),
                          child: Text('common.show-all'.i18n),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            // Todo junto y una sola vez: cambiar cada valor por
                            // separado disparaba una reconstruccion por filtro.
                            c.searchType.value = tipo;
                            c.searchLevel.value = nivel;
                            c.searchNsfw.value = contenido;
                            c.searchInstalled.value = estado;
                            Navigator.of(context).pop();
                          },
                          child: Text('common.confirm'.i18n),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // Solo español e inglés: son los dos idiomas de la app, y el catálogo no
  // publica extensiones en los demás. Ofrecer una lista de ocho idiomas era
  // mandar al usuario a filtros que siempre devuelven vacío.
  static const Map<String, String> _langLabels = {
    'all': 'Todos',
    'es': 'Español',
    'en': 'English',
  };

  // (total, instaladas, disponibles) — sobre el catálogo COMPLETO, sin
  // filtros activos (a diferencia de _content(), que sí filtra). Para el
  // resumen del encabezado ("9 extensiones · 7 instaladas · 2 disponibles").
  (int, int, int) _repoStats() {
    final valid = c.extensionsTemp.where((e) => e['package'] != null).toList();
    final installed = valid
        .where((e) => ExtensionUtils.runtimes.containsKey(e['package']))
        .length;
    return (valid.length, installed, valid.length - installed);
  }

  // Chip tipo "Etiqueta: valor ⌄" que abre un MenuFlyout con las opciones —
  // reemplaza los fluent.ComboBox sueltos (look genérico de sistema, poco
  // integrado) por algo con la misma superficie/borde que el resto de la
  // app (mismo patrón que las tarjetas de abajo).
  Widget _filterChip({
    required fluent.FlyoutController controller,
    required String label,
    required String value,
    required List<fluent.MenuFlyoutItemBase> Function(BuildContext) items,
  }) {
    return fluent.FlyoutTarget(
      controller: controller,
      child: GestureDetector(
        onTap: () => controller.showFlyout(
          builder: (context) => fluent.MenuFlyout(items: items(context)),
        ),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: HomeTheme.cardSurface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: HomeTheme.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$label: ',
                  style:
                      const TextStyle(color: HomeTheme.textMuted, fontSize: 13),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    color: HomeTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(
                  fluent.FluentIcons.chevron_down,
                  size: 10,
                  color: HomeTheme.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Título de sección con una regla horizontal a la derecha — separa
  // "Instaladas"/"Disponibles"/"Inestables" del resto sin ocupar una franja
  // entera de fondo, y en mayúsculas chicas se lee como encabezado de
  // sección en vez de competir con el título grande de arriba. `trailing`
  // (las flechitas de paginación) va pegado al final de la misma línea, en
  // vez de en una fila aparte más abajo.
  Widget _sectionHeader(String text, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 4),
      child: Row(
        children: [
          Text(
            text.toUpperCase(),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: HomeTheme.textMuted,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(height: 1, color: HomeTheme.border),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 12),
            trailing,
          ],
        ],
      ),
    );
  }

  // Flechitas "‹ X/Y ›" compactas — van pegadas a la línea de
  // Instaladas/Disponibles/Inestables (ver _sectionHeader), no en una fila
  // aparte debajo del grid. Iguales en Android (Material) y desktop
  // (fluent), con `useFluent` eligiendo el set de íconos acorde al resto de
  // cada plataforma. No se muestra nada si entra todo en una sola página.
  Widget _pagerArrows({
    required int page,
    required int totalPages,
    required bool useFluent,
    required ValueChanged<int> onChange,
  }) {
    if (totalPages <= 1) return const SizedBox.shrink();
    final label = '${page + 1}/$totalPages';
    final prevEnabled = page > 0;
    final nextEnabled = page < totalPages - 1;
    const textStyle = TextStyle(fontSize: 11, color: HomeTheme.textMuted);
    // En Android el tap target de antes (icono de 14px + 3px de padding,
    // ~20x20 en total) era muy chico para tocar con el dedo — 44x44 es el
    // mínimo recomendado. Desktop se queda compacto (usa mouse, no dedo).
    final tapSize = useFluent ? 20.0 : 44.0;
    final iconSize = useFluent ? 14.0 : 22.0;
    Widget arrow(IconData icon, bool enabled, VoidCallback onTap) {
      return MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          onTap: enabled ? onTap : null,
          child: SizedBox(
            width: tapSize,
            height: tapSize,
            child: Center(
              child: Icon(
                icon,
                size: iconSize,
                color: enabled
                    ? HomeTheme.textMuted
                    : HomeTheme.textMuted.withValues(alpha: 0.3),
              ),
            ),
          ),
        ),
      );
    }

    final leftIcon =
        useFluent ? fluent.FluentIcons.chevron_left : Icons.chevron_left;
    final rightIcon =
        useFluent ? fluent.FluentIcons.chevron_right : Icons.chevron_right;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        arrow(leftIcon, prevEnabled, () => onChange(page - 1)),
        Text(label, style: textStyle),
        arrow(rightIcon, nextEnabled, () => onChange(page + 1)),
      ],
    );
  }

  /// Los paquetes que AHORA MISMO se pueden instalar con lo que hay filtrado.
  ///
  /// ── Por qué se anota desde el dibujo y no se recalcula ──────────────────
  ///
  /// El botón vive en la barra de filtros y la lista filtrada se arma en
  /// `_content()`, que son dos ramas distintas del árbol. Recalcular los
  /// filtros en el botón significaría escribir por segunda vez las mismas seis
  /// reglas, y ese es exactamente el error contra el que avisa el comentario de
  /// `_applyFilters` en la otra pantalla: dos copias que se desincronizan.
  ///
  /// Así hay una sola verdad. Anotar un campo mientras se dibuja no dispara
  /// otro dibujo —no hay `setState`— y el botón lo lee recién cuando lo tocan,
  /// con al menos un cuadro ya pasado.
  List<String> _instalablesVisibles = const [];

  /// Está instalando una tanda ahora mismo.
  bool _instalandoTodas = false;

  /// Instala las que se están viendo y todavía no están.
  ///
  /// ── Qué queda afuera, a propósito ───────────────────────────────────────
  ///
  /// Las ya instaladas —no hay nada que hacer— y las marcadas inestables: el
  /// catálogo dice que están rotas o retiradas, y meterlas en el Home solo
  /// llena la pantalla de filas vacías. Quien quiera una igual la instala desde
  /// su tarjeta, donde el aviso está a la vista.
  ///
  /// Las +18 sí entran, pero apagadas si el interruptor general lo está — igual
  /// que al instalarlas de a una. Ver `instalarDesdeCatalogo`.
  Future<void> _instalarTodas() async {
    if (_instalandoTodas) return;
    final paquetes = List<String>.from(_instalablesVisibles);
    if (paquetes.isEmpty) {
      showPlatformSnackbar(
        context: context,
        title: 'extension.instalar-todas'.i18n,
        content: 'extension.masivo-nada-para-instalar'.i18n,
      );
      return;
    }

    setState(() => _instalandoTodas = true);
    var hechas = 0;
    var fallidas = 0;
    try {
      // De a una: cada instalación baja el guion, verifica la firma y arranca
      // el runtime. Diecisiete en paralelo pelean por el mismo hilo y encima
      // dejarían la pantalla sin responder mientras tanto.
      for (final pkg in paquetes) {
        final entrada = c.extensions.firstWhere(
          (e) => e['package']?.toString() == pkg,
          orElse: () => null,
        );
        if (entrada is! Map) continue;
        if (!mounted) return;
        if (await ExtensionUtils.instalarDesdeCatalogo(entrada, context)) {
          hechas++;
        } else {
          fallidas++;
        }
        // Un cuadro para la pantalla entre una y otra. Arrancar el runtime es
        // trabajo de CPU y bloquea el isolate: encadenándolas sin soltar, la
        // rueda del botón no se movía y el app parecía colgado hasta que
        // terminaba la tanda entera.
        await ExtensionUtils.cederElCuadro();
      }
    } finally {
      if (mounted) setState(() => _instalandoTodas = false);
    }
    if (!mounted) return;
    // ── Rehacer la lista al terminar la tanda ────────────────────────────
    //
    // Explícito y no confiando en el aviso que manda cada instalación: ese
    // aviso se junta con los de la ráfaga y llega un rato después (ver
    // ExtensionUtils._pedirReload), así que las tarjetas de las recién
    // instaladas se quedaban un momento con el botón «Instalar» puesto — que
    // es justo lo que se reportó. Acá se sabe que la tanda terminó, así que se
    // pide una vez y queda al día de una.
    await c.onRefresh(forceRefresh: false);
    if (!mounted) return;
    showPlatformSnackbar(
      context: context,
      title: 'extension.instalar-todas'.i18n,
      content: fallidas == 0
          ? FlutterI18n.translate(
              context,
              'extension.masivo-instaladas',
              translationParams: {'n': '$hechas'},
            )
          : FlutterI18n.translate(
              context,
              'extension.masivo-instaladas-con-fallos',
              translationParams: {'n': '$hechas', 'f': '$fallidas'},
            ),
    );
  }

  Widget _content() {
    // Bloques con forma de fila, no una rueda: el repositorio ya tiene su
    // forma desde el primer cuadro y al llegar el catálogo nada salta de
    // lugar. Mismo criterio que el Inicio y que la Biblioteca.
    if (c.isLoading.value) {
      return const EsqueletoDeLista(alto: 96);
    }
    if (c.isError.value) {
      return Center(
          child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('extension-repo.error'.i18n),
          // El motivo real debajo del titulo generico. Antes solo se veia
          // "no se pudo cargar" y era imposible distinguir sin internet de
          // un repositorio que devuelve algo que no se entiende.
          if (c.errorDetalle.value.isNotEmpty) ...[
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                c.errorDetalle.value,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: HomeTheme.textMuted,
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          fluent.Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              'extension-repo.error-tips'.i18n,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(height: 13),
          PlatformFilledButton(
            child: Text('common.retry'.i18n),
            onPressed: () {
              c.onRefresh();
            },
          )
        ],
      ));
    }

    final extensionCards = c.extensions
        .where((e) =>
            e['package'] != null &&
            e['name'] != null &&
            e['version'] != null &&
            e['lang'] != null)
        .map((e) {
      final type = ExtensionType.values.firstWhere(
        (element) => element.toString() == 'ExtensionType.${e['type']}',
        orElse: () => ExtensionType.bangumi,
      );
      return ExtensionCard(
          key: ValueKey(e['package']),
          name: e['name'] ?? '',
          icon: e['icon'],
          version: e['version'] ?? '',
          package: e['package'] ?? '',
          lang: e['lang'] ?? 'all',
          // El catálogo de prism+ trae la URL del bundle en `script`;
          // repos antiguos usaban `url`. Soportar ambos.
          url: e['script'] ?? e['url'],
          webSite: e['webSite'],
          license: e['license'],
          description: e['description'],
          // Firma Ed25519 de prism+ — la card verifica antes de instalar.
          signature: e['signature'],
          nsfw: e['nsfw'] == 'true' || e['nsfw'] == true,
          // Una extensión que declara `minProtocol` mayor al que entiende este
          // app se trata como no instalable, reusando el mismo bloqueo que ya
          // existe para `unstable` — pero con el motivo correcto: acá lo que
          // falta es actualizar PrismHub, no esperar un arreglo de la
          // extensión. Sin esto se instalaría y fallaría de forma confusa.
          unstable: e['unstable'] == 'true' ||
              e['unstable'] == true ||
              ExtensionUtils.entryNeedsNewerApp(e),
          // El motivo lo publica el catalogo (unstableReason). Antes se
          // ignoraba y salia siempre el generico "en espera de actualizacion",
          // aunque el sitio estuviera simplemente en mantenimiento.
          blockedReasonKey: ExtensionUtils.entryNeedsNewerApp(e)
              ? 'extension.needs-newer-app'
              : ExtensionUtils.claveMotivoInestable(e['unstableReason']),
          unstableReason: e['unstableReason'] as String?,
          type: type);
    }).toList();
    // 过滤 — nombre tolerante a tildes/orden, O categoría/tipo si la
    // búsqueda menciona un sinónimo conocido ("anime", "manga", etc):
    // permite filtrar por tipo escribiendo en el mismo buscador, sin tener
    // que usar el chip "Tipo" aparte.
    if (c.search.value.isNotEmpty) {
      final inferredTypes = SearchText.inferTypeFromQuery(
        c.search.value,
        _videoTypes,
        _readingTypes,
      );
      extensionCards.removeWhere((element) {
        final nameMatches =
            SearchText.matchesQuery(element.name, c.search.value);
        final categoryMatches =
            inferredTypes != null && inferredTypes.contains(element.type);
        return !(nameMatches || categoryMatches);
      });
    }
    if (c.searchType.value != null) {
      extensionCards.removeWhere(
        (element) => !c.searchType.value!.contains(element.type),
      );
    }
    if (c.searchLang.value != 'all') {
      extensionCards.removeWhere(
        (element) => element.lang != c.searchLang.value,
      );
    }
    if (c.searchLevel.value != 'all') {
      final wantUnstable = c.searchLevel.value == 'unstable';
      extensionCards.removeWhere(
        (element) => element.unstable != wantUnstable,
      );
    }
    if (c.searchNsfw.value != 'all') {
      final quiereNsfw = c.searchNsfw.value == 'nsfw';
      extensionCards.removeWhere((element) => element.nsfw != quiereNsfw);
    }
    switch (c.searchInstalled.value) {
      case 'installed':
        extensionCards.removeWhere(
          (e) => !ExtensionUtils.runtimes.containsKey(e.package),
        );
      case 'available':
        extensionCards.removeWhere(
          (e) => ExtensionUtils.runtimes.containsKey(e.package),
        );
      case 'new':
        // "Nueva" = no estaba en el catálogo la última vez que se abrió esta
        // pantalla. El índice no trae fecha de publicación, así que no se puede
        // deducir de los datos — ver ExtensionRepoPageController.esNueva.
        extensionCards.removeWhere((e) => !c.esNueva(e.package));
    }

    if (extensionCards.isEmpty) {
      return Center(child: Text('extension-repo.empty'.i18n));
    }

    // Instaladas primero, agrupadas aparte — antes quedaban mezcladas en
    // cualquier orden con las que ni siquiera están instaladas, obligando a
    // buscar entre todas para ver qué ya tenés.
    final installedCards = extensionCards
        .where((e) => ExtensionUtils.runtimes.containsKey(e.package))
        .toList();
    final availableCards = extensionCards
        .where((e) => !ExtensionUtils.runtimes.containsKey(e.package))
        .toList();
    // Las no instaladas se dividen a su vez en Disponibles/Inestables — antes
    // una extensión marcada `unstable` (bloqueada para instalar, ver
    // ExtensionCard._install) se mezclaba entre las disponibles normales;
    // separarla en su propia zona la hace fácil de encontrar/ignorar de un
    // vistazo, sin tener que leer badge por badge.
    final stableAvailableCards =
        availableCards.where((e) => !e.unstable).toList();
    final unstableAvailableCards =
        availableCards.where((e) => e.unstable).toList();
    // La misma lista que ve el usuario, para el botón «Instalar todas».
    _instalablesVisibles =
        stableAvailableCards.map((e) => e.package).toList(growable: false);
    final nonEmptyGroups = [
      installedCards,
      stableAvailableCards,
      unstableAvailableCards,
    ].where((g) => g.isNotEmpty).length;
    final showSections = nonEmptyGroups > 1;

    // Paginado: cada sección (Instaladas/Disponibles/Inestables) pagina por
    // separado, para no perder el orden ni mezclar una con otra. El clamp
    // cubre el caso de quedar en una página que un filtro/búsqueda dejó
    // vacía — en vez de mostrar una página en blanco, cae sola a la última
    // válida.
    List<T> paginate<T>(List<T> items, int page, int pageSize) {
      final totalPages = items.isEmpty ? 0 : (items.length / pageSize).ceil();
      final safePage = totalPages == 0 ? 0 : page.clamp(0, totalPages - 1);
      return items.skip(safePage * pageSize).take(pageSize).toList();
    }

    int totalPagesOf(int length, int pageSize) =>
        length == 0 ? 0 : (length / pageSize).ceil();
    int safePageOf(int page, int totalPages) =>
        totalPages == 0 ? 0 : page.clamp(0, totalPages - 1);

    // Encabezado (con las flechitas de paginación pegadas a esa misma
    // línea, ver _sectionHeader) + contenido paginado + gap final — el
    // mismo armado sirve para Android (lista) y desktop (grid), solo cambia
    // cómo se renderizan las cards (`render`) y qué set de íconos usar
    // (`useFluent`). Si hay más de una página pero la sección es la única
    // con contenido (showSections false), el encabezado igual se muestra —
    // si no, las flechitas no tendrían dónde ir. Devuelve [] si la sección
    // no tiene nada, así no deja huecos vacíos en el Column/ListView que la
    // contiene.
    List<Widget> paginatedSection({
      required String headerKey,
      required List<Widget> cards,
      required int page,
      required int pageSize,
      required bool useFluent,
      required double trailingGap,
      required ValueChanged<int> onChange,
      required Widget Function(List<Widget>) render,
    }) {
      if (cards.isEmpty) return const [];
      final totalPages = totalPagesOf(cards.length, pageSize);
      final safePage = safePageOf(page, totalPages);
      final pager = _pagerArrows(
        page: safePage,
        totalPages: totalPages,
        useFluent: useFluent,
        onChange: onChange,
      );
      return [
        if (showSections || totalPages > 1)
          _sectionHeader(
            headerKey.i18n,
            trailing: totalPages > 1 ? pager : null,
          ),
        render(paginate(cards, safePage, pageSize)),
        SizedBox(height: trailingGap),
      ];
    }

    return PlatformBuildWidget(
      androidBuilder: (context) {
        const pageSize = 4;
        Widget listRender(List<Widget> cards) =>
            Column(mainAxisSize: MainAxisSize.min, children: cards);
        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          children: [
            ...paginatedSection(
              headerKey: 'extension-repo.installed',
              cards: installedCards,
              page: _installedPage,
              pageSize: pageSize,
              useFluent: false,
              trailingGap: 8,
              onChange: (p) => setState(() => _installedPage = p),
              render: listRender,
            ),
            ...paginatedSection(
              headerKey: 'extension-repo.available',
              cards: stableAvailableCards,
              page: _availablePage,
              pageSize: pageSize,
              useFluent: false,
              trailingGap: 8,
              onChange: (p) => setState(() => _availablePage = p),
              render: listRender,
            ),
            ...paginatedSection(
              headerKey: 'extension-repo.level-unstable',
              cards: unstableAvailableCards,
              page: _unstablePage,
              pageSize: pageSize,
              useFluent: false,
              trailingGap: 16,
              onChange: (p) => setState(() => _unstablePage = p),
              render: listRender,
            ),
          ],
        );
      },
      // Wrap centrado dentro de su propio ConstrainedBox(1100) — el
      // Scrollbar de más afuera (ver abajo) ocupa TODO el ancho de la
      // ventana, así que el centrado del grid tiene que resolverse acá
      // adentro, no delegarlo al ancho ya limitado del scrollable.
      desktopBuilder: (context) {
        Widget grid(List<Widget> cards) => Wrap(
              alignment: WrapAlignment.center,
              spacing: 16,
              runSpacing: 16,
              children: [
                for (final card in cards) SizedBox(width: 240, child: card),
              ],
            );
        const pageSize = 4;
        // Scrollbar de sistema (comportamiento default, sin theming propio
        // — uno customizado quedaba difícil de agarrar con el mouse) pero
        // envolviendo TODO el ancho disponible (ver _buildDesktop, este
        // Expanded ya no está adentro del ConstrainedBox de 1100) para que
        // quede pegado al borde derecho real de la ventana en vez de al
        // borde del bloque centrado de cards.
        return Scrollbar(
          controller: _desktopScrollController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _desktopScrollController,
            // Mismo padding izq/der que el encabezado (ver _buildDesktop)
            // para que el bloque centrado de 1100px quede exactamente
            // alineado con el título/filtros de arriba.
            padding: const EdgeInsets.only(left: 16, right: 20, bottom: 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      ...paginatedSection(
                        headerKey: 'extension-repo.installed',
                        cards: installedCards,
                        page: _installedPage,
                        pageSize: pageSize,
                        useFluent: true,
                        trailingGap: 24,
                        onChange: (p) => setState(() => _installedPage = p),
                        render: grid,
                      ),
                      ...paginatedSection(
                        headerKey: 'extension-repo.available',
                        cards: stableAvailableCards,
                        page: _availablePage,
                        pageSize: pageSize,
                        useFluent: true,
                        trailingGap: 24,
                        onChange: (p) => setState(() => _availablePage = p),
                        render: grid,
                      ),
                      ...paginatedSection(
                        headerKey: 'extension-repo.level-unstable',
                        cards: unstableAvailableCards,
                        page: _unstablePage,
                        pageSize: pageSize,
                        useFluent: true,
                        trailingGap: 24,
                        onChange: (p) => setState(() => _unstablePage = p),
                        render: grid,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAndroid(BuildContext context) {
    return Obx(
      () => Scaffold(
        backgroundColor: HomeTheme.bg,
        // Buscador en la AppBar (arriba): el teclado se superpone en vez de
        // encoger el body, si no en horizontal la lista se queda sin alto y
        // desborda.
        resizeToAvoidBottomInset: false,
        appBar: SearchAppBar(
          title: 'common.extension-repo'.i18n,
          textEditingController: TextEditingController(text: c.search.value),
          onSubmitted: (value) {
            c.search.value = value;
          },
          actions: [
            // Instalar todo lo que dejaron los filtros. Al lado del embudo
            // porque actua sobre lo que ese embudo eligio; en el celular no hay
            // barra de filtros donde ponerlo, asi que va en la cabecera.
            IconButton(
              tooltip: 'extension.instalar-todas'.i18n,
              icon: Icon(_instalandoTodas
                  ? Icons.hourglass_top_rounded
                  : Icons.download_for_offline_outlined),
              onPressed: _instalandoTodas ? null : _instalarTodas,
            ),
            IconButton(
              icon: const Icon(Icons.filter_list),
              onPressed: () {
                _filterDialog();
              },
            ),
          ],
        ),
        body: Stack(
          children: [
            const Positioned.fill(child: AnimatedBackgroundGlow()),
            EasyRefresh(
              onRefresh: c.onRefresh,
              header: const ClassicHeader(
                showText: false,
                showMessage: false,
              ),
              child: Obx(_content),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktop(BuildContext context) {
    return Container(
      color: HomeTheme.bg,
      child: Stack(
        children: [
          const Positioned.fill(child: AnimatedBackgroundGlow()),
          Column(
            children: [
              // Encabezado + filtros: centrados con ancho máximo, fijos
              // arriba (no scrollean con el grid). A propósito quedan
              // AFUERA del Expanded de abajo — así su Scrollbar puede
              // ocupar todo el ancho de la ventana y quedar pegado a su
              // borde derecho real, en vez de al borde de este bloque de
              // 1100px (ver desktopBuilder en _content()).
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, top: 16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Título + resumen del catálogo, todo centrado como
                        // un solo bloque (antes título a la izquierda y una
                        // pill aparte a la derecha, sin relación visual
                        // clara entre las dos).
                        Text(
                          'common.extension-repo'.i18n,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: HomeTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Obx(() {
                          // Ancla reactiva: extensionsTemp/runtimes (lo que
                          // lee _repoStats) NO son observables — sin tocar
                          // algo Rx acá, GetX no tiene nada que rastrear y
                          // tira "improper use of a GetX" (pantalla gris al
                          // entrar). isLoading SÍ es Rx y cambia justo
                          // después de cada refresh, así que de paso hace
                          // que esto se recalcule cuando corresponde.
                          // ignore: unused_local_variable
                          final _ = c.isLoading.value;
                          final (total, installed, available) = _repoStats();
                          return Text(
                            FlutterI18n.translate(
                              context,
                              'extension-repo.stats',
                              translationParams: {
                                'total': '$total',
                                'installed': '$installed',
                                'available': '$available',
                              },
                            ),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 13,
                              color: HomeTheme.textMuted,
                            ),
                          );
                        }),
                        const SizedBox(height: 20),
                        // Barra de filtros: cada control es su propia pill
                        // separada (antes todos compartían una sola caja —
                        // acá se leen como piezas distintas, más fácil de
                        // escanear). Wrap para que reflowe en vez de
                        // desbordar en ventana angosta. Centrada para
                        // acompañar el resto del centrado de la página.
                        Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            Obx(() => _filterChip(
                                  controller: _typeFlyoutController,
                                  label: 'extension-repo.filter-type'.i18n,
                                  value: switch (c.searchType.value) {
                                    null => 'common.show-all'.i18n,
                                    _videoTypes => 'extension-type.video'.i18n,
                                    _readingTypes =>
                                      'extension-type.reading'.i18n,
                                    _ => 'common.show-all'.i18n,
                                  },
                                  items: (context) => [
                                    fluent.MenuFlyoutItem(
                                      text: Text('common.show-all'.i18n),
                                      onPressed: () {
                                        fluent.Flyout.of(context).close();
                                        c.searchType.value = null;
                                      },
                                    ),
                                    fluent.MenuFlyoutItem(
                                      text: Text('extension-type.video'.i18n),
                                      onPressed: () {
                                        fluent.Flyout.of(context).close();
                                        c.searchType.value = _videoTypes;
                                      },
                                    ),
                                    fluent.MenuFlyoutItem(
                                      text: Text('extension-type.reading'.i18n),
                                      onPressed: () {
                                        fluent.Flyout.of(context).close();
                                        c.searchType.value = _readingTypes;
                                      },
                                    ),
                                  ],
                                )),
                            Obx(() => _filterChip(
                                  controller: _levelFlyoutController,
                                  label: 'extension-repo.filter-level'.i18n,
                                  value: switch (c.searchLevel.value) {
                                    'stable' =>
                                      'extension-repo.level-stable'.i18n,
                                    'unstable' =>
                                      'extension-repo.level-unstable'.i18n,
                                    _ => 'extension-repo.level-all'.i18n,
                                  },
                                  items: (context) => [
                                    for (final level in [
                                      'all',
                                      'stable',
                                      'unstable',
                                    ])
                                      fluent.MenuFlyoutItem(
                                        text: Text(
                                          'extension-repo.level-$level'.i18n,
                                        ),
                                        onPressed: () {
                                          fluent.Flyout.of(context).close();
                                          c.searchLevel.value = level;
                                        },
                                      ),
                                  ],
                                )),
                            Obx(() => _filterChip(
                                  controller: _nsfwFlyoutController,
                                  label: 'extension-repo.filter-nsfw'.i18n,
                                  value:
                                      'extension-repo.nsfw-${c.searchNsfw.value}'
                                          .i18n,
                                  items: (context) => [
                                    for (final v in ['all', 'sfw', 'nsfw'])
                                      fluent.MenuFlyoutItem(
                                        text: Text(
                                          'extension-repo.nsfw-$v'.i18n,
                                        ),
                                        onPressed: () {
                                          fluent.Flyout.of(context).close();
                                          c.searchNsfw.value = v;
                                        },
                                      ),
                                  ],
                                )),
                            Obx(() => _filterChip(
                                  controller: _installedFlyoutController,
                                  label: 'extension-repo.filter-installed'.i18n,
                                  value:
                                      'extension-repo.installed-${c.searchInstalled.value}'
                                          .i18n,
                                  items: (context) => [
                                    for (final v in [
                                      'all',
                                      'installed',
                                      'available',
                                      'new',
                                    ])
                                      fluent.MenuFlyoutItem(
                                        text: Text(
                                          'extension-repo.installed-$v'.i18n,
                                        ),
                                        onPressed: () {
                                          fluent.Flyout.of(context).close();
                                          c.searchInstalled.value = v;
                                        },
                                      ),
                                  ],
                                )),
                            Obx(() => _filterChip(
                                  controller: _langFlyoutController,
                                  label: 'extension-repo.filter-lang'.i18n,
                                  value: _langLabels[c.searchLang.value] ??
                                      c.searchLang.value,
                                  items: (context) => [
                                    for (final entry in _langLabels.entries)
                                      fluent.MenuFlyoutItem(
                                        text: Text(entry.value),
                                        onPressed: () {
                                          fluent.Flyout.of(context).close();
                                          c.searchLang.value = entry.key;
                                        },
                                      ),
                                  ],
                                )),
                            // Instalar todo lo que está a la vista. Al final
                            // de la barra: es una acción, no un filtro, y
                            // pegada a los filtros deja claro que actúa sobre
                            // lo que ellos dejaron.
                            fluent.Button(
                              onPressed:
                                  _instalandoTodas ? null : _instalarTodas,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _instalandoTodas
                                        ? Icons.hourglass_top_rounded
                                        : Icons.download_for_offline_outlined,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 7),
                                  Text('extension.instalar-todas'.i18n),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: 260,
                              child: Obx(
                                () => fluent.TextBox(
                                  controller: TextEditingController(
                                      text: c.search.value),
                                  placeholder:
                                      'extension-repo.search-hint'.i18n,
                                  prefix: const Padding(
                                    padding: EdgeInsets.only(left: 8),
                                    child: Icon(fluent.FluentIcons.search,
                                        size: 14),
                                  ),
                                  // Solo visible con texto — antes no había
                                  // forma de limpiar la búsqueda en desktop
                                  // sin borrar a mano letra por letra.
                                  suffix: c.search.value.isEmpty
                                      ? null
                                      : fluent.IconButton(
                                          icon: const Icon(
                                              fluent.FluentIcons.chrome_close,
                                              size: 9.0),
                                          onPressed: () {
                                            c.onRefresh();
                                            c.search.value = '';
                                          },
                                        ),
                                  onChanged: (value) {
                                    if (value.isEmpty) {
                                      c.onRefresh();
                                      c.search.value = '';
                                    }
                                  },
                                  onSubmitted: (value) {
                                    c.search.value = value;
                                  },
                                ),
                              ),
                            ),
                            fluent.IconButton(
                              icon: const Icon(fluent.FluentIcons.refresh),
                              onPressed: () {
                                c.onRefresh();
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: Obx(_content),
              ),
            ],
          ),
        ],
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
