import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:get/get.dart';
import 'package:prismhub/models/extension.dart';
import 'package:prismhub/controllers/detail_controller.dart';
import 'package:prismhub/views/widgets/detail/detail_continue_play.dart';
import 'package:prismhub/utils/prismhub_storage.dart';
import 'package:prismhub/views/widgets/detail/detail_card_tile.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/platform_widget.dart';

/// La geometría de la lista de capítulos, en un solo lugar.
///
/// La usa la propia lista para dibujarse y la ficha para saber si entra sin
/// desplazamiento (ver [GeometriaCapitulos.altoDeLaLista] y el `physics` del
/// NestedScrollView). Antes eran números sueltos en los dos lados y no
/// coincidían: la cuenta daba de más y la pantalla se seguía desplazando hacia
/// el vacío teniendo dos capítulos.
class GeometriaCapitulos {
  GeometriaCapitulos._();

  static const margen = 12.0;

  /// El hueco de abajo, para que el botón flotante no tape el último.
  static const rellenoAbajo = 88.0;

  static const separacion = 8.0;
  static const separacionGrilla = 10.0;

  /// Ancho mínimo de una tarjeta de la grilla de vídeo: el que hace entrar
  /// "Capítulo 128" cómodo.
  static const anchoMinimoGrilla = 168.0;
  static const proporcionGrilla = 2.5;

  static const altoSelector = 58.0;
  static const altoFilaTotal = 54.0;

  /// Un episodio suelto (una película) no va en grilla: va un botón grande.
  static const altoBotonUnico = 64.0;

  // La tarjeta de lectura, pieza por pieza.
  static const tarjetaRelleno = 28.0; // 14 arriba + 14 abajo
  static const tarjetaAire = 8.0; // entre el título y la caja
  static const tarjetaCaja = 30.0; // la caja del idioma
  static const tituloTarjeta = TextStyle(
    fontSize: 16,
    height: 1.25,
    fontWeight: FontWeight.w700,
    color: HomeTheme.textPrimary,
  );

  /// Lo que la tarjeta de lectura se lleva sin ser texto: los rellenos
  /// laterales, el aire y el icono de la derecha.
  static const anchoNoTexto = 16.0 + 12.0 + 22.0 + 12.0;

  static int columnasGrilla(double ancho) =>
      (ancho / anchoMinimoGrilla).floor().clamp(2, 6);

  /// Cuánto mide la lista entera con estos capítulos y este ancho.
  ///
  /// Los títulos se MIDEN, no se estiman: de esto depende si la pantalla se
  /// puede desplazar, y estimando "dos líneas por las dudas" la cuenta daba
  /// siempre de más y nunca se bloqueaba nada. Solo se llama con pocos
  /// capítulos —con muchos no entra ni por asomo— así que medir uno por uno no
  /// cuesta nada.
  ///
  /// Devuelve null si no se puede calcular con el ancho que hay.
  static double? altoDeLaLista({
    required BuildContext context,
    required double ancho,
    required List<String> etiquetas,
    required bool enGrilla,
    required bool hayGrupos,
  }) {
    final total = etiquetas.length;
    if (total == 0) return null;
    final cabecera = (hayGrupos ? altoSelector : 0.0) + altoFilaTotal;
    final libre = ancho - margen * 2;
    if (libre <= 0) return null;

    if (enGrilla) {
      if (total == 1) return cabecera + altoBotonUnico + rellenoAbajo;
      final columnas = columnasGrilla(ancho);
      final anchoCelda =
          (libre - separacionGrilla * (columnas - 1)) / columnas;
      if (anchoCelda <= 0) return null;
      final filas = (total + columnas - 1) ~/ columnas;
      return cabecera +
          filas * (anchoCelda / proporcionGrilla) +
          (filas - 1) * separacionGrilla +
          rellenoAbajo;
    }

    final anchoTexto = libre - anchoNoTexto;
    if (anchoTexto <= 0) return null;
    var alto = cabecera + rellenoAbajo + (total - 1) * separacion;
    for (final etiqueta in etiquetas) {
      final medidor = TextPainter(
        text: TextSpan(text: etiqueta, style: tituloTarjeta),
        maxLines: 2,
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: anchoTexto);
      alto += tarjetaRelleno + medidor.height + tarjetaAire + tarjetaCaja;
      medidor.dispose();
    }
    return alto;
  }
}

