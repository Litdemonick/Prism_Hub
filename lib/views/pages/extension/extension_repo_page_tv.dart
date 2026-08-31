import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:get/get.dart';
import 'package:prismhub/controllers/extension/extension_repo_controller.dart';
import 'package:prismhub/models/extension.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/log.dart';
import 'package:prismhub/utils/prismhub_mas.dart';
import 'package:prismhub/views/pages/extension/catalogo_del_repo.dart';
import 'package:prismhub/views/widgets/cache_network_image.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/messenger.dart';
import 'package:prismhub/views/widgets/tv/columna_de_acciones.dart';
import 'package:prismhub/views/widgets/tv/focusable_card.dart';
import 'package:prismhub/views/widgets/tv/pantalla_tv.dart';
import 'package:prismhub/views/widgets/tv/teclado_tv.dart';

/// El repositorio de extensiones, para televisor.
///
/// ── Por qué no es la de teléfono ────────────────────────────────────────
///
/// La de teléfono/PC tiene tres secciones paginadas con sus flechitas, un
/// menú de filtros con cinco submenús adentro, y tarjetas con descripción,
/// licencia, sitio web y firma. Todo eso se lee sentado con el aparato en la
/// mano. Desde el sillón, con un mando, abrir un submenú para cambiar un
/// filtro son cinco pulsaciones y una capa que tapa la lista.
///
/// ── La forma ────────────────────────────────────────────────────────────
///
/// El mismo molde que el resto del televisor: título arriba a la izquierda
/// con su flecha, las funciones en la columna de la izquierda —buscar, la
/// zona, y qué mostrar— y el catálogo a la derecha ocupando lo que queda.
///
/// ── Qué se saca respecto de la de teléfono, y por qué ────────────────────
///
///   · **Lectura no está.** Regla del rediseño: en televisor solo vídeo. Una
///     extensión de manga instalada en un televisor es un motor de
///     JavaScript levantado para nada.
///   · **Las +18 tampoco.** En televisor la Zona +18 vive aparte, en Ajustes
///     y detrás de su PIN. Un catálogo donde aparecen al desplazarse es
///     justo lo que ese PIN existe para evitar.
///   · **El idioma y la licencia no se filtran.** Nadie hace eso desde el
///     sillón, y cada filtro de más es una fila más que recorrer con el
///     mando.
///
/// Lo que queda es lo que se hace de verdad acá: ver qué hay, buscar algo, e
/// instalarlo.
class ExtensionRepoPageTv extends StatefulWidget {
  const ExtensionRepoPageTv({super.key});

  @override
  State<ExtensionRepoPageTv> createState() => _ExtensionRepoPageTvState();
}

/// Qué parte del catálogo se está mirando.
enum _Vista {
  disponibles,
  instaladas,
  nuevas,
  rotas;

  String get etiqueta => switch (this) {
        _Vista.disponibles => 'extension-repo.tv-disponibles'.i18n,
        _Vista.instaladas => 'extension-repo.tv-instaladas'.i18n,
        _Vista.nuevas => 'extension-repo.tv-nuevas'.i18n,
        _Vista.rotas => 'extension.filter-unstable'.i18n,
      };

  IconData get icono => switch (this) {
        _Vista.disponibles => Icons.cloud_download_outlined,
        _Vista.instaladas => Icons.check_circle_outline_rounded,
        _Vista.nuevas => Icons.auto_awesome_outlined,
        _Vista.rotas => Icons.warning_amber_rounded,
      };
}

class _ExtensionRepoPageTvState extends State<ExtensionRepoPageTv> {
  late final ExtensionRepoPageController c =
      Get.isRegistered<ExtensionRepoPageController>()
          ? Get.find<ExtensionRepoPageController>()
          : Get.put(ExtensionRepoPageController());

  _Vista _vista = _Vista.disponibles;
  ZonaPrincipal? _zona;
  String _busqueda = '';
  bool _escribiendo = false;

  /// Está instalando la tanda entera ahora mismo.
  bool _instalandoTodas = false;

