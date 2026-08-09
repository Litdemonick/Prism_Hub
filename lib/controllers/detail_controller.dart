// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:get/get.dart';
import 'package:prismhub/data/providers/tmdb_provider.dart';
import 'package:prismhub/models/index.dart';
import 'package:prismhub/views/dialogs/tmdb_binding.dart';
import 'package:prismhub/controllers/home_controller.dart';
import 'package:prismhub/controllers/main_controller.dart';
import 'package:prismhub/views/pages/watch/watch_page.dart';
import 'package:prismhub/views/widgets/deferred_route_content.dart';
import 'package:prismhub/views/widgets/progress.dart';
import 'package:prismhub/router/router.dart';
import 'package:prismhub/data/services/database_service.dart';
import 'package:prismhub/utils/error.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/utils/forma_portada.dart';
import 'package:prismhub/utils/portada_adelantada.dart';
import 'package:prismhub/utils/portadas_perdidas.dart';
import 'package:prismhub/data/services/extension_service.dart';
import 'package:prismhub/utils/external_player.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/prismhub_storage.dart';
import 'package:prismhub/views/widgets/messenger.dart';
import 'package:prismhub/views/widgets/nsfw_confirm_dialog.dart';

class DetailPageController extends GetxController {
  DetailPageController({
    required this.package,
    required this.url,
    this.heroTag,
    this.isAdultOption = false,
  });

  // Caché en memoria por sesión: evita re-fetch al volver al mismo detalle.
  // Se invalida al hacer pull-to-refresh manual (onRefresh() con clearCache=true).
  static final Map<String, ExtensionDetail> _sessionCache = {};
  static const _sessionCacheLimit = 60;

  static void clearSessionCache() => _sessionCache.clear();

  // Mapa insertion-ordered: al reinsertar una key se la manda al final (LRU),
  // y si se pasa el límite se descarta la más vieja (la primera).
  static void _putSessionCache(String key, ExtensionDetail value) {
    _sessionCache.remove(key);
    _sessionCache[key] = value;
    if (_sessionCache.length > _sessionCacheLimit) {
      _sessionCache.remove(_sessionCache.keys.first);
    }
  }

  final String package;
  final String url;
  final String? heroTag;
  // Zona +18: true si se llegó acá desde la opción "adultos" de un filtro
  // de una extensión mixta (ej. ShadeManga/ManhwaWeb — ver
  // ExtensionFilter.adultOption y ExtensionSearcherPage._adultOptionSelected).
  // Atajo: si ya viene en true, _resolveNsfwStatus no necesita preguntar.
  final bool isAdultOption;

  // No se puede saber automáticamente, ítem por ítem, si algo es +18 o no —
  // así que se le pregunta al usuario UNA vez por título, al mirar/leer o al
  // marcar favorito, y se recuerda la respuesta (queda guardada en el propio
  // History/Favorite, así que no se vuelve a preguntar nunca por ese título).
  //
  // Se pregunta en TODA extensión, no solo en las marcadas nsfw:true: a pedido
  // explícito, una extensión sin esa marca igual puede tener contenido +18
  // suelto, y el usuario tiene que poder mandarlo a la Zona +18. Antes se
  // cortaba acá para las no-nsfw y nunca preguntaba.
  bool? _nsfwAnswer;

  // null = el usuario canceló (tocó afuera del diálogo) sin elegir Sí/No —
  // quien llama a esto DEBE tratar null como "abortar la acción entera"
  // (no favoritear, no abrir el reproductor/lector), no como "No". Antes
  // tocar afuera devolvía false igual que "No" y la acción seguía de largo
  // (favoriteaba igual, mandándolo al Home normal sin querer).
  Future<bool?> resolveIsNsfw(BuildContext context,
      {bool opening = true}) async {
    // Ya se guardó antes (con esta respuesta o con el default de un
    // registro viejo, previo a este campo) — no se vuelve a preguntar.
    if (history.value != null) return history.value!.isNsfw;
    if (favorite.value != null) return favorite.value!.isNsfw;
    if (_nsfwAnswer != null) return _nsfwAnswer!;
    // Venir del filtro "+18" de la extensión ya NO responde solo: antes acá
    // había un `if (isAdultOption) return true;` que daba por hecho el sí. A
    // pedido explícito se pregunta igual — el filtro dice qué se está
    // explorando, no que ESTE título puntual sea +18.
    final result = await showNsfwConfirmDialog(
      context,
      title: detail?.title ?? '',
      type: type,
      opening: opening,
      // Cambia el tono del aviso (rojo, con advertencia y la opción "sí"
      // primero) cuando la extensión ya viene marcada +18 en el catálogo:
      // preguntar en frío ahí quedaba raro, como si nada lo sugiriera.
      extensionIsNsfw: extension?.nsfw ?? false,
    );
    // Tocar afuera: result queda null — NO se cachea nada en _nsfwAnswer,
    // así que la próxima vez se vuelve a preguntar en vez de quedar
    // "decidido" con una respuesta que el usuario nunca dio.
    if (result == null) return null;
    _nsfwAnswer = result == true;
    return _nsfwAnswer!;
  }

