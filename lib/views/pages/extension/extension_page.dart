import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:get/get.dart';
import 'package:prismhub/models/extension.dart';
import 'package:prismhub/controllers/extension/extension_controller.dart';
import 'package:prismhub/views/widgets/franja_de_zona.dart';
import 'package:prismhub/views/widgets/extension/extension_tile.dart';
import 'package:prismhub/views/pages/extension/extension_repo_page.dart';
import 'package:prismhub/views/widgets/home/animated_background_glow.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/home/indicadores_de_pagina.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/utils/log.dart';
import 'package:prismhub/utils/breakpoints.dart';
import 'package:prismhub/utils/search_text.dart';
import 'package:prismhub/router/router.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/router.dart';
import 'package:prismhub/views/widgets/button.dart';
import 'package:prismhub/views/widgets/messenger.dart';
import 'package:prismhub/views/widgets/platform_widget.dart';

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

  // ── En el teléfono la página se cambia deslizando ──────────────────────
  //
  // Las flechitas se quedan en escritorio, donde hay un ratón y un puntero
  // fino. Con el dedo, deslizar es el gesto natural —es el que ya se usa en el
  // acordeón del Inicio— y encima devuelve la franja de abajo que ocupaban los
  // botones: son tarjetas que se ven.
  //
  // El PageController se crea acá y no en `build` porque tiene que sobrevivir a
  // los redibujados: si se armara nuevo en cada uno, la página volvería a la
  // primera cada vez que llega una extensión.
  final _paginas = PageController();

  /// Deja el deslizador en la página que dice el estado.
  ///
  /// Hace falta porque `_page` cambia también desde afuera del gesto: al
  /// filtrar, al buscar y al desinstalar vuelve a cero, y ahí el PageController
  /// no se entera solo. Se pide para el próximo cuadro porque esto se llama
  /// desde `build` y saltar de página en medio de un dibujo dispara un
  /// `setState` mientras Flutter todavía está dibujando.
  void _seguirLaPagina(int pagina) {
    if (!_paginas.hasClients) return;
    final actual = _paginas.page?.round() ?? _paginas.initialPage;
    if (actual == pagina) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_paginas.hasClients) return;
      if ((_paginas.page?.round() ?? 0) == pagina) return;
      _paginas.jumpToPage(pagina);
    });
  }

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
  /// Hay una acción masiva corriendo AHORA MISMO.
  ///
  /// ── Una sola para las cuatro ────────────────────────────────────────────
  ///
  /// Activar, desactivar, actualizar y desinstalar tocan todas lo mismo: la
  /// lista de extensiones instaladas y sus archivos en disco. Dos a la vez no es
  /// «el doble de rápido», es una carrera: desinstalar mientras se actualiza deja
  /// media extensión escrita, y activar mientras se desinstala vuelve a prender
  /// algo que ya no está.
  ///
  /// Con una sola marca compartida, la primera que arranca bloquea las cuatro
  /// hasta terminar. Y como cada botón la mira para apagarse, tocar quince veces
  /// hace exactamente lo mismo que tocar una.
  bool _masivoEnCurso = false;

  /// Corre una acción masiva con el paso cerrado detrás.
  ///
  /// El `finally` no es adorno: si la de adentro tira una excepción y la marca
  /// quedara puesta, los cuatro botones se apagarían para siempre y habría que
  /// reiniciar la app para volver a usarlos.
  Future<void> _conElPasoCerrado(Future<void> Function() accion) async {
    if (_masivoEnCurso) return;
    setState(() => _masivoEnCurso = true);
    try {
      await accion();
    } finally {
      if (mounted) setState(() => _masivoEnCurso = false);
    }
  }

  Future<void> _cambiarTodas(bool activar) async {
    final visibles = _applyFilters(c.runtimes.values.toList(growable: false));
    if (visibles.isEmpty) return;

    // Las +18 no se prenden en masa si el interruptor general está apagado.
    // Activarlas igual dejaría contenido adulto disponible sin que nadie lo
    // haya pedido, que es justo lo que ese interruptor existe para evitar.
    var salteadas = 0;
    final paquetes = <String>[];
    for (final r in visibles) {
      final ext = r.extension;
      if (activar && !ExtensionUtils.isNsfwVisibleOutsideZone(ext.nsfw)) {
        salteadas++;
        continue;
      }
      paquetes.add(ext.package);
    }
    // Una sola llamada y no una por extensión.
    //
    // En bucle, cada vuelta leía y reescribía la lista entera de desactivadas
    // Y pedía recargar Inicio, Buscar, Instaladas y el Repositorio. Con
    // diecisiete instaladas eran diecisiete cascadas encimadas y el app se
    // quedaba sin responder — reportado en vivo, no se podía tocar nada.
    await ExtensionUtils.setExtensionsEnabled(paquetes, activar);
    if (!mounted) return;
    final hechas = visibles.length - salteadas;
    // Frase entera, no un número suelto: «17» a secas no dice si son las que
    // se cambiaron, las que quedaron o cuántas hay en total.
    final base = FlutterI18n.translate(
      context,
      activar ? 'extension.masivo-activadas' : 'extension.masivo-desactivadas',
      translationParams: {'n': '$hechas'},
    );
    showPlatformSnackbar(
      context: context,
      title: activar
          ? 'extension.activar-todas'.i18n
          : 'extension.desactivar-todas'.i18n,
      content:
          salteadas == 0 ? base : '$base ${'extension.masivo-salteadas'.i18n}',
    );
  }

  /// Está actualizando todas ahora mismo.
  bool _actualizandoTodas = false;

  /// Baja la última versión de cada extensión instalada que tenga una.
  ///
  /// ── Por qué de a una y no todas a la vez ────────────────────────────────
  ///
  /// Cada actualización baja un guion, verifica su firma y reinstala. Diecisiete
  /// en paralelo es diecisiete descargas y diecisiete verificaciones peleando
  /// por el mismo hilo, y encima el catálogo se pide una vez por cada una.
  ///
  /// De a una tarda más, pero se puede contar cuántas van, y si una falla las
  /// demás siguen. Es una acción que se hace de vez en cuando, no algo que
  /// tenga que ser instantáneo.
  ///
  /// ── Sobre TODAS las instaladas, no sobre las filtradas ──────────────────
  ///
  /// Al revés que activar/desactivar. Ahí el botón hace lo que la pantalla
  /// muestra porque prender de más es un error caro. Acá no: dejar una
  /// extensión sin actualizar porque justo estaba filtrada no le sirve a nadie,
  /// y una desactualizada deja de funcionar sin avisar.
  Future<void> _actualizarTodas() async {
    if (_actualizandoTodas) return;
    setState(() => _actualizandoTodas = true);
    var hechas = 0;
    var fallidas = 0;
    try {
      final instaladas = c.runtimes.values.toList(growable: false);
      for (final r in instaladas) {
        final pkg = r.extension.package;
        try {
          if (!await ExtensionUtils.hasExtensionUpdate(pkg)) continue;
          if (!mounted) return;
          await ExtensionUtils.updateInstalledFromRepo(pkg, context);
          hechas++;
          // Un cuadro para la pantalla: reinstalar arranca el runtime, que es
          // trabajo de CPU y bloquea el isolate entero. Sin esto la tanda deja
          // el app sin dibujar de punta a punta.
          await ExtensionUtils.cederElCuadro();
        } catch (e) {
          // Una que falle no puede frenar a las demás: puede ser una extensión
          // retirada del catálogo, o el sitio de descarga caído un momento.
          fallidas++;
          logger.info('[extensiones] no se pudo actualizar $pkg: $e');
        }
      }
    } finally {
      if (mounted) setState(() => _actualizandoTodas = false);
    }
    if (!mounted) return;
    showPlatformSnackbar(
      context: context,
      title: 'extension.actualizar-todas'.i18n,
      content: hechas == 0 && fallidas == 0
          ? 'extension.masivo-al-dia'.i18n
          : FlutterI18n.translate(
              context,
              'extension.masivo-actualizadas',
              translationParams: {'n': '$hechas'},
            ),
    );
  }

  /// Está desinstalando todas ahora mismo.
  bool _desinstalandoTodas = false;

  /// Borra de golpe las extensiones que se están viendo.
  ///
  /// ── Sobre las FILTRADAS, y con confirmación ─────────────────────────────
  ///
  /// Mismo criterio que activar/desactivar: el botón hace lo que la pantalla
  /// muestra. Si alguien está viendo «+18» y toca desinstalar, espera que se
  /// vayan esas, no las diecisiete.
  ///
  /// A diferencia de los otros botones masivos, este no se deshace: volver
  /// atrás significa reinstalar una por una y perder los ajustes de cada una.
  /// Por eso pregunta antes, y dice cuántas son — «desinstalar todas» sin un
  /// número es justo el aviso que la gente acepta sin leer.
  Future<void> _desinstalarTodas() async {
    if (_desinstalandoTodas) return;
    final visibles = _applyFilters(c.runtimes.values.toList(growable: false));
    if (visibles.isEmpty) return;

    final confirma = await showPlatformDialog(
      context: context,
      title: 'extension.desinstalar-todas'.i18n,
      content: Text(FlutterI18n.translate(
        context,
        'extension.masivo-confirmar-borrado',
        translationParams: {'n': '${visibles.length}'},
      )),
      actions: [
        PlatformTextButton(
          onPressed: () => RouterUtils.pop(false),
          child: Text('common.cancel'.i18n),
        ),
        PlatformFilledButton(
          onPressed: () => RouterUtils.pop(true),
          child: Text('common.confirm'.i18n),
        ),
      ],
    );
    if (confirma != true || !mounted) return;

    setState(() => _desinstalandoTodas = true);
    var hechas = 0;
    try {
      for (final r in visibles) {
        try {
          await ExtensionUtils.uninstall(r.extension.package);
          hechas++;
        } catch (e) {
          // Un archivo trabado por el sistema no puede dejar a medias el resto.
          logger.info('[extensiones] no se pudo desinstalar '
              '${r.extension.package}: $e');
        }
        // Igual que en las otras tandas: un cuadro para la pantalla entre una
        // y otra, así la rueda se mueve y el app no parece colgado.
        await ExtensionUtils.cederElCuadro();
      }
    } finally {
      if (mounted) setState(() => _desinstalandoTodas = false);
    }
    if (!mounted) return;
    showPlatformSnackbar(
      context: context,
      title: 'extension.desinstalar-todas'.i18n,
      content: FlutterI18n.translate(
        context,
        'extension.masivo-desinstaladas',
        translationParams: {'n': '$hechas'},
      ),
    );
  }

  /// La barra de filtros: los chips con un botón a cada lado.
  ///
  /// ── Por qué así y no de las otras dos formas que se probaron ────────────
  ///
  /// Juntos y centrados quedaban a un par de píxeles uno del otro, y hacen
  /// cosas OPUESTAS: apagar las diecisiete cuando se querían prender es un
  /// error caro de deshacer. Después se separaron a las puntas de la pantalla
  /// y quedaron sueltos, lejos de todo, como si no fueran parte de la barra.
  ///
  /// Flanqueando los chips quedan separados entre sí —que es lo que importa—
  /// pero agrupados con lo demás.
  ///
  /// En pantalla angosta no entran los tres en una línea: ahí los botones van
  /// arriba y los chips debajo. Forzarlos igual dejaría los chips en una
  /// rendija de cien píxeles.
  Widget _buildBarraDeFiltros() {
    final activar = _BotonMasivo(
      icono: _masivoEnCurso
          ? Icons.hourglass_top_rounded
          : Icons.toggle_on_outlined,
      label: 'extension.activar-todas'.i18n,
      onTap: _masivoEnCurso
          ? null
          : () => _conElPasoCerrado(() => _cambiarTodas(true)),
    );
    final desactivar = _BotonMasivo(
      icono: _masivoEnCurso
          ? Icons.hourglass_top_rounded
          : Icons.toggle_off_outlined,
      label: 'extension.desactivar-todas'.i18n,
      onTap: _masivoEnCurso
          ? null
          : () => _conElPasoCerrado(() => _cambiarTodas(false)),
    );
    final desinstalar = _BotonMasivo(
      icono: _masivoEnCurso
          ? Icons.hourglass_top_rounded
          : Icons.delete_sweep_outlined,
      label: 'extension.desinstalar-todas'.i18n,
      onTap: _masivoEnCurso ? null : () => _conElPasoCerrado(_desinstalarTodas),
    );
    final actualizar = _BotonMasivo(
      icono: _masivoEnCurso
          ? Icons.hourglass_top_rounded
          : Icons.system_update_alt_rounded,
      label: 'extension.actualizar-todas'.i18n,
      // Mientras corre, no se puede volver a tocar: son diecisiete descargas y
      // dispararlas dos veces solo duplica el trabajo.
      onTap: _masivoEnCurso ? null : () => _conElPasoCerrado(_actualizarTodas),
    );

    // ── Una línea o dos, y no lo decide solo el ancho ─────────────────────
    //
    // En horizontal, un teléfono tiene ancho DE SOBRA y poca altura. Mirando
    // solo el ancho, esto apilaba los botones sobre los chips y se comía el
    // espacio vertical que es justamente el que falta: quedaba una franja de
    // lista tan baja que no se veían bien las tarjetas (reportado en vivo).
    //
    // Así que también cuenta el alto: con pantalla baja se usa UNA línea
    // aunque el ancho no dé para «amplio». Es donde más se nota y donde hay
    // ancho para hacerlo.
    final alto = MediaQuery.sizeOf(context).height;
    final unaSolaLinea = Ancho.de(context).alMenosAmplio || alto < 520;

    if (!unaSolaLinea) {
      return Column(
        children: [
          // Los tres en una fila que se puede correr: en un teléfono angosto
          // no entran, y partirlos en dos líneas se comería el alto que le
          // falta a la lista.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                activar,
                const SizedBox(width: 10),
                desactivar,
                const SizedBox(width: 10),
                actualizar,
                const SizedBox(width: 10),
                desinstalar,
              ],
            ),
          ),
          const SizedBox(height: 10),
          _buildFilterChips(),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        activar,
        const SizedBox(width: 14),
        // Flexible y no Expanded: así los chips ocupan lo que necesitan y el
        // conjunto queda centrado. Con Expanded se estirarían hasta el borde y
        // los botones volverían a quedar en las puntas.
        Flexible(child: _buildFilterChips()),
        const SizedBox(width: 14),
        desactivar,
        const SizedBox(width: 10),
        actualizar,
        const SizedBox(width: 10),
        desinstalar,
      ],
    );
  }

  /// La hoja con los filtros y las acciones.
  void _abrirPanel() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: HomeTheme.cardSurface,
      builder: (hojaContext) {
        // StatefulBuilder para que al tocar un chip se repinte la hoja: el
        // setState de la página no llega acá, que es otro árbol.
        return StatefulBuilder(
          builder: (hojaContext, setHoja) {
            Widget accion({
              required IconData icono,
              required String texto,
              required Future<void> Function() alTocar,
              Color? color,
            }) {
              return ListTile(
                enabled: !_masivoEnCurso,
                leading: Icon(
                  _masivoEnCurso ? Icons.hourglass_top_rounded : icono,
                  color: color ?? HomeTheme.textPrimary,
                ),
                title: Text(
                  texto,
                  style: TextStyle(color: color ?? HomeTheme.textPrimary),
                ),
                onTap: () {
                  // Se cierra ANTES de arrancar: son acciones largas, y dejar
                  // la hoja abierta encima tapa el aviso del final y deja
                  // tocar otra cosa mientras corre.
                  Navigator.of(hojaContext).pop();
                  unawaited(_conElPasoCerrado(alTocar));
                },
              );
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'search.filter'.i18n,
                    style: const TextStyle(
                      color: HomeTheme.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final f in _ExtFilter.values)
                        _ExtFilterChip(
                          label: f.label,
                          selected: _filter == f,
                          onTap: () {
                            // Las dos pantallas a la vez: la hoja para que el
                            // chip se marque, y la página para que la lista se
                            // rearme detrás mientras la hoja sigue abierta.
                            setHoja(() {});
                            setState(() {
                              _filter = f;
                              // Vuelve a la página 0: con menos resultados,
                              // quedarse en la 3 mostraba una lista vacía sin
                              // explicación.
                              _page = 0;
                            });
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Divider(height: 1, color: HomeTheme.border),
                  const SizedBox(height: 12),
                  Text(
                    'extension.acciones'.i18n,
                    style: const TextStyle(
                      color: HomeTheme.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  accion(
                    icono: Icons.toggle_on_outlined,
                    texto: 'extension.activar-todas'.i18n,
                    alTocar: () => _cambiarTodas(true),
                  ),
                  accion(
                    icono: Icons.toggle_off_outlined,
                    texto: 'extension.desactivar-todas'.i18n,
                    alTocar: () => _cambiarTodas(false),
                  ),
                  accion(
                    icono: Icons.system_update_alt_rounded,
                    texto: 'extension.actualizar-todas'.i18n,
                    alTocar: _actualizarTodas,
                  ),
                  // Última y en rojo: es la única que no se deshace. Ya
                  // pregunta antes (ver _desinstalarTodas), pero que se vea
                  // distinta evita el toque por inercia.
                  accion(
                    icono: Icons.delete_sweep_outlined,
                    texto: 'extension.desinstalar-todas'.i18n,
                    alTocar: _desinstalarTodas,
                    color: const Color(0xFFE5484D),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFilterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      // Centrados cuando entran todos, y desplazables cuando no.
      //
      // `Center` a secas no alcanza dentro de un desplazamiento horizontal: si
      // la fila es más ancha que la pantalla, centrarla recorta el primer chip
      // y no se puede llegar a él. Con esto, el contenido se centra solo
      // mientras sobre lugar y se comporta como una lista normal cuando no.
      padding: EdgeInsets.zero,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
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
    _paginas.dispose();
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
  /// Envuelve una lista para que se pueda tirar de ella y refrescar.
  ///
  /// Con nombre porque ahora hay una por página del deslizador, y el
  /// RefreshIndicator tiene que ir ADENTRO de cada una: puesto por fuera del
  /// PageView no encuentra a quién escucharle el tirón —el PageView se desplaza
  /// de costado, no para abajo— y el gesto se perdía.
  Widget _conRefresco(Widget lista) {
    return RefreshIndicator(
      onRefresh: () async {
        // desdeElBoton: lo pidio el usuario, asi que se vuelve a pedir el
        // catalogo de verdad. Limpiar la cache no alcanzaba: onRefresh solo
        // releia los mapas locales, y el fetch recien salia cuando alguna
        // tarjeta lo pedia por su cuenta — para entonces la pantalla ya se
        // habia dibujado con los datos viejos.
        await c.onRefresh(desdeElBoton: true);
      },
      color: HomeTheme.accentPink,
      backgroundColor: HomeTheme.cardSurface,
      child: lista,
    );
  }

  /// Las rayitas de abajo: en cuál página vas.
  ///
  /// ── No crecen con las páginas ───────────────────────────────────────────
  ///
  /// Con veinte páginas, veinte rayitas son una línea punteada donde no se
  /// distingue cuál está encendida, y encima la fila cambia de ancho cada vez
  /// que entra o sale una extensión. Con el tope, cada raya representa un tramo
  /// y la fila mide siempre lo mismo.
  Widget _rayitas(int page, int totalPages) {
    const tope = IndicadoresDePagina.maximo;
    final cortas = totalPages <= tope;
    return IndicadoresDePagina(
      cantidad: cortas ? totalPages : tope,
      actual: cortas ? page : (page * tope ~/ totalPages).clamp(0, tope - 1),
      onTocar: (i) {
        final destino =
            cortas ? i : (i * totalPages ~/ tope).clamp(0, totalPages - 1);
        setState(() => _page = destino);
      },
    );
  }

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
    // ── Con el dedo, grandes y con forma de botón ────────────────────────
    //
    // Ahora que van al final de la lista, son lo último que se ve y lo que hay
    // que tocar para seguir. Dos flechitas finas sobre el fondo negro no se
    // leen como algo que se pueda tocar: se pierden.
    //
    // En el teléfono van en un círculo con su superficie y su borde —los
    // mismos de las tarjetas— y con el número más grande en el medio. En el
    // escritorio se quedan compactas: ahí es un ratón, no un dedo, y la
    // paginación va apretada arriba del grid.
    final textStyle = TextStyle(
      fontSize: useFluent ? 11 : 14,
      fontWeight: useFluent ? FontWeight.normal : FontWeight.w700,
      color: useFluent ? HomeTheme.textMuted : HomeTheme.textPrimary,
    );
    final tapSize = useFluent ? 20.0 : 52.0;
    final iconSize = useFluent ? 14.0 : 28.0;
    Widget arrow(IconData icon, bool enabled, VoidCallback onTap) {
      final color = enabled
          ? (useFluent ? HomeTheme.textMuted : HomeTheme.textPrimary)
          : HomeTheme.textMuted.withValues(alpha: 0.3);
      return MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          onTap: enabled ? onTap : null,
          child: Container(
            width: tapSize,
            height: tapSize,
            decoration: useFluent
                ? null
                : BoxDecoration(
                    shape: BoxShape.circle,
                    // Apagado también se ve, pero sin invitar: si desaparece,
                    // en la última página parece que faltara un botón.
                    color: enabled
                        ? HomeTheme.cardSurface
                        : HomeTheme.cardSurface.withValues(alpha: 0.5),
                    border: Border.all(
                      color: enabled
                          ? HomeTheme.border
                          : HomeTheme.border.withValues(alpha: 0.5),
                    ),
                  ),
            child: Center(child: Icon(icon, size: iconSize, color: color)),
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
      // El deslizador tiene que quedar donde dice el estado: al filtrar, al
      // buscar y al desinstalar la pagina vuelve a cero desde afuera del gesto.
      _seguirLaPagina(page);
      return Scaffold(
        backgroundColor: HomeTheme.bg,
        // Sin AppBar: el título va en la franja fina, dentro del cuerpo (ver
        // FranjaDeZona). Una AppBar mide 56 y dibuja su propia superficie;
        // acá el contenido pasa justo debajo del título, como en Inicio y en
        // la Biblioteca, y acostado eso es media fila de tarjetas.
        body: Stack(
          children: [
            const Positioned.fill(child: AnimatedBackgroundGlow()),
            // ── Acá la franja se queda fija ─────────────────────────────
            //
            // Es la única zona que no la puede meter dentro de su área
            // desplazable: las páginas van en un deslizador horizontal, y
            // meter el buscador adentro serían tres campos de texto vivos a la
            // vez peleándose el foco. Ver la nota en franja_de_zona.dart.
            Column(
              children: [
                FranjaDeZona(
                  titulo: 'common.extension-installed'.i18n,
                  ayuda: 'common.search'.i18n,
                  controlador: _androidSearchController,
                  alEscribir: (value) {
                    if (value.isEmpty) {
                      setState(() {
                        _search = '';
                        _page = 0;
                      });
                    }
                  },
                  alEnviar: (value) {
                    setState(() {
                      _search = value;
                      _page = 0;
                    });
                  },
                  acciones: [
                    // ── El filtro vive en la franja de arriba ─────────────
                    //
                    // No en una fila propia debajo. Esa fila se llevaba su
                    // alto entero justo encima de la lista, y acostado —donde
                    // el alto es lo que falta— eso es media pantalla de
                    // tarjetas.
                    //
                    // El puntito avisa que hay un filtro puesto: metido dentro
                    // de la hoja, uno se olvida de que filtró y la lista corta
                    // parece un error.
                    AccionDeFranja(
                      ayuda: 'search.filter'.i18n,
                      alTocar: _abrirPanel,
                      icono: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Icon(
                            _masivoEnCurso
                                ? Icons.hourglass_top_rounded
                                : Icons.tune_rounded,
                          ),
                          if (_filter != _ExtFilter.todas)
                            Positioned(
                              right: -1,
                              top: -1,
                              child: Container(
                                width: 9,
                                height: 9,
                                decoration: const BoxDecoration(
                                  color: HomeTheme.accentPink,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (c.errors.isNotEmpty)
                      AccionDeFranja(
                        icono: const Icon(Icons.error),
                        alTocar: () => _loadErrorDialog(),
                      ),
                    AccionDeFranja(
                      icono: const Icon(Icons.download),
                      alTocar: () => Get.to(() => const ExtensionRepoPage()),
                    ),
                  ],
                ),
                Expanded(
                    child: Stack(
                  children: [
                    installed.isEmpty
                        ? _conRefresco(
                            ListView(
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
                            ),
                          )
                        // ── Se desliza para cambiar de página ────────────
                        //
                        // El PageView es horizontal y la lista de adentro
                        // vertical, así que los dos gestos conviven sin pelearse:
                        // arrastrar de costado cambia de página y tirar para
                        // abajo sigue refrescando.
                        //
                        // Cada página arma SU tanda acá adentro en vez de recibir
                        // la de afuera: las de al lado también se construyen al
                        // asomar, y con una sola tanda se verían las mismas cinco
                        // extensiones en las tres.
                        : PageView.builder(
                            controller: _paginas,
                            itemCount: totalPages,
                            onPageChanged: (i) => setState(() => _page = i),
                            itemBuilder: (_, p) {
                              final dePagina = installed
                                  .skip(p * _pageSize)
                                  .take(_pageSize)
                                  .toList();
                              return _conRefresco(
                                ListView.builder(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  // Espacio a los costados y entre cards — antes
                                  // iban pegadas al borde de la pantalla.
                                  //
                                  // El hueco de la barra flotante ya NO se
                                  // reserva acá: debajo de la lista van las
                                  // rayitas, y son ellas las que tienen que
                                  // quedar por encima de la barra. Reservándolo
                                  // en los dos lados se contaba dos veces y
                                  // quedaba un hueco enorme.
                                  // `arriba` deja libre lo que ocupa la franja
                                  // que flota encima: sin eso la primera tarjeta
                                  // arranca tapada. Ver FranjaQueSeVa.
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 0, 16, 8),
                                  itemCount: dePagina.length,
                                  // Sin RepaintBoundary a mano: ListView.builder
                                  // ya envuelve cada ítem en uno
                                  // (SliverChildBuilderDelegate
                                  // .addRepaintBoundaries viene en true). Ponerlo
                                  // acá sería una capa anidada de gusto. La
                                  // grilla de más abajo SÍ lo necesita, porque
                                  // ahí las tarjetas se arman con un for suelto y
                                  // no pasan por ese delegate.
                                  itemBuilder: (_, i) =>
                                      ExtensionTile(dePagina[i].extension),
                                ),
                              );
                            },
                          ),
                    // ── Rayitas abajo, ENCIMA de la lista ─────────────────
                    //
                    // Antes iban en la columna, debajo de la lista, y por eso le
                    // comían su alto: la lista terminaba justo arriba de la barra
                    // de navegación y detrás de la barra no pasaba nada. Con el
                    // fondo liso ahí, la barra flotante parecía tener un fondo
                    // propio en vez de dejar ver lo de atrás.
                    //
                    // Ahora la lista usa la pantalla entera y pasa por debajo de
                    // la barra —el cuerpo ya lo hace, `extendBody` en main_page—
                    // así que se ven las tarjetas moviéndose detrás de ella. Las
                    // rayitas flotan encima, en su sitio de siempre.
                    //
                    // Y son rayitas, no flechas: con el dedo la página se cambia
                    // deslizando, así que abajo solo hace falta decir en cuál
                    // vas. Las mismas del acordeón del Inicio.
                    if (totalPages > 1)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: MediaQuery.paddingOf(context).bottom + 2,
                        child: Center(child: _rayitas(page, totalPages)),
                      ),
                  ],
                )),
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
              _buildBarraDeFiltros(),
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
                                          // Su capa propia, igual que en la
                                          // lista de arriba.
                                          child: RepaintBoundary(
                                            child: ExtensionTile(ext.extension),
                                          ),
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
  final VoidCallback? onTap;

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