  /// Los paquetes que se están instalando de a uno, para poder pintar cada
  /// fila como «instalando» sin que una tanda tape a la otra.
  final _enVuelo = <String>{};

  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    // Si se vino acá desde un aviso que nombraba una extensión, se abre ya
    // buscada en vez de dejar a alguien rastreándola entre decenas.
    final pedido = ExtensionUtils.tomarFiltroPendiente();
    if (pedido != null && pedido.isNotEmpty) _busqueda = pedido;
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Los filtros de esta pantalla, traducidos a los del catálogo.
  ///
  /// `nsfwDesbloqueado: false` a propósito y sin ninguna forma de cambiarlo:
  /// en televisor las +18 no salen del repositorio, punto. Ver la nota de la
  /// clase.
  FiltrosDelRepo get _filtros => FiltrosDelRepo(
        texto: _busqueda,
        tipos: ExtensionUtils.videoTypes,
        zona: _zona,
        nivel: _vista == _Vista.rotas ? 'unstable' : 'stable',
        instalacion: switch (_vista) {
          _Vista.disponibles => 'available',
          _Vista.instaladas => 'installed',
          _Vista.nuevas => 'new',
          _Vista.rotas => 'all',
        },
      );

  List<EntradaDelRepo> get _visibles {
    final leidas = EntradaDelRepo.leerTodas(c.extensions);
    final filtradas = _filtros.aplicar(leidas, esNueva: c.esNueva);
    return [...filtradas]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  /// Cuántas hay en cada vista, para poder decirlo al lado del nombre.
  int _cuantasEn(_Vista v) {
    final leidas = EntradaDelRepo.leerTodas(c.extensions);
    return FiltrosDelRepo(
      texto: _busqueda,
      tipos: ExtensionUtils.videoTypes,
      zona: _zona,
      nivel: v == _Vista.rotas ? 'unstable' : 'stable',
      instalacion: switch (v) {
        _Vista.disponibles => 'available',
        _Vista.instaladas => 'installed',
        _Vista.nuevas => 'new',
        _Vista.rotas => 'all',
      },
    ).aplicar(leidas, esNueva: c.esNueva).length;
  }

  // ─── Instalar ──────────────────────────────────────────────────────────

  Map? _entradaCruda(String package) {
    for (final e in c.extensions) {
      if (e is Map && e['package']?.toString() == package) return e;
    }
    return null;
  }

  Future<void> _instalar(EntradaDelRepo e) async {
    if (e.instalada) {
      // Ya está: acá el botón desinstala. Es la única acción que queda para
      // una instalada, y tenerla acá evita ir a la otra pantalla solo para
      // sacar algo que se acaba de poner.
      await ExtensionUtils.uninstall(e.package);
      if (mounted) setState(() {});
      return;
    }
    if (e.unstable) {
      showPlatformSnackbar(
        context: context,
        title: 'extension.unstable-title'.i18n,
        content: e.claveDelBloqueo.i18n,
      );
      return;
    }
    final cruda = _entradaCruda(e.package);
    if (cruda == null) return;
    setState(() => _enVuelo.add(e.package));
    try {
      await ExtensionUtils.instalarDesdeCatalogo(cruda, context);
    } finally {
      if (mounted) setState(() => _enVuelo.remove(e.package));
    }
  }

  /// Instala TODO lo que la pantalla está mostrando ahora mismo.
  ///
  /// De a una y no todas a la vez: cada instalación baja el guion, verifica
  /// su firma y arranca el motor. Eso es trabajo de CPU y bloquea el hilo —
  /// encadenadas sin soltar, la pantalla no se dibuja hasta que termina la
  /// tanda entera y la app parece colgada. Mismo criterio que las tandas de
  /// la pantalla de instaladas.
  Future<void> _instalarTodas() async {
    if (_instalandoTodas) return;
    final paquetes = _visibles
        .where((e) => !e.instalada && !e.unstable)
        .map((e) => e.package)
        .toList(growable: false);
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
      for (final pkg in paquetes) {
        final cruda = _entradaCruda(pkg);
        if (cruda == null) continue;
        if (!mounted) return;
        try {
          if (await ExtensionUtils.instalarDesdeCatalogo(cruda, context)) {
            hechas++;
          } else {
            fallidas++;
          }
        } catch (e) {
          // Una que falle no puede frenar a las demás: puede ser una firma
          // que no valida o el sitio de descarga caído un momento.
          fallidas++;
          logger.info('[repositorio] no se pudo instalar $pkg: $e');
        }
        await ExtensionUtils.cederElCuadro();
      }
    } finally {
      if (mounted) setState(() => _instalandoTodas = false);
    }
    if (!mounted) return;
    // Explícito y sin confiar en el aviso que manda cada instalación: ese
    // aviso se junta con los de la ráfaga y llega un rato después, así que
    // las recién instaladas se quedaban un momento con el botón «Instalar»
    // puesto. Acá se sabe que la tanda terminó.
    await c.onRefresh(forceRefresh: false);
    if (!mounted) return;
    showPlatformSnackbar(
      context: context,
      title: 'extension.instalar-todas'.i18n,
      content: fallidas == 0
          ? FlutterI18n.translate(context, 'extension.masivo-instaladas',
              translationParams: {'n': '$hechas'})
          : FlutterI18n.translate(
              context,
              'extension.masivo-instaladas-con-fallos',
              translationParams: {'n': '$hechas', 'f': '$fallidas'},
            ),
    );
  }