  ScrollController scrollController = ScrollController();

  final RxBool isFavorite = false.obs;

  /// La OBRA terminó de publicarse (marcado a mano en el Detalle). Es un eje
  /// aparte de si el usuario está al día — ver WatchState en history.dart.
  final RxBool isSeriesFinished = false.obs;

  /// Contenido por capítulos/episodios. Se decide por el ÍTEM y no por el tipo
  /// de extensión: hay extensiones de vídeo que traen películas (un solo
  /// "episodio") y extensiones mixtas con las dos cosas a la vez, así que el
  /// tipo no alcanza para saberlo. Los botones de seguimiento solo tienen
  /// sentido acá: en una película no hay nada que "completar".
  bool get isSerialized {
    // 1) Si la extensión informa estado de publicación, es una obra por
    //    entregas y punto. Verificado en prism-plus: ContentStatus es un
    //    conjunto cerrado —ongoing, completed, upcoming, hiatus— y las
    //    extensiones de películas o vídeos sueltos (FuegoCine, VeoHentai,
    //    XVideos) directamente NO lo informan.
    //
    //    Esto importa porque contar episodios NO alcanza: un anime recién
    //    estrenado tiene UN episodio publicado y seguía sin botón, igual que
    //    una serie ya finalizada de un solo capítulo — y en los dos casos el
    //    usuario tiene que poder marcarla para filtrarla después.
    final estado = detail?.status;
    if (estado != null && estado.isNotEmpty) return true;

    // 2) Sin estado: se cuenta. Más de un capítulo/episodio es serializado.
    final grupos = detail?.episodes;
    if (grupos == null || grupos.isEmpty) return false;
    final total = grupos.fold<int>(0, (n, g) => n + (g.urls?.length ?? 0));
    return total > 1;
  }

  final Rx<ExtensionDetail?> data = Rx(null);
  final Rx<History?> history = Rx(null);
  final Rx<Favorite?> favorite = Rx(null);
  final RxString error = ''.obs;

  /// Mira el historial de este título mientras la ficha está abierta.
  ///
  /// El reproductor y el lector guardan el progreso al cerrarse, o sea DESPUÉS
  /// de que la ficha ya leyó el historial una única vez al abrirse. Por eso
  /// había que salir de la ficha y volver a entrar para que el botón de
  /// "continuar" dijera dónde habías quedado. Con esto la ficha se entera sola.
  ///
  /// Solo dispara una relectura: no toca nada más y no reemplaza a getHistory()
  /// —lo llama—, así que el camino de siempre queda igual.
  StreamSubscription<void>? _miradaAlHistorial;

  /// Si lo que falló fue la conexión y no la extensión.
  ///
  /// El texto ya sale traducido de friendlyError, pero para la pantalla hace
  /// falta saber TAMBIÉN de qué tipo de fallo se trata: un corte de internet
  /// se arregla solo con reintentar y merece decirlo así, mientras que un
  /// error propio de la fuente probablemente siga igual por más que insistas.
  final RxBool errorEsDeConexion = false.obs;

  final RxBool isLoading = true.obs;

