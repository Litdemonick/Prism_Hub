import 'package:flutter/material.dart';
import 'package:prismhub/controllers/detail_controller.dart';
import 'package:prismhub/models/extension.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/views/widgets/cache_network_image.dart';
import 'package:prismhub/views/widgets/detail/detail_continue_play.dart';
import 'package:prismhub/views/widgets/detail/detail_episodes.dart';
import 'package:prismhub/views/widgets/detail/detail_favorite_button.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';

// ─── La ficha en Android TV ─────────────────────────────────────────────
//
// Hecha de cero, no adaptada. Las de teléfono y escritorio son una cabecera
// alta que se pliega al desplazar, con pestañas debajo (Sinopsis /
// Episodios): eso funciona con dedo o con rueda, pero con un mando obliga a
// bajar a ciegas por una pantalla que se mueve sola, y las pestañas son un
// destino más al que llegar antes de poder elegir un episodio.
//
// Acá el reparto es fijo y todo se ve a la vez:
//
//   · **Izquierda**: portada, título, datos y las acciones. No se desplaza.
//   · **Derecha**: los episodios, que es lo único que se recorre.
//
// Es el mismo criterio de la Home de TV (sidebar fijo + panel que se
// recorre), y significa que desde el episodio uno llega a "Ver ahora" con
// una sola flecha, sin cruzar la pantalla ni buscar una pestaña.
//
// Lo que NO se reescribe: los datos y las acciones son las mismas piezas de
// siempre (`DetailContinuePlay`, `DetailFavoriteButton`, `DetailEpisodes`),
// que ya se enfocan solas en TV. Acá solo cambia cómo se reparten.
class DetailTV extends StatelessWidget {
  const DetailTV({super.key, required this.c, this.tag});

  final DetailPageController c;
  final String? tag;

  /// El margen contra el borde de la pantalla (overscan).
  ///
  /// Estaba escrito acá y en `home_page_tv.dart` con el mismo cuerpo — ahora
  /// las dos apuntan a la única definición, en `HomeTheme.overscanTv`.
  static double _overscan(BuildContext context) =>
      HomeTheme.overscanTv(context);

