import 'dart:io';

import 'package:dio/dio.dart';
import 'package:extended_image/extended_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/platform_tv.dart';
import 'package:prismhub/utils/request.dart';
import 'package:prismhub/views/widgets/home/esqueleto.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/messenger.dart';
import 'package:prismhub/views/widgets/platform_widget.dart';

class CacheNetWorkImagePic extends StatefulWidget {
  const CacheNetWorkImagePic(
    this.url, {
    super.key,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.fallback,
    this.headers,
    this.placeholder,
    this.canFullScreen = false,
    this.mode = ExtendedImageMode.none,
    this.initGestureConfigHandler,
    this.alignment = Alignment.center,
    this.filterQuality = FilterQuality.low,
    this.cacheWidth,
    this.cacheHeight,
    this.onTamanoReal,
  });
  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget? fallback;
  final Map<String, String>? headers;
  final bool canFullScreen;
  final Widget? placeholder;
  final ExtendedImageMode mode;
  final InitGestureConfigHandler? initGestureConfigHandler;
  final Alignment alignment;
  final FilterQuality filterQuality;
  final int? cacheWidth;
  final int? cacheHeight;

  /// El tamaño en píxeles de la imagen que llegó, apenas se sabe.
  ///
  /// Sirve para averiguar la FORMA de la imagen sin pedir nada de más: la
  /// proporción entre ancho y alto se conserva aunque se decodifique a menor
  /// tamaño (ver cacheWidth), así que alcanza para distinguir un póster
  /// vertical de un fotograma apaisado.
  final void Function(int ancho, int alto)? onTamanoReal;

  /// Vacía lo que el widget recuerda entre pantallas: qué URLs fallaron hace
  /// poco y cuáles ya se habían visto bien.
  ///
  /// Se llama cuando el sistema avisa que se está quedando sin memoria (ver
  /// `alivio_de_memoria.dart`). Perderlos no rompe nada: son atajos para no
  /// reintentar de más y para no parpadear al remontar, no información que
  /// haga falta. Lo peor que puede pasar es que una portada que ya se vio
  /// vuelva a mostrar el bloque brillando mientras llega — que en ese momento
  /// además es la verdad, porque Flutter también acaba de soltar sus píxeles.
  static void olvidarLoRecordado() {
    _CacheNetWorkImagePicState._fallosRecientes.clear();
    _CacheNetWorkImagePicState._yaCargaron.clear();
  }

  @override
  State<CacheNetWorkImagePic> createState() => _CacheNetWorkImagePicState();
}

class _CacheNetWorkImagePicState extends State<CacheNetWorkImagePic> {
  // URLs que ya fallaron alguna vez, compartido entre TODAS las instancias
  // del widget (no por-instancia) — cuando navegás a otra sección y volvés
  // (o el widget se remonta por cualquier motivo), Flutter crea un
  // _CacheNetWorkImagePicState nuevo desde cero: un flag de instancia no
  // alcanza, porque el nuevo widget no sabe que esa URL ya había fallado y
  // vuelve a intentar la red, pasando un frame por "loading" (en blanco)
  // antes de volver a "failed" — el mismo parpadeo, ahora disparado por
  // cambiar de pestaña/página en vez de por un resize.
  // Se recuerda CUANDO fallo, no solo QUE fallo.
  //
  // Antes era un conjunto sin caducidad: la primera vez que una portada
  // fallaba quedaba anotada para toda la sesion y ya no se reintentaba nunca.
  // Pero el motivo mas comun de fallo aca es transitorio — decenas de tarjetas
  // pidiendo su imagen a la vez, y alguna que no llega a tiempo (ver el
  // comentario de `retries` mas abajo). El resultado era una tarjeta con el
  // logo de relleno de forma permanente, mientras la MISMA imagen cargaba sin
  // problema al abrir el detalle segundos despues, ya sin competencia.
  // Reportado en vivo en dos extensiones distintas, que fue lo que dejo claro
  // que el problema estaba aca y no en ninguna de ellas.
  //
  // Con caducidad se conserva lo que este registro venia a resolver —no
  // parpadear al remontar la misma tarjeta— pero un fallo pasajero deja de ser
  // definitivo: al volver a construirse pasada la ventana, se reintenta.
  static final Map<String, DateTime> _fallosRecientes = <String, DateTime>{};