  /// La ficha está tardando más de lo normal.
  ///
  /// Con el sitio de una extensión caído, la pantalla se quedaba con la rueda
  /// girando para siempre y sin decir nada — desde afuera eso se lee como que
  /// la app se colgó. Medido en LaMovie el 2026-08-06: su propio sitio tardaba
  /// entre 21 y 27 segundos, y abierto en un navegador directamente no cargaba.
  ///
  /// Doce segundos, el mismo criterio que en la fila de la búsqueda: por encima
  /// de lo que tarda una extensión sana y por debajo del límite del puente de
  /// red, así el aviso llega ANTES de que el pedido muera.
  ///
  /// Es SOLO un aviso: no cancela nada. Si la ficha llega después, entra igual.
  final RxBool tardaDemasiado = false.obs;

  /// Lo que se ve es lo guardado de antes: no se pudo traer nada nuevo.
  ///
  /// Al entrar a una ficha ya vista se muestra lo de la caché y se refresca por
  /// detrás. Ese refresco fallaba en silencio, así que con el sitio caído se
  /// veía una ficha que podía estar vieja —capítulos de menos— sin ninguna
  /// señal. Ahora se dice.
  final RxBool mostrandoCache = false.obs;

  Timer? _relojDeLaFicha;

  void _mirarSiTarda() {
    _relojDeLaFicha?.cancel();
    tardaDemasiado.value = false;
    _relojDeLaFicha = Timer(const Duration(seconds: 12), () {
      if (isLoading.value) tardaDemasiado.value = true;
    });
  }

  void _dejarDeMirar() {
    _relojDeLaFicha?.cancel();
    _relojDeLaFicha = null;
    tardaDemasiado.value = false;
  }
  final RxInt selectEpGroup = 0.obs;
  final RxString aniListID = ''.obs;
  final Rx<TMDBDetail?> tmdb = Rx(null);
  final Rx<ExtensionService?> runtime = Rx(null);
  ExtensionType get type {
    final ext = runtime.value?.extension;
    if (ext == null) return ExtensionType.bangumi;
    return ExtensionUtils.resolveType(ext, data.value);
  }

  Extension? get extension => runtime.value?.extension;

  ExtensionDetail? get detail => data.value;
  set detail(ExtensionDetail? value) => data.value = value;

  TMDBDetail? get tmdbDetail => tmdb.value;
  set tmdbDetail(TMDBDetail? value) => tmdb.value = value;

  /// La portada que la tarjeta tocada ya estaba mostrando, si la hay.
  ///
  /// Se lee una sola vez, al construirse: es un dato de la apertura y no tiene
  /// por qué cambiar mientras la ficha está abierta.
  late final _adelantada = PortadaAdelantada.de(package, url);

  /// Si esta extensión publica fotogramas apaisados en vez de pósters.
  ///
  /// El hueco del póster de la ficha es vertical de toda la vida, y para un
  /// manga o un sitio de anime está bien. Pero los sitios de vídeo publican
  /// fotogramas 16:9, y metidos en una caja vertical hay que recortarles los
  /// costados — justo donde suele estar lo que se quiere ver. Sabiendo qué
  /// publica cada uno, la caja toma la forma que corresponde.
  ///
  /// Lectura siempre en falso: un libro lleva tapa vertical aunque alguna
  /// portada suelta venga apaisada. Es el mismo criterio que usa la grilla de
  /// las extensiones (ver FormaPortada).
  /// Ancho ÷ alto que tiene que tener el hueco de la portada.
  ///
  /// La proporción EXACTA de las portadas de este sitio, no una de dos formas
  /// fijas: una portada un poco más angosta que la caja dejaba franjas a los
  /// costados, y ahí no hay relleno que quede bien. Midiendo la de verdad, la
  /// imagen llena el hueco y no sobra nada.
  /// La proporción REAL de la portada de ESTA ficha, cuando ya se pudo medir.
  ///
  /// Ver [anotarPortada].
  final RxnDouble proporcionMedida = RxnDouble();

  /// Anota el tamaño real de la portada que se está mostrando.
  ///
  /// [FormaPortada] decide por CATÁLOGO y tarda cuatro portadas en decidirse:
  /// hasta entonces contesta la vertical de siempre. En una extensión de vídeo
  /// eso significa abrir la ficha con la caja vertical y el fotograma 16:9
  /// metido chico en el medio, con relleno borroso alrededor — y ahí se queda,
  /// porque la ficha no se entera de cuándo el catálogo se decide. Lo mismo
  /// pasa con un título suelto que traiga otra forma que el resto del sitio.
  ///
  /// Acá hay UNA portada, así que se le puede tomar la medida y darle a la
  /// caja su forma exacta.
  void anotarPortada(int ancho, int alto) {
    if (ancho <= 0 || alto <= 0) return;
    // El mismo recorte que usa FormaPortada: una imagen rarísima —un banner
    // larguísimo, una tira finita— no puede deformar la cabecera entera.
    final nueva = (ancho / alto).clamp(0.45, 2.2);
    if (proporcionMedida.value == nueva) return;
    proporcionMedida.value = nueva;
  }