  // ─── Pantalla ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      return PantallaTv(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_escribiendo) _teclado() else _columna(),
            const SizedBox(width: 24),
            Expanded(child: _contenido()),
          ],
        ),
      );
    });
  }

  Widget _columna() {
    return ColumnaDeAcciones(
      titulo: 'common.extension-repo'.i18n,
      detalle: FlutterI18n.translate(
        context,
        'extension-repo.tv-cuenta',
        translationParams: {'n': '${_cuantasEn(_Vista.disponibles)}'},
      ),
      grupos: [
        GrupoDeColumna(opciones: [
          OpcionDeColumna(
            icono: Icons.arrow_back_rounded,
            texto: 'extension.tv-volver'.i18n,
            onTap: () => Get.back<void>(),
          ),
        ]),
        GrupoDeColumna(
          titulo: 'extension.tv-buscar-y-filtrar'.i18n,
          opciones: [
            OpcionDeColumna(
              id: 'buscar',
              icono: Icons.search_rounded,
              texto: _busqueda.isEmpty ? 'common.search'.i18n : '«$_busqueda»',
              elegido: _busqueda.isNotEmpty,
              onTap: () => setState(() => _escribiendo = true),
            ),
            for (final v in _Vista.values)
              OpcionDeColumna(
                id: v.name,
                icono: v.icono,
                texto: '${v.etiqueta}  ·  ${_cuantasEn(v)}',
                elegido: _vista == v,
                onTap: () => setState(() => _vista = v),
              ),
          ],
        ),
        GrupoDeColumna(
          titulo: 'extension-repo.tv-zona'.i18n,
          opciones: [
            OpcionDeColumna(
              id: 'zona-todas',
              icono: Icons.apps_rounded,
              texto: 'extension.filter-all'.i18n,
              elegido: _zona == null,
              onTap: () => setState(() => _zona = null),
            ),
            // Mangas no está: en televisor solo se ve vídeo.
            for (final z in const [
              ZonaPrincipal.peliculas,
              ZonaPrincipal.series,
              ZonaPrincipal.anime,
            ])
              OpcionDeColumna(
                id: z.name,
                icono: switch (z) {
                  ZonaPrincipal.peliculas => Icons.movie_outlined,
                  ZonaPrincipal.series => Icons.tv_rounded,
                  _ => Icons.animation_rounded,
                },
                texto: 'home.zona-${z.name}'.i18n,
                elegido: _zona == z,
                onTap: () => setState(() => _zona = z),
              ),
          ],
        ),
        GrupoDeColumna(
          titulo: 'extension.acciones'.i18n,
          opciones: [
            OpcionDeColumna(
              id: 'instalar-todas',
              icono: Icons.download_for_offline_outlined,
              texto: _instalandoTodas
                  ? 'extension-repo.tv-instalando'.i18n
                  : 'extension.instalar-todas'.i18n,
              onTap: () => unawaited(_instalarTodas()),
            ),
            OpcionDeColumna(
              id: 'refrescar',
              icono: Icons.refresh_rounded,
              texto: 'common.refresh'.i18n,
              onTap: () => unawaited(c.onRefresh(forceRefresh: true)),
            ),
          ],
        ),
      ],
    );
  }

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

  Widget _contenido() {
    if (c.isLoading.value) {
      return Center(
        child: Text(
          'common.refreshing'.i18n,
          style: TextStyle(fontSize: 17, color: HomeTheme.textMuted),
        ),
      );
    }
    if (c.isError.value) return _fallo();
    final visibles = _visibles;
    if (visibles.isEmpty) return _vacio();
    return ListView.separated(
      controller: _scroll,
      scrollCacheExtent: PrismHubMas.cuantoSeConstruyeDeMas,
      padding: const EdgeInsets.only(top: 4, bottom: 24),
      itemCount: visibles.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _FilaDelRepo(
        entrada: visibles[i],
        instalando: _enVuelo.contains(visibles[i].package),
        onTap: () => unawaited(_instalar(visibles[i])),
      ),
    );
  }

  /// El fallo dice el motivo real, no solo «no se pudo».
  ///
  /// Sin el detalle era imposible distinguir estar sin internet de un
  /// repositorio que contesta algo que no se entiende — y desde un televisor,
  /// donde no hay forma de mirar el registro, esa diferencia es todo.
  Widget _fallo() => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_rounded,
                  size: 56, color: HomeTheme.textMuted),
              const SizedBox(height: 18),
              Text(
                'extension-repo.error'.i18n,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: HomeTheme.textPrimary,
                ),
              ),
              if (c.errorDetalle.value.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  c.errorDetalle.value,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: HomeTheme.textMuted,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              // Enfocable: sin esto, en un televisor el único camino sería
              // salir de la pantalla y volver a entrar.
              FocusableCard(
                borderRadius: 10,
                autofocus: true,
                onTap: () => unawaited(c.onRefresh(forceRefresh: true)),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                  decoration: BoxDecoration(
                    color: HomeTheme.cardSurface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'common.retry'.i18n,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: HomeTheme.textPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _vacio() {
    final (titulo, detalle) = _busqueda.isNotEmpty
        ? (
            'extension.tv-sin-resultados'.i18n,
            FlutterI18n.translate(
              context,
              'extension.tv-sin-resultados-detalle',
              translationParams: {'texto': _busqueda},
            ),
          )
        : (
            'extension-repo.empty'.i18n,
            FlutterI18n.translate(
              context,
              'extension-repo.tv-vacio-detalle',
              translationParams: {'vista': _vista.etiqueta},
            ),
          );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.travel_explore_outlined,
                size: 56, color: HomeTheme.textMuted),
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

/// Una extensión del catálogo, en una fila del ancho entero.
///
/// Una sola cosa enfocable, a diferencia de la lista de instaladas: acá hay
/// una sola acción por fila —instalar, o desinstalar si ya está— y partirla
/// en dos blancos solo agregaría un paso a la única cosa que se viene a
/// hacer.
class _FilaDelRepo extends StatelessWidget {
  const _FilaDelRepo({
    required this.entrada,
    required this.instalando,
    required this.onTap,
  });

  final EntradaDelRepo entrada;
  final bool instalando;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final instalada = entrada.instalada;
    return FocusableCard(
      borderRadius: 12,
      conCrecido: false,
      onTap: onTap,
      child: Container(
        height: 68,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: HomeTheme.cardSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border(
            left: BorderSide(
              width: 4,
              color: entrada.unstable
                  ? HomeTheme.accentRed.withValues(alpha: 0.8)
                  : instalada
                      ? HomeTheme.accentPink
                      : HomeTheme.border.withValues(alpha: 0.6),
            ),
          ),
        ),
        child: Row(
          children: [
            _icono(context),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entrada.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: HomeTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    // La descripción cuando la hay: es lo que ayuda a decidir
                    // si vale la pena instalarla, y en una fila entra sin
                    // pelearle el sitio a nada.
                    entrada.description?.trim().isNotEmpty == true
                        ? entrada.description!.trim()
                        : 'v${entrada.version} · ${entrada.lang.toUpperCase()}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontSize: 12.5, color: HomeTheme.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _estado(instalada),
          ],
        ),
      ),
    );
  }

  Widget _estado(bool instalada) {
    final (texto, color) = instalando
        ? ('extension-repo.tv-instalando'.i18n, HomeTheme.accentPink)
        : entrada.unstable
            ? ('extension-repo.tv-rota'.i18n, HomeTheme.accentRed)
            : instalada
                ? ('extension-repo.tv-puesta'.i18n, HomeTheme.accentPink)
                : ('common.install'.i18n, HomeTheme.textMuted);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        texto.toUpperCase(),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: color,
        ),
      ),
    );
  }

  Widget _icono(BuildContext context) {
    const lado = 40.0;
    final url = entrada.icon;
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
          entrada.name.characters.first.toUpperCase(),
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
        cacheWidth: (lado * MediaQuery.devicePixelRatioOf(context)).ceil(),
      ),
    );
  }
}