  // Corto a proposito: lo suficiente para cubrir un resize o un cambio de
  // pestana (que es cuando molestaba el parpadeo), y no tanto como para que
  // una portada quede ausente un rato largo.
  static const Duration _ventanaDeFallo = Duration(seconds: 20);

  /// Las que YA cargaron bien alguna vez en esta sesión.
  ///
  /// ── El agujero que tapa ─────────────────────────────────────────────────
  ///
  /// El registro de fallos de arriba corta por lo sano: si una portada falló
  /// hace menos de veinte segundos, la tarjeta muestra el arte de respaldo sin
  /// siquiera intentar cargarla. Eso está bien para una portada que nunca
  /// cargó —no tiene sentido pelearse con un sitio caído— pero es un desastre
  /// para una que se estaba viendo perfecta hace un segundo.
  ///
  /// Y en Android pasa seguido. Al abrir una ficha, el sistema le pide memoria
  /// a la app y Flutter suelta las imágenes decodificadas; al volver, las
  /// portadas del Inicio se piden todas de nuevo a la vez, y bajo esa
  /// contención alguna se cae. Con eso queda anotada y su tarjeta se va al
  /// arte de respaldo por veinte segundos, hasta que vence la ventana y
  /// reaparece: eso es el parpadeo. En escritorio no pasa porque ahí nadie le
  /// pide memoria a la app, así que las portadas nunca se vuelven a pedir.
  ///
  /// Con esta lista, una portada que ya se vio no se da por caída nunca: si
  /// hay que traerla otra vez se muestra el bloque brillando mientras llega,
  /// que es la verdad —está cargando— en vez de mentir con «no se pudo».
  static final Set<String> _yaCargaron = <String>{};

  /// Tope de la lista de arriba, para que no crezca sin fin en una sesión
  /// larga. Al llegar se vacía entera: perder la memoria de qué cargó bien no
  /// rompe nada, solo devuelve el comportamiento de antes hasta que se vuelvan
  /// a ver.
  static const int _topeYaCargaron = 3000;

  // Incluye los headers en la clave — si la primera vez falló sin headers
  // (ej. un sitio que exige Referer y no se lo dimos) y después se reintenta
  // CON los headers correctos, es un intento distinto y merece una
  // oportunidad real, no quedar bloqueado por el fallo anterior.
  String get _failureKey => '${widget.url}|${widget.headers ?? ''}';

  // True mientras se reintenta una portada que ya habia fallado. Sirve para no
  // vaciar la tarjeta durante ese reintento: si no, al cumplirse la ventana
  // CUALQUIER reconstruccion —pasar el mouse por encima hace setState— pasaba
  // por el estado "cargando", que devuelve una caja vacia, y la imagen
  // desaparecia a la vista. Mostrando el arte de respaldo hasta que el
  // reintento termine, la tarjeta nunca queda en blanco: o sigue igual, o
  // aparece la portada real.
  bool _reintentando = false;

  /// Si ya se avisó del tamaño de esta imagen. Ver el uso en loadStateChanged.
  bool _tamanoAvisado = false;

  bool get _failed {
    // Una que ya se vio bien no se da por caída: se reintenta y mientras tanto
    // se muestra el bloque brillando. Ver _yaCargaron.
    if (_yaCargaron.contains(_failureKey)) return false;
    final cuando = _fallosRecientes[_failureKey];
    if (cuando == null) return false;
    if (DateTime.now().difference(cuando) < _ventanaDeFallo) return true;
    // Se cumplio la ventana: se olvida y se le da otra oportunidad.
    _fallosRecientes.remove(_failureKey);
    _reintentando = true;
    return false;
  }

  void _markFailed() {
    final primeraVez = !_fallosRecientes.containsKey(_failureKey);
    _fallosRecientes[_failureKey] = DateTime.now();
    if (primeraVez && mounted) setState(() {});
  }