  double get portadaProporcion {
    final ext = extension;
    if (ext == null) return FormaPortada.proporcionVertical;
    final esDeLectura = !ExtensionUtils.videoTypes.contains(ext.type);
    // Solo en vídeo. En lectura la tapa es vertical por convención aunque una
    // portada suelta venga apaisada, y ese criterio ya está probado; en vídeo
    // es justo donde la forma del catálogo falla.
    if (!esDeLectura) {
      final medida = proporcionMedida.value;
      if (medida != null) return medida;
    }
    return FormaPortada.paraDibujar(package, esDeLectura: esDeLectura);
  }

  bool get portadaApaisada => portadaProporcion > 1;

  /// La portada que traía la tarjeta, tal cual. Null si se llegó sin pasar por
  /// una (el historial, un enlace compartido, "Ver detalle" desde el
  /// reproductor).
  String? get portadaPrevia => _adelantada?.url;
  Map<String, String>? get portadaPreviaHeaders => _adelantada?.cabeceras;

  /// La portada a dibujar AHORA.
  ///
  /// La de la extensión cuando ya llegó; mientras tanto, la que traía la
  /// tarjeta. Así la ficha nunca abre con un hueco: en las extensiones que
  /// devuelven la misma imagen no cambia nada, y en las que devuelven otra se
  /// ve la de la tarjeta y se reemplaza sola cuando llega la buena.
  String? get portada {
    final deLaExtension = detail?.cover;
    if (deLaExtension != null && deLaExtension.isNotEmpty) return deLaExtension;
    return _adelantada?.url;
  }

  /// Las cabeceras que le corresponden a [portada].
  ///
  /// Van atadas a la imagen y no sueltas: varios sitios devuelven 403 sin el
  /// Referer correcto (medido en HQPorner), y la portada de la tarjeta puede
  /// venir de un servidor distinto al de la ficha.
  Map<String, String>? get portadaHeaders {
    final deLaExtension = detail?.cover;
    if (deLaExtension != null && deLaExtension.isNotEmpty) {
      return detail?.headers;
    }
    return _adelantada?.cabeceras;
  }

  String? get backgorund {
    String? bg;
    if (tmdbDetail != null && tmdbDetail!.backdrop != null) {
      bg = TmdbApi.getImageUrl(tmdbDetail!.backdrop!) ?? '';
    } else {
      bg = portada;
    }
    return bg;
  }

  PrismHubDetail? _prismDetail;

  int _tmdbID = -1;

  final _flyoutController = fluent.FlyoutController();

  @override
  void onInit() {
    onRefresh();
    Get.find<MainController>().setAcitons([
      fluent.FlyoutTarget(
        controller: _flyoutController,
        child: fluent.IconButton(
          icon: const Icon(fluent.FluentIcons.more),
          onPressed: () {
            _flyoutController.showFlyout(builder: (context) {
              return SizedBox(
                width: 300,
                child: Card(
                    child: fluent.Column(
                  mainAxisSize: fluent.MainAxisSize.min,
                  children: [
                    if (detail != null)
                      fluent.ListTile(
                        title: Text(
                          'detail.modify-tmdb-binding'.i18n,
                        ),
                        onPressed: () {
                          router.pop();
                          modifyTMDBBinding();
                        },
                      )
                  ],
                )),
              );
            });
          },
        ),
      )
    ]);

    // Se engancha ANTES de la primera carga: así también cubre el caso de
    // volver del reproductor mientras la ficha todavía se estaba armando.
    _miradaAlHistorial =
        DatabaseService.watchHistoryByPackageAndUrl(package, url).listen((_) {
      // Sin la ficha cargada no hay con qué comparar el episodio guardado
      // (getHistory usa detail!.episodes) — cuando termine de cargar, la lee
      // igual por el camino de siempre.
      if (detail == null) return;
      getHistory();
    });

    super.onInit();
  }