  @override
  Widget build(BuildContext context) {
    final overscan = _overscan(context);
    return Scaffold(
      backgroundColor: HomeTheme.bg,
      body: Stack(
        children: [
          // La portada, enorme y muy tenue, como fondo. No es decoración
          // gratis: en una pantalla grande y oscura da contexto de QUÉ se
          // está mirando sin robarle sitio a nada.
          // ── El fondo: la portada grande, difuminándose hacia el texto ──
          //
          // La primera versión ponía la imagen a opacidad 0.14 sobre toda la
          // pantalla: quedaba tan tenue que no se veía nada y solo ensuciaba
          // el fondo. Ahora se ve de verdad —a la derecha, donde no compite
          // con la ficha— y se apaga con un degradado hacia la izquierda,
          // que es donde va el texto y donde el contraste importa.
          if (c.portada != null)
            Positioned.fill(
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (rect) => const LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Colors.transparent, Colors.white],
                  // Arranca antes y llega entera: la imagen ocupa el fondo
                  // de verdad en vez de asomar solo en un costado. El
                  // degradado sigue apagándola sobre la ficha, que es donde
                  // hay texto que leer.
                  stops: [0.12, 0.62],
                ).createShader(rect),
                child: CacheNetWorkImagePic(
                  c.portada!,
                  headers: c.portadaHeaders,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          // Un velo por encima: la portada es el fondo, no el contenido —
          // sin esto, sobre una imagen clara los títulos de los episodios no
          // se leen.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    HomeTheme.bg,
                    HomeTheme.bg.withValues(alpha: 0.78),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: EdgeInsets.all(overscan),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    // Un tercio para la ficha: lo justo para que el título
                    // entre en dos líneas y la portada se vea grande, sin
                    // quitarle columnas a los episodios.
                    width: (MediaQuery.sizeOf(context).width * 0.34)
                        .clamp(280.0, 460.0),
                    child: _Ficha(c: c, tag: tag),
                  ),
                  SizedBox(width: overscan),
                  Expanded(child: _Episodios(c: c, tag: tag)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// El panel de la izquierda: portada, título, datos y acciones.
class _Ficha extends StatefulWidget {
  const _Ficha({required this.c, this.tag});

  final DetailPageController c;
  final String? tag;

  @override
  State<_Ficha> createState() => _FichaState();
}

class _FichaState extends State<_Ficha> {
  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final tag = widget.tag;
    // ── Sin scroll: el panel ENTRA siempre ──────────────────────────────
    //
    // Antes era desplazable, y con el mando eso no servía: adentro solo hay
    // dos botones enfocables, así que el foco saltaba de uno al otro sin
    // mover el scroll — la portada quedaba a la vista pero no había forma de
    // llegar a ella ni de recuperar lo que quedaba cortado.
    //
    // Ahora la portada se encoge si hace falta (Flexible) y la sinopsis se
    // corta con puntos suspensivos, así que todo el panel entra en pantalla
    // sin desplazar nada. En un televisor eso es lo correcto: se lee de un
    // vistazo, no bajando.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      // Centrado en el alto disponible: el panel es más corto que la
      // pantalla, y anclado arriba dejaba un hueco grande debajo del último
      // botón mientras la portada quedaba chica arriba.
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
          // La portada se encoge si el panel no entra, en vez de empujar
          // el resto fuera de pantalla. Centrada y a todo el ancho del
          // panel: es lo primero que se mira al abrir la ficha, y pegada a
          // la izquierda con el resto del panel más ancho quedaba chica y
          // descolgada.
          if (c.portada != null)
            Flexible(
              child: Center(
                child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: AspectRatio(
                  // La proporción REAL de las portadas de esta extensión (ver
                  // DetailPageController.portadaProporcion): con 2:3 fijo, las
                  // extensiones que publican fotogramas apaisados salían
                  // recortadas por los costados.
                  aspectRatio: c.portadaApaisada ? 16 / 9 : c.portadaProporcion,
                  child: CacheNetWorkImagePic(
                    c.portada!,
                    headers: c.portadaHeaders,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 18),
          Text(
            c.detail?.title ?? '',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 26,
              height: 1.2,
              fontWeight: FontWeight.w800,
              color: HomeTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          _Datos(c: c),
          const SizedBox(height: 18),
          // Las acciones, una debajo de otra y a todo el ancho: en TV el
          // foco se mueve en línea recta, y una fila de botones chicos
          // obliga a cruzar de a uno para llegar al último.
          DetailContinuePlay(tag: tag),
          const SizedBox(height: 10),
          DetailFavoriteButton(tag: tag),
          const SizedBox(height: 18),
          if ((c.detail?.desc ?? '').trim().isNotEmpty)
            Text(
              c.detail!.desc!.trim(),
              // Acotada a propósito.
              //
              // Este panel no se puede desplazar con el mando: adentro solo
              // hay dos botones enfocables, y el foco salta de uno al otro
              // sin mover el scroll — así que una sinopsis larga quedaba
              // cortada abajo sin forma de seguir leyéndola.
              //
              // Con un tope, entra entera en pantalla y se lee de un
              // vistazo, que es como se lee a tres metros. Las sinopsis
              // largas se cortan con puntos suspensivos: en un televisor
              // nadie va a leer quince líneas de todos modos.
              maxLines: 8,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: HomeTheme.textMuted,
              ),
            ),
      ],
    );
  }
}

/// La línea de datos: extensión, tipo y estado de publicación.
class _Datos extends StatelessWidget {
  const _Datos({required this.c});

  final DetailPageController c;

  @override
  Widget build(BuildContext context) {
    final estado = c.detail?.status;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (c.extension?.name != null)
          Text(
            c.extension!.name,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: HomeTheme.accentPink,
            ),
          ),
        if (estado != null && estado.isNotEmpty) _pastilla(_estado(estado)),
        for (final genero in (c.detail?.genres ?? const <String>[]).take(3))
          _pastilla(genero),
      ],
    );
  }

  /// El estado que manda la extensión ('ongoing' | 'completed' | ...) en el
  /// idioma de la app. Si llega uno que no conocemos se muestra tal cual:
  /// mejor un texto en inglés que un hueco.
  String _estado(String bruto) => switch (bruto.toLowerCase()) {
        'ongoing' => 'home.estado.emision'.i18n,
        'completed' => 'home.estado.finalizado'.i18n,
        _ => bruto,
      };

  Widget _pastilla(String texto) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: HomeTheme.border),
        ),
        child: Text(
          texto,
          style: TextStyle(fontSize: 12.5, color: HomeTheme.textMuted),
        ),
      );
}

/// El panel de la derecha: los episodios, con su título arriba.
class _Episodios extends StatelessWidget {
  const _Episodios({required this.c, this.tag});

  final DetailPageController c;
  final String? tag;

  @override
  Widget build(BuildContext context) {
    final grupos = c.detail?.episodes;
    if (grupos == null || grupos.isEmpty) {
      return Center(
        child: Text(
          'common.no-data'.i18n,
          style: TextStyle(color: HomeTheme.textMuted, fontSize: 15),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 12, bottom: 12),
          child: Text(
            c.type == ExtensionType.bangumi
                ? 'video.episodes'.i18n
                : 'video.chapters'.i18n,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: HomeTheme.textPrimary,
            ),
          ),
        ),
        // La lista de siempre: ya trae el selector de grupos (temporadas),
        // el orden, la marca del que estás viendo y —en TV— el foco por
        // episodio. No hace falta nada nuevo.
        Expanded(child: DetailEpisodes(tag: tag)),
      ],
    );
  }
}