  // Cargo bien: se borra cualquier anotacion previa, para que un fallo viejo no
  // siga contando en contra de una URL que evidentemente ya funciona.
  void _markLoaded() {
    _fallosRecientes.remove(_failureKey);
    if (_yaCargaron.length >= _topeYaCargaron) _yaCargaron.clear();
    _yaCargaron.add(_failureKey);
    _reintentando = false;
  }

  // Branded placeholder for a cover that failed to load — the source site
  // may be down or blocking, not necessarily an app bug. assets/carddefaultoffline.png
  // is the app's dedicated "offline/no image" art, so it reads as an
  // intentional state instead of a bare error icon.
  Widget _errorBuild() {
    if (widget.fallback != null) {
      return widget.fallback!;
    }
    // Full-bleed (BoxFit.cover, sin padding ni caja negra alrededor) —
    // mismo criterio que el fallback de tarjeta oculta en Home
    // (home_media_card.dart hiddenCover): antes tenía un margen de 28 +
    // BoxFit.contain sobre fondo negro, así que se veía como un logo
    // chico flotando en una caja oscura en vez de una portada de verdad.
    // OJO: `fit` solo pinta los píxeles DENTRO de la caja que Image ya
    // decidió — si el padre da constraints sueltas (loose, con mínimo 0 —
    // ej. un Stack normal), Image elige su PROPIA caja preservando el
    // aspect ratio (como si fuera contain) aunque el fit diga "cover". Por
    // eso se fuerza width/height infinitos — pero SOLO cuando el alto está
    // acotado: en el lector (alto sin acotar a propósito) forzarlo rompe
    // el layout (crashea el hit-test, app se cuelga), así que ahí se deja
    // sin forzar y cae al tamaño por aspect ratio, que es seguro.
    return LayoutBuilder(
      builder: (context, constraints) {
        final bounded =
            constraints.maxWidth.isFinite && constraints.maxHeight.isFinite;
        return Image.asset(
          'assets/carddefaultoffline.png',
          fit: BoxFit.cover,
          alignment: Alignment.center,
          width: bounded ? double.infinity : null,
          height: bounded ? double.infinity : null,
        );
      },
    );
  }

  /// El tope de ancho al que conviene decodificar en ESTE aparato, o null si
  /// no hay que ponerle ninguno.
  ///
  /// ── Por qué hace falta ─────────────────────────────────────────────────
  ///
  /// Una imagen ocupa en memoria cuatro bytes por píxel DECODIFICADO, sin
  /// importar lo que pese el archivo. Sin tope, una portada de 2000×3000 son
  /// 24 MB aunque se muestre en una tarjeta de 150 puntos.
  ///
  /// Casi todas las pantallas ya pasan su `cacheWidth` a mano y hacen bien la
  /// cuenta, pero quedaban dieciocho llamadas sin ninguno — y varias son a
  /// pantalla completa (el fondo de una ficha, la portada del televisor). Ahí
  /// es donde más duele: en un panel 4K son más de treinta megas por imagen.
  ///
  /// ── Y por qué solo en televisor ────────────────────────────────────────
  ///
  /// En el nivel `alto` (escritorio, teléfono y tablet) devuelve null: ahí
  /// nada cambia, ni una llamada. Poner un tope general sería tocar de
  /// refilón cosas que hoy funcionan bien —el lector de cómic, que se puede
  /// ampliar con los dedos y necesita todos los píxeles— sin ninguna medición
  /// que lo pida.
  ///
  /// En un televisor esa preocupación no existe: no hay pellizco para ampliar,
  /// y la pantalla no da más de lo que el tope permite igual.
  static int? get _topeDelPerfil => PerfilDeAparato.nivel.elegir<int?>(
        alto: null,
        medio: 1080,
        bajo: 720,
      );