  onRefresh() async {
    // Deshabilitada (con el toggle apagado en Extensiones) se trata igual
    // que no instalada acá: runtime queda null, así que getDetail() de abajo
    // toma el mismo camino de error que ya existía para "no instalada" — sin
    // esto, una extensión desactivada seguía sirviendo el detalle entero
    // pese al toggle.
    runtime.value = ExtensionUtils.isEnabled(package)
        ? ExtensionUtils.runtimes[package]
        : null;
    await refreshFavorite();
    await refreshSeriesFinished();
    try {
      _prismDetail = await DatabaseService.getPrismHubDetail(package, url);
      _tmdbID = _prismDetail?.tmdbID ?? -1;
      aniListID.value = _prismDetail?.aniListID ?? "";
      await getDetail();
      await getTMDBDetail();
      await getHistory();
      isLoading.value = false;
      _dejarDeMirar();
    } catch (e) {
      error.value = friendlyError(e);
      errorEsDeConexion.value = isConnectionError(e);
      rethrow;
    }
  }

  /// Vuelve a pedir la ficha porque el usuario lo pidió.
  ///
  /// ── Por qué no alcanza con onRefresh() ──────────────────────────────────
  ///
  /// La ficha se guarda en una caché de sesión para que volver al mismo título
  /// sea instantáneo. Llamando a onRefresh() a secas, getDetail() encuentra esa
  /// copia y la devuelve: el gesto no traería nada nuevo y el usuario vería
  /// exactamente lo mismo, sin entender por qué.
  ///
  /// Acá se tira la entrada de ESTE título —no la caché entera, que las demás
  /// fichas siguen siendo válidas— y recién ahí se pide.
  ///
  /// El comentario de _sessionCache decía desde hacía rato que se invalidaba
  /// «al hacer pull-to-refresh manual». Ese gesto no existía; ahora sí.
  ///
  /// No toca `isLoading`: refrescando ya hay contenido en pantalla y vaciarlo
  /// para volver a llenarlo se ve como que la ficha se rompió y volvió. La
  /// señal de que algo está pasando la da el propio gesto —la rueda de arriba
  /// en el teléfono, el botón girando en el escritorio—.
  Future<void> refrescarAMano() async {
    _sessionCache.remove('$package:$url');
    error.value = '';
    try {
      await onRefresh();
    } catch (_) {
      // onRefresh ya dejó el mensaje puesto. Propagarlo desde acá lo dejaría
      // como un error sin nadie que lo atienda.
    }
  }

  /// Vuelve a pedir la ficha después de un fallo.
  ///
  /// Limpia el mensaje y vuelve a mostrar el indicador ANTES de pedir: sin
  /// eso, la pantalla se queda con el error viejo puesto todo el rato que dure
  /// el intento nuevo y no se ve que esté pasando algo — se siente como que el
  /// botón no hizo nada.
  Future<void> reintentar() async {
    error.value = '';
    isLoading.value = true;
    _mirarSiTarda();
    try {
      await onRefresh();
    } catch (_) {
      // onRefresh ya dejó el mensaje puesto; acá solo hace falta no propagar,
      // porque nadie más lo va a atender y quedaría como un error suelto.
    }
  }

  // 修改 tmdb 绑定
  modifyTMDBBinding() async {
    // 判断是否有 key
    if (PrismHubStorage.getSetting(SettingKey.tmdbKey) == "") {
      showPlatformSnackbar(
        context: currentContext,
        content: 'detail.tmdb-key-missing'.i18n,
        severity: fluent.InfoBarSeverity.error,
      );
      return;
    }

    dynamic data;
    if (Platform.isAndroid) {
      data = await Get.to(TMDBBinding(
        title: detail!.title,
      ));
    } else {
      data = await fluent.showDialog(
        context: currentContext,
        builder: (context) => TMDBBinding(title: detail!.title),
      );
    }
    if (data != null) {
      await getRemoteTMDBDetail(
        id: data['id'],
        mediaType: data['media_type'],
      );
    }
  }

