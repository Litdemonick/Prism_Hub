import 'dart:io';

import 'package:dio/dio.dart';
import 'package:extended_image/extended_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/request.dart';
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
  static final Set<String> _knownFailedUrls = <String>{};

  // Incluye los headers en la clave — si la primera vez falló sin headers
  // (ej. un sitio que exige Referer y no se lo dimos) y después se reintenta
  // CON los headers correctos, es un intento distinto y merece una
  // oportunidad real, no quedar bloqueado por el fallo anterior.
  String get _failureKey => '${widget.url}|${widget.headers ?? ''}';

  bool get _failed => _knownFailedUrls.contains(_failureKey);

  void _markFailed() {
    if (_knownFailedUrls.add(_failureKey) && mounted) {
      setState(() {});
    }
  }

  // Branded placeholder for a cover that failed to load — the source site
  // may be down or blocking, not necessarily an app bug. assets/carddefaultoffline.png
  // is the app's dedicated "offline/no image" art, so it reads as an
  // intentional state instead of a bare error icon.
  Widget _errorBuild() {
    if (widget.fallback != null) {
      return widget.fallback!;
    }
    // cover para que llene la tarjeta entera (nada de franjas negras) — el
    // arte es un logo centrado sobre fondo liso, así que recortar el margen
    // no se nota. OJO: `fit` solo pinta los píxeles DENTRO de la caja que
    // Image ya decidió — si el padre da constraints sueltas (loose, con
    // mínimo 0 — ej. un Stack normal, fit: loose por defecto), Image elige
    // su PROPIA caja preservando el aspect ratio de la imagen (como si
    // fuera contain), dejando un resto sin pintar aunque el fit diga
    // "cover". Por eso acá se fuerza width/height infinitos (rellenan lo
    // que el padre dé) — pero SOLO cuando el alto está acotado: en el
    // lector (alto sin acotar a propósito) forzarlo rompe el layout
    // (crashea el hit-test, app se cuelga), así que ahí se deja sin forzar
    // y cae al tamaño por aspect ratio, que es seguro.
    return LayoutBuilder(
      builder: (context, constraints) {
        final bounded =
            constraints.maxWidth.isFinite && constraints.maxHeight.isFinite;
        return ColoredBox(
          color: Colors.black,
          child: Padding(
            padding: bounded ? const EdgeInsets.all(28) : EdgeInsets.zero,
            child: Image.asset(
              'assets/carddefaultoffline.png',
              fit: BoxFit.contain,
              alignment: Alignment.center,
              width: bounded ? double.infinity : null,
              height: bounded ? double.infinity : null,
            ),
          ),
        );
      },
    );
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

    final image = ExtendedImage.network(
      widget.url,
      headers: widget.headers,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      alignment: widget.alignment,
      filterQuality: widget.filterQuality,
      cache: true,
      cacheWidth: widget.cacheWidth,
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
            return widget.placeholder ?? const SizedBox();
          case LoadState.completed:
            // Algunas extensiones no tienen una portada real para un título
            // puntual y devuelven un ícono genérico chico (ej. un avatar
            // placeholder) en vez de un error de red — la imagen carga bien,
            // solo que es diminuta. Estirarla/recortarla con BoxFit.cover
            // sobre una tarjeta grande la deja irreconocible y descentrada.
            // Si la imagen real es más chica que el espacio que ocupa, se
            // muestra completa y centrada en vez de recortada.
            final uiImage = state.extendedImageInfo?.image;
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
              builder: (_) => thumnailPage,
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
    return Center(
      child: ExtendedImageSlidePage(
        slideAxis: SlideAxis.both,
        slideType: SlideType.onlyImage,
        slidePageBackgroundHandler: (offset, pageSize) {
          final color = Platform.isAndroid
              ? Theme.of(context).scaffoldBackgroundColor
              : fluent.FluentTheme.of(context).scaffoldBackgroundColor;
          return color.withValues(alpha: 0);
        },
        child: ExtendedImage.network(
          widget.url,
          headers: widget.headers,
          cache: true,
          fit: BoxFit.contain,
          mode: ExtendedImageMode.gesture,
          initGestureConfigHandler: (state) {
            return GestureConfig(
              minScale: 0.9,
              animationMinScale: 0.7,
              maxScale: 3.0,
              animationMaxScale: 3.5,
              speed: 1.0,
              inertialSpeed: 100.0,
              initialScale: 1.0,
              inPageView: true,
              reverseMousePointerScrollDirection: true,
              initialAlignment: InitialAlignment.center,
            );
          },
        ),
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