  int? _topeDeAncho(BuildContext context, BoxConstraints? caja) {
    final tope = _topeDelPerfil;
    if (tope == null) return null;
    // El ancho de verdad que va a ocupar, en puntos. Se prueba primero lo que
    // le dio el padre y después lo que pidió quien la usa; si ninguno de los
    // dos es un número finito (pasa con `double.infinity`, que es "llená lo
    // que haya"), se cae al ancho de la pantalla, que es el techo real.
    final anchoCaja = caja?.maxWidth;
    final anchoPedido = widget.width;
    final double enPuntos;
    if (anchoCaja != null && anchoCaja.isFinite && anchoCaja > 0) {
      enPuntos = anchoCaja;
    } else if (anchoPedido != null && anchoPedido.isFinite && anchoPedido > 0) {
      enPuntos = anchoPedido;
    } else {
      enPuntos = MediaQuery.sizeOf(context).width;
    }
    final enPixeles =
        (enPuntos * MediaQuery.devicePixelRatioOf(context)).ceil();
    return enPixeles.clamp(1, tope);
  }

  @override
  Widget build(BuildContext context) {
    // URL vacía (ej. extensión sin ícono en su manifest) no es un fallo de
    // red — es que nunca hubo nada que pedir. Antes esto igual entraba al
    // ciclo completo de reintentos de ExtendedImage (hasta 6 intentos a
    // 500ms = ~3s) antes de caer al ícono de respaldo, así que el ícono
    // "tardaba en aparecer" aunque de entrada no había nada que cargar.
    if (widget.url.isEmpty || _failed) {
      return _errorBuild();
    }

    // Quien ya pasó su propio tamaño manda: la cuenta de arriba solo cubre a
    // los que no pasaron ninguno. Y `_topeDeAncho` devuelve null en
    // escritorio y teléfono, así que ahí esto no hace absolutamente nada y no
    // se agrega ni un `LayoutBuilder` al árbol.
    final leFaltaTope = widget.cacheWidth == null && widget.cacheHeight == null;
    if (leFaltaTope && _topeDelPerfil != null) {
      return LayoutBuilder(
        builder: (context, caja) =>
            _imagen(context, _topeDeAncho(context, caja)),
      );
    }
    return _imagen(context, widget.cacheWidth);
  }

