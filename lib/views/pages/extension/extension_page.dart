import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:get/get.dart';
import 'package:prismhub/models/extension.dart';
import 'package:prismhub/controllers/extension/extension_controller.dart';
import 'package:prismhub/views/widgets/extension/extension_tile.dart';
import 'package:prismhub/views/pages/extension/extension_repo_page.dart';
import 'package:prismhub/views/widgets/home/animated_background_glow.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/utils/search_text.dart';
import 'package:prismhub/router/router.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/router.dart';
import 'package:prismhub/views/widgets/button.dart';
import 'package:prismhub/views/widgets/messenger.dart';
import 'package:prismhub/views/widgets/platform_widget.dart';
import 'package:prismhub/views/widgets/search_appbar.dart';

class ExtensionPage extends StatefulWidget {
  const ExtensionPage({super.key});

  @override
  State<ExtensionPage> createState() => _ExtensionPageState();
}

class _ExtensionPageState extends State<ExtensionPage> {
  late ExtensionPageController c;

  // Paginación — con muchas extensiones instaladas la lista se volvía
  // larguísima de scrollear (mismo criterio que el repositorio, ver
  // extension_repo_page.dart). Estado local: es puramente de la vista.
  // Desktop ahora es un grid de cards (más chicas por página que la lista
  // de Android) — cada plataforma con su propio tamaño de página.
  static const _pageSize = 5;
  int _page = 0;

  // Búsqueda por nombre — Android y desktop comparten el mismo estado (solo
  // uno de los dos builders está montado a la vez). Estado local, no en el
  // controller.
  String _search = '';
  // Filtro por categoría. Compartido entre Android y escritorio igual que
  // _search: solo uno de los dos builders está montado a la vez.
  _ExtFilter _filter = _ExtFilter.todas;
  // Controller propio (no uno nuevo por build) — en Android lo usa
  // SearchAppBar (mismo patrón que el repositorio: el buscador se abre
  // adentro de la propia AppBar, no en un diálogo aparte).
  final _androidSearchController = TextEditingController();

  // Explícito (en vez de dejar que Scrollbar/SingleChildScrollView se
  // adivinen entre sí) — sin esto el scrollbar no se puede arrastrar con el
  // mouse, mismo bug ya visto y arreglado en el repositorio de extensiones.
  final _scrollController = ScrollController();

  // Filtra por nombre Y por categoría. Antes cada builder repetía el filtro
  // de búsqueda por su cuenta; con dos criterios repetirlo era pedir que se
  // desincronizaran, así que vive en un solo lugar.
  List<T> _applyFilters<T extends dynamic>(List<T> all) {
    return all.where((e) {
      final ext = e.extension;
      if (_search.isNotEmpty && !SearchText.matchesQuery(ext.name, _search)) {
        return false;
      }
      switch (_filter) {
        case _ExtFilter.todas:
          return true;
        case _ExtFilter.normales:
          return !ext.nsfw;
        case _ExtFilter.nsfw:
          return ext.nsfw;
        case _ExtFilter.video:
          return ext.type == ExtensionType.bangumi;
        case _ExtFilter.lectura:
          // Manga, novela y todo lo que se lee. `mixed` entra en las dos
          // porque una extensión así sirve para ambas cosas.
          return ExtensionUtils.readingTypes.contains(ext.type);
        case _ExtFilter.desactivadas:
          return !ExtensionUtils.isEnabled(ext.package);
        case _ExtFilter.inestables:
          // Marcadas inestables por el catálogo: o la página está caída, o la
          // extensión responde pero no entrega contenido, o quedó retirada
          // (ver el chequeo de salud de prism-plus). Tenerlas juntas ayuda a
          // ver de un vistazo qué dejó de andar sin recorrer toda la lista.
          return ExtensionUtils.isRemoteUnstableCached(ext.package);
      }
    }).toList();
  }

  /// Prende o apaga TODAS las que se están viendo ahora.
  ///
  /// Sobre la lista FILTRADA y no sobre todas las instaladas, a propósito: si
  /// el usuario está viendo «Lectura» y toca desactivar, espera que se apaguen
  /// las de lectura — no las diecisiete. El botón hace lo que la pantalla
  /// muestra.
  Future<void> _cambiarTodas(bool activar) async {
    final visibles = _applyFilters(c.runtimes.values.toList(growable: false));
    if (visibles.isEmpty) return;

    // Las +18 no se prenden en masa si el interruptor general está apagado.
    // Activarlas igual dejaría contenido adulto disponible sin que nadie lo
    // haya pedido, que es justo lo que ese interruptor existe para evitar.
    var salteadas = 0;
    for (final r in visibles) {
      final ext = r.extension;
      if (activar && !ExtensionUtils.isNsfwVisibleOutsideZone(ext.nsfw)) {
        salteadas++;
        continue;
      }
      await ExtensionUtils.setExtensionEnabled(ext.package, activar);
    }
    if (!mounted) return;
    final hechas = visibles.length - salteadas;
    showPlatformSnackbar(
      context: context,
      content: salteadas == 0
          ? '$hechas'
          : '$hechas · ${'extension.masivo-salteadas'.i18n}',
      title: activar
          ? 'extension.activar-todas'.i18n
          : 'extension.desactivar-todas'.i18n,
    );
  }