  getDetail() async {
    // Con la extensión deshabilitada/desinstalada (runtime null) no hay que
    // usar el detalle cacheado localmente tampoco — sin este chequeo, el
    // capítulo/detalle entero se seguía viendo desde la caché de Isar pese
    // al toggle apagado, aunque nunca se pudiera reproducir nada real.
    // getRemoteDeatil() ya sabe mostrar el error correcto (missing/disabled)
    // cuando runtime.value es null.
    if (runtime.value != null && _prismDetail != null) {
      detail = ExtensionDetail.fromJson(
        Map<String, dynamic>.from(
          jsonDecode(_prismDetail!.data),
        ),
      );
      getRemoteDeatil();
    } else {
      await getRemoteDeatil();
    }
  }

  getRemoteDeatil() async {
    // Se pide de nuevo: si esta vez sí llega, el aviso de "esto es lo guardado"
    // no tiene que quedar puesto.
    mostrandoCache.value = false;
    final cacheKey = '$package:$url';
    // Si ya tenemos el dato en memoria (misma sesión) lo usamos directo y
    // actualizamos en background sin bloquear la UI — pero NO si la
    // extensión está deshabilitada/desinstalada ahora: sin este chequeo,
    // desactivarla a mitad de sesión no bloqueaba nada si el detalle ya
    // se había pedido antes en esa misma sesión.
    if (runtime.value != null && _sessionCache.containsKey(cacheKey)) {
      detail = _sessionCache[cacheKey];
      _refreshDetailInBackground(cacheKey);
      return;
    }
    try {
      detail = await runtime.value!.detail(url);
      _putSessionCache(cacheKey, detail!);
      // La portada que acaba de cargar se aprovecha para la tarjeta del inicio
      // y del historial, si les faltaba. Ver PortadasPerdidas.desdeLaFicha.
      unawaited(PortadasPerdidas.desdeLaFicha(
        package: package,
        url: url,
        cover: detail!.cover,
      ));
      await DatabaseService.putPrismHubDetail(
        package,
        url,
        detail!,
        tmdbID: _tmdbID,
        anilistID: aniListID.value,
      );
    } catch (e) {
      // 弹出错误信息
      if (runtime.value == null) {
        final content = FlutterI18n.translate(
          currentContext,
          ExtensionUtils.runtimes.containsKey(package)
              ? 'common.extension-disabled'
              : 'common.extension-missing',
          translationParams: {'package': ExtensionUtils.nombreDe(package)},
        );
        showPlatformSnackbar(
          context: currentContext,
          content: content,
          severity: fluent.InfoBarSeverity.error,
        );
        throw content;
      } else {
        // friendlyError(e) en vez del texto crudo de la excepción — sin
        // conexión, esto mostraba literalmente "DioException [connection
        // error]: ..." en vez de un aviso legible (reportado en vivo).
        showPlatformSnackbar(
          context: currentContext,
          title: 'detail.get-lastest-data-error'.i18n,
          content: friendlyError(e),
          severity: fluent.InfoBarSeverity.error,
        );
      }
      rethrow;
    }
  }

  // Actualiza el detalle en background (sin spinner) cuando viene de caché.
  Future<void> _refreshDetailInBackground(String cacheKey) async {
    try {
      final fresh = await runtime.value!.detail(url);
      _putSessionCache(cacheKey, fresh);
      detail = fresh;
      // También acá: es el camino por el que se entra cuando la ficha ya
      // estaba en caché, que es justamente el caso de un título que se abrió
      // antes y quedó sin portada en la tarjeta.
      unawaited(PortadasPerdidas.desdeLaFicha(
        package: package,
        url: url,
        cover: fresh.cover,
      ));
      await DatabaseService.putPrismHubDetail(
        package,
        url,
        fresh,
        tmdbID: _tmdbID,
        anilistID: aniListID.value,
      );
    } catch (_) {
      // Se sigue con lo de la caché, que es lo correcto: mejor la ficha de
      // antes que una pantalla vacía. Pero YA NO en silencio — antes no había
      // forma de saber que lo que se estaba viendo podía estar viejo (con
      // capítulos de menos, por ejemplo) porque el sitio no contestó.
      if (mostrandoCache.value) return;
      mostrandoCache.value = true;
      // Con el aviso de siempre y no un cartel propio: así sale igual en
      // celular y en escritorio sin tocar los dos diseños de la ficha, que es
      // justo donde se rompen las cosas.
      if (!currentContext.mounted) return;
      showPlatformSnackbar(
        context: currentContext,
        content: 'common.detalle-desde-cache'.i18n,
        severity: fluent.InfoBarSeverity.warning,
      );
    }
  }

