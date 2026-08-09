import 'package:prismhub/views/widgets/detail/detail_finished_button.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:prismhub/data/providers/tmdb_provider.dart';
import 'package:prismhub/controllers/detail_controller.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/views/widgets/cache_network_image.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';

class DetailOverView extends StatefulWidget {
  const DetailOverView({
    super.key,
    this.tag,
    this.onAlto,
  });

  final String? tag;

  /// Cuánto mide de alto todo lo que hay dentro de esta pestaña.
  ///
  /// Se avisa MEDIDO, no estimado. La ficha lo necesita para saber si esta
  /// pestaña entra sin plegar la cabecera —y si entra, la pantalla no se
  /// desplaza—. Estimarlo funcionaba solo con la sinopsis pelada: en cuanto
  /// hay datos de TMDB aparecen la tira de imágenes y el bloque de
  /// información, con altos que dependen de cuánto texto traiga cada campo, y
  /// ahí había que rendirse y dar por hecho que no entraba. O sea que en vídeo
  /// —donde casi siempre hay TMDB— nunca se bloqueaba nada.
  ///
  /// Midiendo la caja de verdad da igual qué haya adentro, y se corrige solo
  /// cuando los datos de TMDB llegan tarde.
  final ValueChanged<double>? onAlto;

  /// El estilo de la sinopsis, fijado a propósito.
  ///
  /// Antes salía del tema por herencia. Se fija acá porque [altoEstimado] lo
  /// necesita para medir el texto, y un estilo que dependa de dónde esté
  /// colgado el widget haría que la medición y lo dibujado no coincidan.
  static TextStyle get estiloSinopsis => TextStyle(
    height: 2,
    fontSize: 14,
    color: HomeTheme.textPrimary,
  );

  static const _rellenoArriba = 16.0;
  static const _rellenoCostado = 16.0;
  static const _rellenoAbajo = 20.0;

  /// Cuánto alto necesita esta pestaña con el ancho dado.
  ///
  /// Devuelve **null** cuando no se puede saber, y quien pregunta tiene que
  /// dar por hecho que NO entra. Pasa cuando hay datos de TMDB: traen tiras de
  /// imágenes y bloques de información de alto variable, y estimarlos sería
  /// adivinar. De esto depende si la pantalla se puede desplazar o no, así que
  /// equivocarse hacia abajo escondería texto.
  static double? altoEstimado(
    BuildContext context,
    double ancho,
    DetailPageController c,
  ) {
    if (c.tmdbDetail != null) return null;
    if (ancho <= _rellenoCostado * 2) return null;

    final desc = c.tmdbDetail?.overview ?? c.detail?.desc;
    final texto =
        (desc == null || desc.isEmpty) ? "detail.no-description".i18n : desc;

    final medidor = TextPainter(
      text: TextSpan(text: texto, style: estiloSinopsis),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: ancho - _rellenoCostado * 2);
    final altoTexto = medidor.height;
    medidor.dispose();

    // El botón de "terminó de publicarse" solo aparece en contenido por
    // capítulos — ver DetailFinishedButton.
    final boton = (Platform.isAndroid && c.isSerialized) ? 50.0 + 16.0 : 0.0;
    return _rellenoArriba + boton + altoTexto + _rellenoAbajo;
  }

  @override
  State<DetailOverView> createState() => _DetailOverViewState();
}

class _DetailOverViewState extends State<DetailOverView> {
  /// La caja que se mide: contiene TODO lo de la pestaña.
  final _caja = GlobalKey();
  double _ultimoAlto = -1;

  String? get tag => widget.tag;

  /// Mide después de dibujar y avisa, solo si cambió.
  ///
  /// Después del cuadro y no durante: acá se lee el tamaño ya calculado, y
  /// pedirlo en pleno dibujado devuelve el de la vez anterior o revienta. Y
  /// solo cuando cambia de verdad, porque el que escucha hace `setState`: sin
  /// esa guarda serían dos reconstrucciones por cuadro, para siempre.
  void _medir() {
    final avisar = widget.onAlto;
    if (avisar == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final alto = _caja.currentContext?.size?.height;
      if (alto == null) return;
      // El relleno de arriba va por fuera de la caja medida.
      final total = alto + DetailOverView._rellenoArriba;
      if ((total - _ultimoAlto).abs() < 1) return;
      _ultimoAlto = total;
      avisar(total);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = Get.find<DetailPageController>(tag: tag);
    _medir();
    return Padding(
      padding: const EdgeInsets.only(
        left: DetailOverView._rellenoCostado,
        right: DetailOverView._rellenoCostado,
        top: DetailOverView._rellenoArriba,
      ),
      child: SingleChildScrollView(
        child: Column(
          key: _caja,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // En celular el botón va acá y no en el hero: ahí ya conviven
            // "Continuar" y "Favorito" en un ancho justo, y en horizontal un
            // tercero los dejaba ilegibles. Acá además queda al lado del
            // estado que informa la extensión, que es con lo que dialoga.
            if (Platform.isAndroid) ...[
              DetailFinishedButton(tag: tag),
              const SizedBox(height: 16),
            ],
            Obx(() {
              if (c.tmdbDetail == null || c.tmdbDetail!.backdrop == null) {
                return const SizedBox();
              }
              final images = [c.tmdbDetail!.backdrop!, ...c.tmdbDetail!.images];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'tmdb.backdrops'.i18n,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 160,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemBuilder: (context, index) {
                        final image = images[index];
                        final url = TmdbApi.getImageUrl(image);
                        if (url == null) {
                          return const SizedBox();
                        }
                        return Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          clipBehavior: Clip.antiAlias,
                          margin: const EdgeInsets.only(right: 8),
                          child: CacheNetWorkImagePic(
                            url,
                            height: 160,
                            canFullScreen: true,
                          ),
                        );
                      },
                      itemCount: images.length,
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              );
            }),
            Obx(() {
              final desc = c.tmdbDetail?.overview ?? c.detail?.desc;
              final hasDesc = desc != null && desc.isNotEmpty;
              return SelectableText(
                hasDesc ? desc : "detail.no-description".i18n,
                style: DetailOverView.estiloSinopsis.copyWith(
                  color: hasDesc ? HomeTheme.textPrimary : HomeTheme.textMuted,
                ),
              );
            }),
            const SizedBox(height: DetailOverView._rellenoAbajo),
            Obx(
              () {
                if (c.tmdbDetail == null) {
                  return const SizedBox();
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'detail.additional-info'.i18n,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      "${'tmdb.status'.i18n}: ${c.tmdbDetail!.status}",
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "${'tmdb.genres'.i18n}: ${c.tmdbDetail!.genres.join(', ')}",
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "${'tmdb.languages'.i18n}: ${c.tmdbDetail!.languages.join(', ')}",
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "${'tmdb.release-date'.i18n}: ${c.tmdbDetail!.releaseDate}",
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "${'tmdb.original-title'.i18n}: ${c.tmdbDetail!.originalTitle}",
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "${'tmdb.runtime'.i18n}: ${c.tmdbDetail!.runtime}",
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                );
              },
            )
          ],
        ),
      ),
    );
  }
}