  Widget _imagen(BuildContext context, int? cacheWidth) {
    final image = ExtendedImage.network(
      widget.url,
      headers: widget.headers,
      // ── Contra el parpadeo al volver a una zona ──────────────────────────
      //
      // Con esto, mientras la imagen se vuelve a decodificar se sigue pintando
      // el ÚLTIMO fotograma que ya tenía en vez de quedar en blanco. Sin esto,
      // cualquier recarga —y en Android hay varias: el sistema le pide memoria
      // a la app al abrir una ficha o el reproductor, y Flutter suelta lo
      // decodificado— dejaba la tarjeta vacía un instante y volvía. Eso es el
      // parpadeo que se ve al ir a Ajustes y volver al Inicio.
      //
      // No cambia nada cuando la imagen es NUEVA (no hay fotograma anterior
      // que mantener): ahí sigue saliendo el bloque brillando como siempre.
      gaplessPlayback: true,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      alignment: widget.alignment,
      filterQuality: widget.filterQuality,
      cache: true,
      cacheWidth: cacheWidth,
      cacheHeight: widget.cacheHeight,
      mode: widget.mode,
      // En una grilla, decenas de tarjetas piden su portada al mismo tiempo
      // — bajo esa contención el intento por defecto (3 reintentos a 100ms)
      // puede agotarse aunque la imagen esté perfectamente bien (se
      // confirmó con la misma URL+headers cargando sin problema segundos
      // después, ya sin competencia, al abrir el detalle). Más reintentos
      // con más espacio entre ellos le da tiempo a que la contención baje
      // antes de darse por vencido y quedar cacheada como fallo permanente.
      retries: 6,
      timeRetry: const Duration(milliseconds: 500),
      initGestureConfigHandler: widget.initGestureConfigHandler,
      loadStateChanged: (state) {
        switch (state.extendedImageLoadState) {
          case LoadState.loading:
            // Reintento de una que ya habia fallado: se mantiene el arte de
            // respaldo en vez de vaciar la tarjeta (ver _reintentando).
            if (_reintentando) return _errorBuild();
            // ── El hueco brilla, en TODAS las imágenes ─────────────────────
            //
            // Antes acá iba un SizedBox vacío salvo que la pantalla pasara su
            // propio placeholder — y eso solo lo hacía una. El resultado era
            // disparejo: en una fila las tarjetas brillaban y en la de al lado
            // quedaban en negro, y no se entendía si estaban cargando o si no
            // había nada.
            //
            // Poniéndolo acá vale para todo lo que dibuje una imagen: Inicio,
            // Buscar, Biblioteca, Historial, la portada de la ficha, su fondo
            // y los iconos de las extensiones. Una sola línea en vez de
            // repetir el bloque en cada pantalla.
            //
            // El brillo no cuesta un reloj por imagen: Esqueleto los comparte
            // todos en uno solo, que además se apaga cuando la app pasa a
            // segundo plano (ver _RelojDelBrillo).
            return widget.placeholder ??
                Esqueleto(
                  width: widget.width,
                  height: widget.height,
                  // Sin esquinas propias: casi siempre va dentro de algo que
                  // ya recorta (una tarjeta, la caja de la portada). Con radio
                  // se veía un redondeo adentro de otro.
                  radio: 0,
                );
          case LoadState.completed:
            // Cargo bien: se olvida cualquier fallo anterior de esta URL.
            WidgetsBinding.instance.addPostFrameCallback((_) => _markLoaded());
            // Algunas extensiones no tienen una portada real para un título
            // puntual y devuelven un ícono genérico chico (ej. un avatar
            // placeholder) en vez de un error de red — la imagen carga bien,
            // solo que es diminuta. Estirarla/recortarla con BoxFit.cover
            // sobre una tarjeta grande la deja irreconocible y descentrada.
            // Si la imagen real es más chica que el espacio que ocupa, se
            // muestra completa y centrada en vez de recortada.
            final uiImage = state.extendedImageInfo?.image;
            // Una sola vez por tarjeta: esto se dispara en cada dibujado
            // mientras la imagen esté puesta (pasar el mouse por encima ya
            // provoca uno), y no hace falta contar la misma portada cien veces.
            if (uiImage != null && !_tamanoAvisado) {
              _tamanoAvisado = true;
              widget.onTamanoReal?.call(uiImage.width, uiImage.height);
            }
            // widget.width/height suelen ser double.infinity a propósito
            // (rellenar lo que el padre disponga, ej. el fondo del detalle)
            // — comparar contra infinito siempre da "más chica", así que
            // esto solo aplica con un tamaño objetivo FINITO real.
            if (uiImage != null &&
                widget.width != null &&
                widget.width!.isFinite &&
                widget.height != null &&
                widget.height!.isFinite &&
                uiImage.width < widget.width! &&
                uiImage.height < widget.height!) {
              return Container(
                color: Colors.black12,
                alignment: Alignment.center,
                width: widget.width,
                height: widget.height,
                child: RawImage(
                  image: uiImage,
                  fit: BoxFit.contain,
                  width: widget.width,
                  height: widget.height,
                ),
              );
            }
            return state.completedWidget;
          case LoadState.failed:
            // No setState durante build — se marca para el próximo frame.
            WidgetsBinding.instance.addPostFrameCallback((_) => _markFailed());
            return _errorBuild();
        }
      },
    );

    if (widget.canFullScreen) {
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            final thumnailPage = _ThumnailPage(
              url: widget.url,
              headers: widget.headers,
            );
            if (Platform.isAndroid) {
              Get.to(thumnailPage);
              return;
            }
            fluent.showDialog(
              context: context,
              // Por defecto fluent_ui NO cierra el diálogo al tocar afuera
              // (barrierDismissible: false) — acá sí queremos ese
              // comportamiento, es solo un visor de imagen.
              barrierDismissible: true,
              // A pantalla completa y con su propia salida.
              //
              // Antes salía como un diálogo del tamaño de su contenido: la
              // portada se veía CASI igual de chica que en la ficha, y al
              // ampliarla se recortaba contra los bordes del diálogo en vez de
              // usar la ventana. Un visor de imagen tiene que dar todo el
              // espacio que hay.
              //
              // Ocupando la ventana entera ya no queda barrera que tocar para
              // cerrar, así que el fondo cierra al hacerle clic y arriba a la
              // derecha va la cruz. La imagen está por encima del fondo, así
              // que arrastrarla para moverla no cierra nada.
              builder: (dialogo) => Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.of(dialogo).pop(),
                      // ── Casi opaco, y oscuro en los DOS modos ─────────
                      //
                      // Estaba al 90%: se veía la pantalla de atrás por
                      // detrás de la portada, con su texto y sus tarjetas
                      // asomando alrededor de la imagen. Distrae de lo único
                      // que uno vino a mirar, y en modo claro es peor todavía
                      // porque lo que asoma es claro y compite de frente.
                      //
                      // Y sigue al modo. Se probó dejarlo oscuro siempre, con
                      // el argumento de que un visor de imagen se mira mejor
                      // sobre negro. No pega: con el modo claro puesto, abrir
                      // una portada apagaba la pantalla entera y cerrarla la
                      // volvía a prender, y ese golpe se nota más que cualquier
                      // ventaja de mirar sobre negro.
                      //
                      // Casi opaco en los dos, que es lo que resolvía el
                      // problema de fondo: al 90% se veía la pantalla de atrás
                      // asomando alrededor de la imagen.
                      child: ColoredBox(
                        color: HomeTheme.bg.withValues(alpha: 0.98),
                      ),
                    ),
                  ),
                  Positioned.fill(child: thumnailPage),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: fluent.IconButton(
                      icon: const Icon(fluent.FluentIcons.chrome_close,
                          size: 16),
                      onPressed: () => Navigator.of(dialogo).pop(),
                    ),
                  ),
                ],
              ),
            );
          },
          child: image,
        ),
      );
    }

    return image;
  }
}