  getTMDBDetail() async {
    tmdbDetail = await DatabaseService.getTMDBDetail(_tmdbID);
    if (detail == null) {
      return;
    }
    if (tmdbDetail == null) {
      getRemoteTMDBDetail();
      return;
    }
    getRemoteTMDBDetail(id: tmdbDetail!.id, mediaType: tmdbDetail!.mediaType);
  }

  getRemoteTMDBDetail({int? id, String? mediaType}) async {
    if (id != null && mediaType != null) {
      tmdbDetail = await TmdbApi.getDetail(id, mediaType);
      if (tmdbDetail == null) {
        return;
      }
    } else {
      tmdbDetail = await TmdbApi.getDetailBySearch(detail!.title);
      if (tmdbDetail == null) {
        return;
      }
    }
    _tmdbID = await DatabaseService.putTMDBDetail(
      tmdbDetail!.id,
      tmdbDetail!,
      tmdbDetail!.mediaType,
    );
    // 更新 id
    await DatabaseService.putPrismHubDetail(
      package,
      url,
      detail!,
      tmdbID: _tmdbID,
      anilistID: aniListID.value,
    );
  }

  saveAniListIds() async {
    await DatabaseService.putPrismHubDetail(
      package,
      url,
      detail!,
      anilistID: aniListID.value,
    );
  }

  getHistory() async {
    // 获取历史记录
    final history_ = await DatabaseService.getHistoryByPackageAndUrl(
      package,
      url,
    );
    if (history_ != null) {
      // 并且剧集的数量大于历史记录的剧集列表数量 防止历史记录超出剧集列表数量
      if (history_.episodeGroupId < detail!.episodes!.length) {
        history.value = history_;
        selectEpGroup.value = history_.episodeGroupId;
      }
    }
  }

  refreshFavorite() async {
    final f = await DatabaseService.getFavorite(package: package, url: url);
    favorite.value = f;
    isFavorite.value = f != null;
  }

  Future<void> refreshSeriesFinished() async {
    final h = await DatabaseService.getHistoryByPackageAndUrl(package, url);
    isSeriesFinished.value = h?.seriesFinished ?? false;
  }

  Future<void> toggleSeriesFinished(BuildContext context) async {
    if (detail == null) return;
    final marcar = !isSeriesFinished.value;
    // Mismo diálogo de zona que Favoritos, y por el mismo motivo: si el ítem
    // se guarda con la zona equivocada aparece en el Historial que no
    // corresponde. Solo se pregunta al MARCAR; desmarcar no crea nada.
    final nsfw = marcar ? await resolveIsNsfw(context, opening: false) : false;
    if (nsfw == null) return;
    try {
      await DatabaseService.setSeriesFinished(
        package: package,
        url: url,
        finished: marcar,
        type: type,
        title: detail!.title,
        cover: detail!.cover,
        isNsfw: nsfw,
      );
    } catch (e) {
      showPlatformSnackbar(
        context: currentContext,
        content: e.toString().split('\n')[0],
        severity: fluent.InfoBarSeverity.error,
      );
      rethrow;
    }
    await refreshSeriesFinished();
    HomePageController.refreshAll();
  }

  // Se llama al quitar favorito o borrar historial (acá mismo, o desde
  // HistoryPage vía el tag de este controller) — "olvida" la respuesta de
  // +18 que este título tenía guardada, para que la próxima vez que se
  // toque favorito o un capítulo se vuelva a preguntar en vez de arrastrar
  // una decisión vieja de contenido que el usuario ya sacó de encima.
  void forgetNsfwDecision() {
    history.value = null;
    favorite.value = null;
    _nsfwAnswer = null;
  }