/// Una tarjeta de la grilla de episodios (vídeo).
///
/// Corta y con el texto centrado: los episodios se llaman casi siempre
/// "Capítulo N" y una fila entera por cada uno es ancho tirado.
class _TarjetaDeGrilla extends StatelessWidget {
  const _TarjetaDeGrilla({
    required this.etiqueta,
    required this.onTap,
    this.enCurso = false,
  });

  final String etiqueta;
  final VoidCallback onTap;

  /// Es el último que se abrió. Se marca con el color de acento en vez de con
  /// un icono suelto: se ve de un vistazo al bajar por una lista larga.
  final bool enCurso;

  @override
  Widget build(BuildContext context) {
    return _CajaDeTarjeta(
      enCurso: enCurso,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Center(
          child: Text(
            etiqueta,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.3,
              fontWeight: enCurso ? FontWeight.w700 : FontWeight.w500,
              color: enCurso ? HomeTheme.accentPink : HomeTheme.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Una fila de la lista de capítulos (lectura).
///
/// El título grande arriba y debajo una caja con el idioma, que es el dato que
/// la extensión declara en su manifiesto y vale para todos sus capítulos.
///
/// **La fecha de publicación y las miniaturas no están.** `ExtensionEpisode`
/// solo trae `name` y `url`: no hay imagen, ni fecha, ni idioma POR capítulo.
/// Para eso hace falta que el SDK lleve esos campos y que cada extensión los
/// scrapee del sitio. La caja está armada para recibirlos: cuando lleguen,
/// entran acá y en ningún otro lado.
class _TarjetaDeCapitulo extends StatelessWidget {
  const _TarjetaDeCapitulo({
    required this.etiqueta,
    required this.onTap,
    this.idioma,
    this.enCurso = false,
  });

  final String etiqueta;
  final String? idioma;
  final VoidCallback onTap;
  final bool enCurso;

  @override
  Widget build(BuildContext context) {
    final acento = enCurso ? HomeTheme.accentPink : HomeTheme.textPrimary;

    return _CajaDeTarjeta(
      enCurso: enCurso,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    etiqueta,
                    // Dos líneas: los capítulos que traen el título de la obra
                    // adelante se cortaban siempre con puntos suspensivos, y
                    // en varias extensiones el número queda al final — se
                    // perdía justo el dato que identifica cuál es.
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GeometriaCapitulos.tituloTarjeta
                        .copyWith(color: acento),
                  ),
                  const SizedBox(height: GeometriaCapitulos.tarjetaAire),
                  Container(
                    height: GeometriaCapitulos.tarjetaCaja,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: enCurso
                            ? HomeTheme.accentPink.withValues(alpha: 0.5)
                            : HomeTheme.border,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.translate_rounded,
                            size: 14, color: HomeTheme.textMuted),
                        const SizedBox(width: 7),
                        Text(
                          // Sin idioma declarado no se inventa ninguno: se
                          // deja el guion largo, que se lee como "no se sabe".
                          idioma ?? '—',
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: HomeTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              enCurso
                  ? Icons.play_circle_outline_rounded
                  : Icons.chevron_right_rounded,
              size: 22,
              color: enCurso ? HomeTheme.accentPink : HomeTheme.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

/// El envoltorio que comparten las dos tarjetas: color, forma, borde y toque.
///
/// El color y el borde los pone el Material y no un Container adentro: así el
/// destello del toque queda recortado por la tarjeta en vez de pintarse por
/// encima o desbordar las esquinas.
class _CajaDeTarjeta extends StatelessWidget {
  const _CajaDeTarjeta({
    required this.child,
    required this.onTap,
    required this.enCurso,
  });

  final Widget child;
  final VoidCallback onTap;
  final bool enCurso;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enCurso
          ? HomeTheme.accentPink.withValues(alpha: 0.12)
          : HomeTheme.cardSurface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: enCurso ? HomeTheme.accentPink : HomeTheme.border,
          width: enCurso ? 1.4 : 1,
        ),
      ),
      child: InkWell(onTap: onTap, child: child),
    );
  }
}

class DetailEpisodes extends StatefulWidget {
  const DetailEpisodes({
    super.key,
    this.tag,
  });
  final String? tag;

  static final _numberPattern = RegExp(r'\d+(?:\.\d+)?');

  /// Cómo se muestra el nombre de un capítulo.
  ///
  /// Estática porque la ficha la necesita para MEDIR la lista y decidir si
  /// entra sin desplazamiento: tiene que medir exactamente el mismo texto que
  /// después se dibuja.
  ///
  /// Nombres cortos (ej. "Capítulo 8.5") nunca se truncan, no hace falta
  /// tocarlos. Los largos (título completo de la serie + número) sí se
  /// recortan con ellipsis en espacios angostos, y el número queda tapado.
  /// Antes se anteponía la POSICIÓN en la lista (index+1) como si fuera el
  /// número — rompe apenas hay un especial/capítulo no secuencial (ej.
  /// "Capítulo 8.5" en la posición 9 mostraba "9." como si ese fuera el
  /// número real). Ahora se extrae el número DE VERDAD desde el propio
  /// nombre — si no hay ninguno, se deja el nombre tal cual (se acepta el
  /// recorte antes que inventar un dato).
  static String etiquetaDe(String name) {
    if (name.length <= 20) return name;
    final matches = _numberPattern.allMatches(name).toList();
    if (matches.isEmpty) return name;
    final number = matches.last.group(0)!;
    if (name.trimLeft().startsWith(number)) return name;
    return '$number. $name';
  }

  @override
  State<DetailEpisodes> createState() => _DetailEpisodesState();
}

class _DetailEpisodesState extends State<DetailEpisodes> {
  late DetailPageController c = Get.find<DetailPageController>(tag: widget.tag);
  List<fluent.ComboBoxItem<int>>? comboBoxItems;
  List<DropdownMenuItem<int>>? dropdownItems;
  late List<ExtensionEpisodeGroup> episodes = [];
  late String listMode = PrismHubStorage.getSetting(SettingKey.listMode);
  bool isRevered = false;

  String _episodeLabel(String name) => DetailEpisodes.etiquetaDe(name);

  /// El último capítulo/episodio abierto, si es de este mismo grupo.
  ///
  /// Solo se marca ESE. El historial guarda un único identificador, así que
  /// dar por leídos también los anteriores sería inventar: alcanza con abrir
  /// el último para que todo lo de atrás quedara marcado sin haberlo visto.
  int get _enCurso {
    final h = c.history.value;
    if (h == null || h.episodeTitle.isEmpty) return -1;
    if (h.episodeGroupId != c.selectEpGroup.value) return -1;
    return h.episodeId;
  }

  DateTime? _ultimoToque;

  /// Cortafuegos contra el toque repetido.
  ///
  /// Tocar dos veces seguidas un capítulo encadenaba dos aperturas: se abría
  /// el lector/reproductor y encima se le pedía otra. Media segundo de
  /// silencio alcanza y no se nota al usar la app normalmente.
  bool _puedeAbrir() {
    final ahora = DateTime.now();
    final anterior = _ultimoToque;
    if (anterior != null &&
        ahora.difference(anterior) < const Duration(milliseconds: 600)) {
      return false;
    }
    _ultimoToque = ahora;
    return true;
  }

  void _abrir(BuildContext context, int indice) {
    if (!_puedeAbrir()) return;
    // Protección: entre que se dibujó la lista y el toque, la extensión pudo
    // haber devuelto otro detalle (se refrescó, cambió el grupo). Sin esto,
    // un índice viejo revienta con RangeError.
    final grupo = c.selectEpGroup.value;
    if (grupo < 0 || grupo >= episodes.length) return;
    final urls = episodes[grupo].urls;
    if (indice < 0 || indice >= urls.length) return;
    c.goWatch(context, urls, indice, grupo);
  }

  Widget _buildAndroidEpisodes(BuildContext context) {
    final urls =
        episodes.isEmpty ? const [] : episodes[c.selectEpGroup.value].urls;
    final total = urls.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // El selector de grupo, SOLO si hay más de uno donde elegir.
        //
        // Con un grupo solo era una barra de lado a lado que decía "Episodios"
        // y no ofrecía nada: 48 puntos de alto tirados, justo arriba de la
        // lista. Y salía del morado de Material por defecto
        // (colorScheme.primaryContainer), que no es ningún color de la app: en
        // una pantalla que por lo demás es negra y rosa, era lo primero que se
        // veía. La mayoría de los títulos tiene un grupo solo.
        if (episodes.length > 1)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: HomeTheme.cardSurface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: HomeTheme.border),
            ),
            child: DropdownButton<int>(
              isExpanded: true,
              underline: const SizedBox(),
              dropdownColor: HomeTheme.cardSurface,
              iconEnabledColor: HomeTheme.textMuted,
              borderRadius: BorderRadius.circular(10),
              style: const TextStyle(
                color: HomeTheme.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              value: c.selectEpGroup.value,
              items: dropdownItems,
              onChanged: (value) {
                setState(() {
                  c.selectEpGroup.value = value!;
                });
              },
            ),
          ),
        if (total > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
            child: Row(
              children: [
                Text(
                  FlutterI18n.translate(
                    context,
                    'detail.total-episodes',
                    translationParams: {'total': total.toString()},
                  ),
                  // 14 y apagado, no 18: es un dato de referencia, no un
                  // título. Con 18 pesaba más que los propios capítulos.
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: HomeTheme.textMuted,
                  ),
                ),
                const Spacer(),
                Transform.flip(
                  flipY: isRevered,
                  child: IconButton(
                    visualDensity: VisualDensity.compact,
                    color: HomeTheme.textMuted,
                    onPressed: () {
                      setState(() {
                        isRevered = !isRevered;
                      });
                    },
                    icon: const Icon(Icons.sort_rounded),
                  ),
                )
              ],
            ),
          ),
        if (total == 0)
          Expanded(
            child: Center(
              child: Text(
                c.type == ExtensionType.bangumi
                    ? 'video.no-episodes-yet'.i18n
                    : 'reader.no-chapters-yet'.i18n,
                style: const TextStyle(color: HomeTheme.textMuted),
              ),
            ),
          )
        else
          Expanded(
            child: LayoutBuilder(
              builder: (context, cons) => c.type == ExtensionType.bangumi
                  ? _grillaDeEpisodios(context, urls, cons.maxWidth)
                  : _listaDeCapitulos(context, urls),
            ),
          )
      ],
    );
  }

  static const _rellenoLista = EdgeInsets.fromLTRB(
    GeometriaCapitulos.margen,
    0,
    GeometriaCapitulos.margen,
    GeometriaCapitulos.rellenoAbajo,
  );

  /// Vídeo: una grilla de tarjetas cortas.
  ///
  /// Los episodios se llaman casi siempre "Capítulo N", así que una fila
  /// entera por cada uno es ancho desperdiciado: en un teléfono se veían 8 y
  /// ahora entran 20, y en una tablet acostada la temporada completa de una.
  /// La lista de una columna se queda para lectura, donde los nombres son
  /// largos de verdad.
  Widget _grillaDeEpisodios(
      BuildContext context, List<dynamic> urls, double ancho) {
    final total = urls.length;

    // Un episodio solo es una película: una grilla con una tarjeta suelta que
    // dice "Capítulo 1" no informa nada. Va el botón directo.
    if (total == 1) {
      return ListView(
        padding: _rellenoLista,
        children: [
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: () => _abrir(context, 0),
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(
                FlutterI18n.translate(context, 'video.tooltip.play'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              style: ButtonStyle(
                backgroundColor:
                    WidgetStateProperty.all(HomeTheme.accentPink),
                foregroundColor: WidgetStateProperty.all(HomeTheme.bg),
              ),
            ),
          ),
        ],
      );
    }

    final columnas = GeometriaCapitulos.columnasGrilla(ancho);
    final enCurso = _enCurso;

    return GridView.builder(
      padding: _rellenoLista,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columnas,
        crossAxisSpacing: GeometriaCapitulos.separacionGrilla,
        mainAxisSpacing: GeometriaCapitulos.separacionGrilla,
        childAspectRatio: GeometriaCapitulos.proporcionGrilla,
      ),
      itemCount: total,
      itemBuilder: (context, index) {
        final real = isRevered ? total - 1 - index : index;
        return _TarjetaDeGrilla(
          etiqueta: _episodeLabel(urls[real].name as String),
          enCurso: real == enCurso,
          onTap: () => _abrir(context, real),
        );
      },
    );
  }

  /// Lectura: una fila por capítulo, con el idioma debajo del título.
  Widget _listaDeCapitulos(BuildContext context, List<dynamic> urls) {
    final total = urls.length;
    final enCurso = _enCurso;
    final idioma = _idiomaDeLaExtension(context);

    return ListView.separated(
      padding: _rellenoLista,
      itemCount: total,
      separatorBuilder: (context, index) =>
          const SizedBox(height: GeometriaCapitulos.separacion),
      itemBuilder: (context, index) {
        // La posición real dentro de la lista de la extensión. Se calcula una
        // vez y se usa para el nombre Y para abrir: antes iban por separado y
        // era fácil que se despegaran.
        final real = isRevered ? total - 1 - index : index;
        return _TarjetaDeCapitulo(
          etiqueta: _episodeLabel(urls[real].name as String),
          idioma: idioma,
          enCurso: real == enCurso,
          onTap: () => _abrir(context, real),
        );
      },
    );
  }

  /// El idioma que declara la extensión en su manifiesto.
  ///
  /// Es del SITIO, no del capítulo: el modelo no trae idioma por capítulo (ver
  /// [_TarjetaDeCapitulo]). Pero una extensión sirve un idioma, así que decirlo
  /// es correcto y es el dato que uno busca al elegir dónde leer.
  String? _idiomaDeLaExtension(BuildContext context) {
    final codigo = c.extension?.lang.trim().toLowerCase();
    if (codigo == null || codigo.isEmpty) return null;
    // "es-la", "pt-br": vale la parte de adelante.
    final base = codigo.split(RegExp('[-_]')).first;
    return FlutterI18n.translate(
      context,
      'detail.lang.$base',
      // Un idioma que no esté en la lista sale con su código, no con la clave
      // sin traducir.
      fallbackKey: 'detail.lang-other',
      translationParams: {'s': codigo.toUpperCase()},
    );
  }

  fluent.ButtonStyle get _chipButtonStyle => fluent.ButtonStyle(
        backgroundColor: fluent.WidgetStateProperty.resolveWith((states) {
          if (states.isPressed || states.isHovered) {
            return HomeTheme.accentPink.withValues(alpha: 0.18);
          }
          return HomeTheme.cardSurface;
        }),
        foregroundColor: fluent.WidgetStateProperty.resolveWith((states) {
          if (states.isPressed || states.isHovered) {
            return HomeTheme.accentPink;
          }
          return HomeTheme.textPrimary;
        }),
        shape: fluent.WidgetStateProperty.resolveWith((states) {
          return RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: states.isPressed || states.isHovered
                  ? HomeTheme.accentPink
                  : HomeTheme.border,
            ),
          );
        }),
      );

  Widget _buildDesktopEpisodes(BuildContext context) {
    late String episodesString;
    late String noEpisodesYetString;
    if (c.type == ExtensionType.bangumi) {
      episodesString = 'video.episodes'.i18n;
      noEpisodesYetString = 'video.no-episodes-yet'.i18n;
    } else {
      episodesString = 'reader.chapters'.i18n;
      noEpisodesYetString = 'reader.no-chapters-yet'.i18n;
    }
    final noEpisodes =
        episodes.isEmpty || episodes[c.selectEpGroup.value].urls.isEmpty;

    Widget cardTile(Widget child) {
      return DetailCardTile(
        title: episodesString,
        leading: Row(children: [
          fluent.IconButton(
            icon: Icon(
              listMode == "grid"
                  ? fluent.FluentIcons.view_list
                  : fluent.FluentIcons.grid_view_medium,
              color: HomeTheme.textPrimary,
            ),
            onPressed: () {
              setState(() {
                listMode == "grid" ? listMode = "list" : listMode = "grid";
                PrismHubStorage.setSetting(SettingKey.listMode, listMode);
              });
            },
          ),
          fluent.IconButton(
            icon: Icon(
              isRevered
                  ? fluent.FluentIcons.sort_lines_ascending
                  : fluent.FluentIcons.sort_lines,
              color: HomeTheme.textPrimary,
            ),
            onPressed: () {
              setState(() {
                isRevered = !isRevered;
                // PrismHubStorage.setSetting(SettingKey.listMode, listMode);
              });
            },
          )
        ]),
        trailing: Row(
          children: [
            DetailContinuePlay(tag: widget.tag),
            const SizedBox(width: 8),
            fluent.ComboBox<int>(
              items: comboBoxItems,
              value: c.selectEpGroup.value,
              onChanged: (value) {
                setState(() {
                  c.selectEpGroup.value = value!;
                });
              },
            )
          ],
        ),
        child: Container(
          constraints: const BoxConstraints(
            maxHeight: 500,
          ),
          child: child,
        ),
      );
    }

    if (noEpisodes) {
      // SizedBox con alto fijo y chico — antes esto pasaba por el mismo
      // Container(maxHeight: 500) que la grilla/lista con contenido real,
      // y Center se estiraba a ocupar las 500px igual, dejando un cartel
      // de una sola línea perdido en medio de un espacio enorme.
      return cardTile(
        SizedBox(
          height: 120,
          child: Center(
            child: Text(
              noEpisodesYetString,
              style: const TextStyle(color: HomeTheme.textMuted),
            ),
          ),
        ),
      );
    }

    if (listMode == "grid") {
      return cardTile(
        LayoutBuilder(
          builder: (context, constraints) {
            return GridView.builder(
              reverse: isRevered,
              shrinkWrap: true,
              itemCount: episodes.isEmpty
                  ? 0
                  : episodes[c.selectEpGroup.value].urls.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: (constraints.maxWidth ~/ 160).clamp(1, 20),
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                // Antes 5 (celdas muy bajas/angostas) sin overflow en el
                // Text — nombres largos ("Capítulo 95.5", títulos con
                // texto) se cortaban a la mitad contra el borde del botón.
                // Con menos alto de celda + maxLines/overflow explícitos
                // en el Text de abajo, ahora se recortan prolijo (ellipsis)
                // en vez de tajarse.
                childAspectRatio: 3.4,
              ),
              itemBuilder: (context, index) {
                final name = episodes[c.selectEpGroup.value].urls[index].name;
                return fluent.Button(
                  style: _chipButtonStyle,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Center(
                      child: Text(
                        _episodeLabel(name),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  onPressed: () async {
                    c.goWatch(
                      context,
                      episodes[c.selectEpGroup.value].urls,
                      index,
                      c.selectEpGroup.value,
                    );
                  },
                );
              },
            );
          },
        ),
      );
    }

    return cardTile(
      ListView.builder(
        shrinkWrap: true,
        reverse: isRevered,
        padding: const EdgeInsets.all(0),
        itemCount:
            episodes.isEmpty ? 0 : episodes[c.selectEpGroup.value].urls.length,
        itemBuilder: (context, index) {
          final name = episodes[c.selectEpGroup.value].urls[index].name;
          return fluent.ListTile(
            title: Text(
              _episodeLabel(name),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: HomeTheme.textPrimary),
            ),
            onPressed: () {
              c.goWatch(
                context,
                episodes[c.selectEpGroup.value].urls,
                index,
                c.selectEpGroup.value,
              );
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      episodes = c.isLoading.value ? [] : c.detail!.episodes ?? [];
      dropdownItems = [
        for (var i = 0; i < episodes.length; i++)
          DropdownMenuItem<int>(
            value: i,
            child: Text(episodes[i].title),
          )
      ];
      comboBoxItems = [
        for (var i = 0; i < episodes.length; i++)
          fluent.ComboBoxItem<int>(
            value: i,
            child: Text(episodes[i].title),
          )
      ];
      return PlatformBuildWidget(
        androidBuilder: _buildAndroidEpisodes,
        desktopBuilder: _buildDesktopEpisodes,
      );
    });
  }
}