class _ThumnailPage extends StatefulWidget {
  const _ThumnailPage({
    required this.url,
    required this.headers,
  });
  final String url;
  final Map<String, String>? headers;

  @override
  State<_ThumnailPage> createState() => _ThumnailPageState();
}

class _ThumnailPageState extends State<_ThumnailPage> {
  final menuController = fluent.FlyoutController();
  final contextAttachKey = GlobalKey();

  @override
  dispose() {
    menuController.dispose();
    super.dispose();
  }

  _saveImage() async {
    final url = widget.url;
    final fileName = url.split('/').last;
    final res = await dio.get(
      url,
      options: Options(
        responseType: ResponseType.bytes,
        headers: widget.headers,
      ),
    );
    if (Platform.isAndroid) {
      final result = await ImageGallerySaverPlus.saveImage(
        res.data,
        name: fileName,
      );
      if (mounted) {
        final msg = result['isSuccess'] == true
            ? 'common.save-success'.i18n
            : result['errorMessage'];
        showPlatformSnackbar(
          context: context,
          content: msg,
        );
      }
      return;
    }
    // 打开目录选择对话框file_picker

    final path = await FilePicker.platform.saveFile(
      type: FileType.image,
      fileName: fileName,
    );
    if (path == null) {
      return;
    }
    // 保存
    File(path).writeAsBytesSync(res.data);
  }