  toggleFavorite(BuildContext context) async {
    if (detail == null) {
      return;
    }
    // Solo pregunta "¿es +18?" al CREAR un favorito nuevo — si ya estaba
    // favorito, esta llamada lo borra, no hace falta preguntar nada.
    final wasFavorite = isFavorite.value;
    final nsfw =
        wasFavorite ? false : await resolveIsNsfw(context, opening: false);
    // Canceló el diálogo (tocó afuera) — no favoritear nada, como si nunca
    // hubiera tocado el botón.
    if (nsfw == null) return;
    try {
      await DatabaseService.toggleFavorite(
        package: package,
        url: url,
        cover: detail!.cover,
        name: detail!.title,
        isNsfw: nsfw,
      );
    } catch (e) {
      showPlatformSnackbar(
        context: currentContext,
        content: e.toString().split('\n')[0],
        severity: fluent.InfoBarSeverity.error,
      );
      rethrow;
    }
    if (wasFavorite) forgetNsfwDecision();
    await refreshFavorite();
    HomePageController.refreshAll();
  }

  goWatch(BuildContext context, List<ExtensionEpisode> urls, int index,
      int selectEpGroup,
      {bool autoResume = false}) async {
    if (runtime.value == null) {
      showPlatformSnackbar(
        context: currentContext,
        content: FlutterI18n.translate(
          currentContext,
          'common.extension-missing',
          translationParams: {'package': ExtensionUtils.nombreDe(package)},
        ),
        severity: fluent.InfoBarSeverity.error,
      );
      return;
    }

    // Se resuelve ANTES de navegar: si hace falta preguntar, mejor que el
    // diálogo aparezca acá (con el detalle todavía en pantalla) que a mitad
    // de la transición hacia el reproductor/lector.
    final nsfwResolved = await resolveIsNsfw(context);
    // Canceló el diálogo (tocó afuera) — no abrir el reproductor/lector,
    // como si nunca hubiera tocado el capítulo.
    if (nsfwResolved == null) return;

    if (type == ExtensionType.bangumi) {
      final player = PrismHubStorage.getSetting(SettingKey.videoPlayer);

      if (player != 'built-in') {
        showPlatformSnackbar(
          context: currentContext,
          content: FlutterI18n.translate(
            currentContext,
            'external-player-launching',
            translationParams: {
              'player': player,
            },
          ),
        );
        late ExtensionBangumiWatch watchData;
        try {
          watchData = await runtime.value!.watch(urls[index].url,
              typeHint: ExtensionType.bangumi) as ExtensionBangumiWatch;
        } catch (e) {
          showPlatformSnackbar(
            context: currentContext,
            content: e.toString().split('\n')[0],
            severity: fluent.InfoBarSeverity.error,
          );
          return;
        }
        try {
          if (GetPlatform.isMobile) {
            await launchMobileExternalPlayer(watchData.url, player);
            return;
          }
          await launchDesktopExternalPlayer(watchData.url, player,
              watchData.headers ?? {}, watchData.subtitles ?? []);
          return;
        } catch (e) {
          showPlatformSnackbar(
            context: currentContext,
            content: e.toString().split('\n')[0],
            severity: fluent.InfoBarSeverity.error,
          );
        }
      }
    }

    Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 600),
        pageBuilder: ((context, animation, secondaryAnimation) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(
                parent: animation,
                curve: Curves.ease,
              ),
            ),
            // Sin este diferido, WatchPage (Get.put del controller + Player()
            // nativo de media_kit) se construía en el mismo frame en que
            // arranca el push, compitiendo por CPU con la transición de
            // 600ms recién empezada — se sentía como un tirón al abrir.
            // DeferredRouteContent espera a que la animación termine antes
            // de montar el contenido real.
            child: DeferredRouteContent(
              pushAnimation: animation,
              placeholder: const Scaffold(
                backgroundColor: Colors.black,
                body: Center(child: ProgressRing()),
              ),
              builder: (context) => WatchPage(
                cover: detail!.cover,
                playList: urls,
                package: package,
                playerIndex: index,
                title: detail!.title,
                episodeGroupId: selectEpGroup,
                detailUrl: url,
                anilistID: aniListID.value,
                typeOverride: type,
                cameFromDetail: true,
                autoResume: autoResume,
                isNsfw: nsfwResolved,
              ),
            ),
          );
        }),
      ),
    );
  }

  @override
  void onClose() {
    _relojDeLaFicha?.cancel();
    _miradaAlHistorial?.cancel();
    scrollController.dispose();
    Get.find<MainController>().setAcitons([]);
    super.onClose();
  }
}