  /// Los dos botones de acción masiva, encima de los filtros.
  Widget _buildAccionesMasivas() {
    return Row(
      children: [
        _BotonMasivo(
          icono: Icons.toggle_on_outlined,
          label: 'extension.activar-todas'.i18n,
          onTap: () => _cambiarTodas(true),
        ),
        const SizedBox(width: 8),
        _BotonMasivo(
          icono: Icons.toggle_off_outlined,
          label: 'extension.desactivar-todas'.i18n,
          onTap: () => _cambiarTodas(false),
        ),
      ],
    );
  }

  Widget _buildFilterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final f in _ExtFilter.values) ...[
            if (f != _ExtFilter.todas) const SizedBox(width: 8),
            _ExtFilterChip(
              label: f.label,
              selected: _filter == f,
              onTap: () => setState(() {
                _filter = f;
                // La página vuelve a 0: con menos resultados, quedarse en la
                // página 3 mostraba una lista vacía sin explicación.
                _page = 0;
              }),
            ),
          ],
        ],
      ),
    );
  }

  @override
  void initState() {
    // Reusar la instancia si ya existe, en vez de Get.put a secas: Get.put
    // REEMPLAZA la registrada y destruye la anterior. Al reabrir esta pagina
    // rapido —o al saltar entre pestanas en el celular— el refresco que habia
    // quedado en vuelo terminaba escribiendo sobre un controller ya destruido.
    // Mismo criterio que SearchPage y HomePage, que ya lo hacian asi.
    c = Get.isRegistered<ExtensionPageController>()
        ? Get.find<ExtensionPageController>()
        : Get.put(ExtensionPageController());
    c.isPageOpen = true;
    if (c.needRefresh) {
      c.onRefresh();
    }
    // Si alguien mandó a buscar una extensión concreta, se abre ya filtrada.
    //
    // Pasa cuando desde otra pantalla se avisa que falta activarla: llevar acá
    // y soltar al usuario en una lista de decenas para que la encuentre a mano
    // es dejarle el trabajo a medias. Se consume una sola vez, así que entrar
    // por cuenta propia después no viene con un filtro que nadie pidió.
    final pedido = ExtensionUtils.tomarFiltroPendiente();
    if (pedido != null && pedido.isNotEmpty) {
      _search = pedido;
      // Y el campo de búsqueda del teléfono, que tiene su propio controlador:
      // sin esto la lista salía filtrada pero el buscador vacío, y no se
      // entendía por qué faltaban las demás ni cómo volver a verlas.
      _androidSearchController.text = pedido;
    }
    super.initState();
  }

  @override
  void dispose() {
    c.isPageOpen = false;
    _androidSearchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // 加载错误对话框
  _loadErrorDialog() {
    showPlatformDialog(
      context: context,
      title: 'extension.error-dialog'.i18n,
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 输出key 和 value
            for (final e in c.errors.entries)
              PlatformWidget(
                androidWidget: Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      "${e.key}: ${e.value}",
                    ),
                  ),
                ),
                desktopWidget: fluent.Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    "${e.key}: ${e.value}",
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        PlatformButton(
          onPressed: () {
            RouterUtils.pop();
          },
          child: Text('common.confirm'.i18n),
        ),
      ],
    );
  }

  // Flechitas "‹ X/Y ›" compactas — mismo widget que el repositorio de
  // extensiones (ver extension_repo_page.dart), repetido acá porque no
  // comparten State. No se muestra nada si entra todo en una sola página.
  Widget _pager({
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

  Widget _buildAndroid(BuildContext context) {
    return Obx(() {
      final installedAll = c.runtimes.values.toList(growable: false);
      final installed = _applyFilters(installedAll);
      final totalPages =
          installed.isEmpty ? 0 : (installed.length / _pageSize).ceil();
      final page = totalPages == 0 ? 0 : _page.clamp(0, totalPages - 1);
      final pageItems =
          installed.skip(page * _pageSize).take(_pageSize).toList();
      return Scaffold(
        backgroundColor: HomeTheme.bg,
        appBar: SearchAppBar(
          title: 'common.extension-installed'.i18n,
          hintText: 'common.search'.i18n,
          textEditingController: _androidSearchController,
          onChanged: (value) {
            if (value.isEmpty) {
              setState(() {
                _search = '';
                _page = 0;
              });
            }
          },
          onSubmitted: (value) {
            setState(() {
              _search = value;
              _page = 0;
            });
          },
          actions: [
            if (c.errors.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.error),
                onPressed: () => _loadErrorDialog(),
              ),
            IconButton(
              onPressed: () {
                Get.to(
                  () => const ExtensionRepoPage(),
                );
              },
              icon: const Icon(Icons.download),
            )
          ],
        ),
        body: Stack(
          children: [
            const Positioned.fill(child: AnimatedBackgroundGlow()),
            Column(
              children: [
                const SizedBox(height: 8),
                // Paginación arriba de la lista (no abajo) — mismo criterio
                // que el repositorio de extensiones.
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildAccionesMasivas(),
                      const SizedBox(height: 10),
                      _buildAccionesMasivas(),
              const SizedBox(height: 10),
              _buildFilterChips(),
                    ],
                  ),
                ),
                if (totalPages > 1)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _pager(
                      page: page,
                      totalPages: totalPages,
                      useFluent: false,
                      onChange: (p) => setState(() => _page = p),
                    ),
                  ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () async {
                      // desdeElBoton: lo pidio el usuario, asi que se vuelve a
                      // pedir el catalogo de verdad. Limpiar la cache no
                      // alcanzaba: onRefresh solo releia los mapas locales, y
                      // el fetch recien salia cuando alguna tarjeta lo pedia
                      // por su cuenta — para entonces la pantalla ya se habia
                      // dibujado con los datos viejos.
                      await c.onRefresh(desdeElBoton: true);
                    },
                    color: HomeTheme.accentPink,
                    backgroundColor: HomeTheme.cardSurface,
                    child: installed.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(
                                height: 300,
                                child: Center(
                                  child: Text(installedAll.isEmpty
                                      ? 'common.no-extension'.i18n
                                      : 'common.no-result'.i18n),
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            // Espacio a los costados y entre cards — antes
                            // iban pegadas al borde de la pantalla.
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                            ),
                            itemCount: pageItems.length,
                            itemBuilder: (_, i) {
                              return ExtensionTile(pageItems[i].extension);
                            },
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    });
  }

  Widget _buildDesktop(BuildContext context) {
    return Container(
      color: HomeTheme.bg,
      child: Stack(
        children: [
          const Positioned.fill(child: AnimatedBackgroundGlow()),
          Column(
            children: [
              // Encabezado (título + cuántas tiene instaladas + buscador)
              // fijo arriba, centrado con ancho máximo — igual que el
              // repositorio de extensiones (ver extension_repo_page.dart).
              // El grid de cards de abajo queda AFUERA de este
              // ConstrainedBox a propósito, para que su Scrollbar pueda
              // ocupar todo el ancho de la ventana.
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, top: 16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          'common.extension-installed'.i18n,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: HomeTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        // Cuántas tiene instaladas — sobre el total real
                        // (sin filtrar por búsqueda), como pill destacada en
                        // vez de un texto suelto.
                        Obx(() {
                          final total = c.runtimes.length;
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: HomeTheme.accentPink.withValues(
                                alpha: 0.16,
                              ),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: HomeTheme.accentPink.withValues(
                                  alpha: 0.35,
                                ),
                              ),
                            ),
                            child: Text(
                              FlutterI18n.translate(
                                context,
                                'extension-repo.stats-badge',
                                translationParams: {'installed': '$total'},
                              ),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: HomeTheme.accentPink,
                              ),
                            ),
                          );
                        }),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 260,
                              child: fluent.TextBox(
                                controller:
                                    TextEditingController(text: _search),
                                placeholder: 'common.search'.i18n,
                                prefix: const Padding(
                                  padding: EdgeInsets.only(left: 8),
                                  child:
                                      Icon(fluent.FluentIcons.search, size: 14),
                                ),
                                // Solo visible con texto — antes no había
                                // forma de limpiar la búsqueda en desktop
                                // sin borrar a mano letra por letra.
                                suffix: _search.isEmpty
                                    ? null
                                    : fluent.IconButton(
                                        icon: const Icon(
                                            fluent.FluentIcons.chrome_close,
                                            size: 9.0),
                                        onPressed: () => setState(() {
                                          _search = '';
                                          _page = 0;
                                        }),
                                      ),
                                onChanged: (value) {
                                  if (value.isEmpty) {
                                    setState(() {
                                      _search = '';
                                      _page = 0;
                                    });
                                  }
                                },
                                onSubmitted: (value) {
                                  setState(() {
                                    _search = value;
                                    _page = 0;
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            // Refrescar: no había forma de recargar en
                            // desktop sin gesto de arrastrar (eso solo existe
                            // en Android) — vuelve a leer las extensiones
                            // instaladas Y limpia la caché de versiones
                            // remotas, igual que el gesto de Android.
                            Obx(() => fluent.IconButton(
                                  icon: c.isRefreshing.value
                                      // Que se vea que hizo algo: antes el
                                      // boton no daba ninguna senal y parecia
                                      // que no respondia.
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: fluent.ProgressRing(
                                              strokeWidth: 2),
                                        )
                                      : const Icon(fluent.FluentIcons.refresh),
                                  onPressed: c.isRefreshing.value
                                      ? null
                                      : () => c.onRefresh(desdeElBoton: true),
                                )),
                            const SizedBox(width: 4),
                            if (c.errors.isNotEmpty)
                              fluent.IconButton(
                                icon: const Icon(fluent.FluentIcons.error),
                                onPressed: () {
                                  _loadErrorDialog();
                                },
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _buildFilterChips(),
              const SizedBox(height: 16),
              Expanded(
                child: Obx(() {
                  final installedAll =
                      c.runtimes.values.toList(growable: false);
                  if (installedAll.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('common.no-extension'.i18n),
                          const SizedBox(height: 8),
                          fluent.FilledButton(
                            child: Text('common.extension-repo'.i18n),
                            onPressed: () {
                              router.push('/extension_repo');
                            },
                          ),
                        ],
                      ),
                    );
                  }
                  final filtered = _applyFilters(installedAll);
                  final totalPages = filtered.isEmpty
                      ? 0
                      : (filtered.length / _pageSize).ceil();
                  final page =
                      totalPages == 0 ? 0 : _page.clamp(0, totalPages - 1);
                  final pageItems =
                      filtered.skip(page * _pageSize).take(_pageSize).toList();
                  // Scrollbar de sistema pegado al borde derecho real de la
                  // ventana (mismo criterio que el repositorio, ver
                  // extension_repo_page.dart) — el grid centrado adentro
                  // resuelve su propio ancho máximo.
                  return Scrollbar(
                    controller: _scrollController,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      padding: const EdgeInsets.only(right: 20, bottom: 24),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1100),
                          child: Padding(
                            padding: const EdgeInsets.only(left: 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                if (filtered.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 40),
                                    child: Text('common.no-result'.i18n),
                                  )
                                else
                                  Wrap(
                                    alignment: WrapAlignment.center,
                                    spacing: 16,
                                    runSpacing: 16,
                                    children: [
                                      for (final ext in pageItems)
                                        SizedBox(
                                          width: 260,
                                          child: ExtensionTile(ext.extension),
                                        ),
                                    ],
                                  ),
                                // Más aire antes de las flechitas — antes
                                // quedaban pegadas justo debajo de la última
                                // fila de cards.
                                const SizedBox(height: 28),
                                _pager(
                                  page: page,
                                  totalPages: totalPages,
                                  useFluent: true,
                                  onChange: (p) => setState(() => _page = p),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
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

// Categorías de filtro de Extensiones instaladas. El orden es el de la fila
// de chips.
enum _ExtFilter {
  todas,
  normales,
  nsfw,
  video,
  lectura,
  desactivadas,
  inestables,
}

extension _ExtFilterLabel on _ExtFilter {
  String get label {
    switch (this) {
      case _ExtFilter.todas:
        return 'extension.filter-all'.i18n;
      case _ExtFilter.normales:
        return 'extension.filter-normal'.i18n;
      case _ExtFilter.nsfw:
        return 'extension.filter-nsfw'.i18n;
      case _ExtFilter.video:
        return 'extension.filter-video'.i18n;
      case _ExtFilter.lectura:
        return 'extension.filter-reading'.i18n;
      case _ExtFilter.desactivadas:
        return 'extension.filter-disabled'.i18n;
      case _ExtFilter.inestables:
        return 'extension.filter-unstable'.i18n;
    }
  }
}

/// Botón de acción masiva (activar o desactivar todas las visibles).
///
/// Se distingue a propósito de los chips de filtro que tiene al lado: los
/// chips SELECCIONAN y estos HACEN algo. Por eso llevan icono y borde propio,
/// en vez de parecer un filtro más que se puede marcar.
class _BotonMasivo extends StatelessWidget {
  const _BotonMasivo({
    required this.icono,
    required this.label,
    required this.onTap,
  });

  final IconData icono;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: HomeTheme.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icono, size: 17, color: HomeTheme.textMuted),
              const SizedBox(width: 7),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: HomeTheme.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExtFilterChip extends StatelessWidget {
  const _ExtFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: selected
                ? HomeTheme.accentPink.withValues(alpha: 0.18)
                : HomeTheme.cardSurface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? HomeTheme.accentPink : HomeTheme.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? HomeTheme.accentPink : HomeTheme.textMuted,
              fontSize: 12.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