  Widget _buildContent(BuildContext context) {
    final imagen = ExtendedImage.network(
      widget.url,
      headers: widget.headers,
      cache: true,
      fit: BoxFit.contain,
      mode: ExtendedImageMode.gesture,
      // ── Arrastrar hacia abajo cierra, y solo en el teléfono ─────────────
      //
      // Sin esto el ExtendedImageSlidePage de afuera no hacía nada: la página
      // deslizable necesita que la imagen se lo diga. O sea que el gesto de
      // bajar para cerrar —el que uno prueba primero en cualquier visor— no
      // existía y había que buscar la flecha de atrás.
      //
      // En escritorio va apagado a propósito: ahí se cierra con la cruz o
      // haciendo clic en el fondo, y arrastrar con el ratón tiene que servir
      // para MOVER la imagen ampliada, no para cerrar sin querer.
      enableSlideOutPage: Platform.isAndroid,
      initGestureConfigHandler: (state) {
        return GestureConfig(
          minScale: 0.9,
          animationMinScale: 0.7,
          // ── Hasta ocho, no hasta tres ────────────────────────────
          //
          // Tres es poco para lo que la gente abre esto: mirar de cerca la
          // portada, leer el texto chico de una tapa o buscar el crédito del
          // autor. Y una portada mostrada entera ya arranca ocupando media
          // pantalla, así que triplicarla se queda corto.
          maxScale: 8.0,
          animationMaxScale: 8.5,
          speed: 1.0,
          // Más inercia al soltar. Con 100 el movimiento se frenaba en seco
          // apenas levantabas el dedo y se sentía pegajoso; con 220 sigue de
          // largo un poco, que es lo que hace que se sienta suelto.
          inertialSpeed: 220.0,
          initialScale: 1.0,
          // false: esto NO vive dentro de un PageView. En true, el visor le
          // cede el arrastre horizontal a un padre que no existe, y moverse de
          // costado con la imagen ampliada se sentía trabado.
          inPageView: false,
          // La rueda hacia arriba ACERCA, que es lo que hace todo lo demás.
          // Estaba al revés y era lo primero que descolocaba con el ratón.
          reverseMousePointerScrollDirection: false,
          initialAlignment: InitialAlignment.center,
        );
      },
      // Doble toque para acercar y alejar, que es lo que uno prueba primero.
      // Sin esto, la única forma era el pellizco —imposible con el ratón— así
      // que en escritorio no había manera de ampliar salvo la rueda.
      //
      // Acerca HACIA DONDE tocaste, no al centro: si tocás una esquina y la
      // imagen se acerca al medio, hay que arrastrar para volver a lo que
      // querías ver.
      onDoubleTap: (state) {
        final origen = state.gestureDetails?.totalScale ?? 1.0;
        state.handleDoubleTap(
          scale: origen < 1.5 ? 3.0 : 1.0,
          doubleTapPosition: state.pointerDownPosition,
        );
      },
    );

    // En escritorio, sin página deslizable: no hace nada con la imagen que no
    // se desliza, y de paso se saca una capa del medio.
    if (!Platform.isAndroid) return Center(child: imagen);

    return Center(
      child: ExtendedImageSlidePage(
        // Solo vertical. Con `both`, arrastrar de costado cerraba el visor en
        // vez de mover la imagen ampliada, que es justo para lo que uno
        // arrastra de costado cuando le hizo zoom.
        slideAxis: SlideAxis.vertical,
        slideType: SlideType.onlyImage,
        slidePageBackgroundHandler: (offset, pageSize) {
          // El fondo se va aclarando a medida que arrastrás: así se ve que el
          // gesto está haciendo algo y hasta dónde hay que llegar. Antes era
          // transparente siempre y el arrastre no daba ninguna señal.
          final recorrido =
              (offset.distance / (pageSize.height / 2)).clamp(0.0, 1.0);
          return Colors.black.withValues(alpha: 0.9 * (1 - recorrido));
        },
        child: imagen,
      ),
    );
  }

  Widget _buildAndroid(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: GestureDetector(
        child: _buildContent(context),
        onLongPress: () {
          showModalBottomSheet(
            context: context,
            showDragHandle: true,
            useSafeArea: true,
            builder: (_) => SizedBox(
              height: 100,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.save),
                    title: Text('common.save'.i18n),
                    onTap: () {
                      Navigator.of(context).pop();
                      _saveImage();
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDesktop(BuildContext context) {
    return GestureDetector(
      onSecondaryTapUp: (d) {
        final targetContext = contextAttachKey.currentContext;
        if (targetContext == null) return;
        final box = targetContext.findRenderObject() as RenderBox;
        final position = box.localToGlobal(
          d.localPosition,
          ancestor: Navigator.of(context).context.findRenderObject(),
        );
        menuController.showFlyout(
          position: position,
          builder: (context) {
            return fluent.MenuFlyout(items: [
              fluent.MenuFlyoutItem(
                leading: const Icon(fluent.FluentIcons.save),
                text: Text('common.save'.i18n),
                onPressed: () {
                  fluent.Flyout.of(context).close();
                  _saveImage();
                },
              ),
            ]);
          },
        );
      },
      child: fluent.FlyoutTarget(
        key: contextAttachKey,
        controller: menuController,
        child: _buildContent(context),
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
