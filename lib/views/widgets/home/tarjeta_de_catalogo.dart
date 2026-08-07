import 'package:flutter/material.dart';
import 'package:prismhub/utils/breakpoints.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/views/widgets/cache_network_image.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';

/// La tarjeta del catálogo: **póster limpio, sin marco**.
///
/// ── Las reglas del diseño ─────────────────────────────────────────────────
///
///   · **Sin borde y sin fondo.** El póster ya tiene su propio marco: el borde
///     de la imagen. Un recuadro alrededor agrega una segunda línea que pelea
///     con la primera y ensucia la grilla.
///   · **El texto va AFUERA del póster**, debajo. Encima obliga a oscurecer la
///     imagen para que se lea, y entonces la portada —lo que hace elegir— se
///     ve peor.
///   · **Todas del mismo tamaño, siempre.** El título ocupa dos líneas tenga
///     una o tenga dos, y el panel de detalle NO agranda la tarjeta: se dibuja
///     ADENTRO del póster. Si una tarjeta creciera al pasarle el mouse,
///     empujaría a las vecinas y la fila entera bailaría.
///   · **2:3**, la proporción real de un póster.
///
/// ── El panel al pasar el mouse ────────────────────────────────────────────
///
/// Sobre el póster, no en lugar de la tarjeta: título, fecha, descripción y el
/// botón. Solo en escritorio — en un teléfono no hay mouse, y ahí tocar ya
/// abre la ficha, que muestra todo eso completo.
///
/// Los tres datos del panel son OPCIONALES a propósito. Hoy `latest()` de las
/// extensiones devuelve título, dirección y portada; fecha, descripción y
/// duración no siempre vienen. Cada uno se dibuja solo si está, y el panel se
/// acomoda: nunca queda un hueco reservado para algo que no llegó.
class TarjetaDeCatalogo extends StatefulWidget {
  const TarjetaDeCatalogo({
    super.key,
    required this.titulo,
    this.subtitulo,
    this.portada,
    this.cabeceras,
    this.onTap,
    this.acento = HomeTheme.accentPink,
    this.encabezado,
    this.fecha,
    this.descripcion,
    this.duracion,
  });

  final String titulo;
  final String? subtitulo;
  final String? portada;
  final Map<String, String>? cabeceras;
  final VoidCallback? onTap;
  final Color acento;

  /// Arriba de todo en el panel, chiquito: de dónde viene (la extensión, la
  /// serie a la que pertenece el episodio).
  final String? encabezado;

  /// Cuándo salió. Se muestra tal cual venga — las extensiones lo dan de
  /// formas distintas («hace 2 días», una fecha) y normalizarlo acá sería
  /// inventar precisión que no hay.
  final String? fecha;

  final String? descripcion;

  /// Cuánto dura, en minutos. Se muestra SIEMPRE, no solo al pasar el mouse:
  /// es de las cosas que más pesan para decidir si lo abrís ahora o después.
  final int? duracion;

  /// El ancho del póster, según cuánto lugar hay.
  ///
  /// Va por ANCHO DE PANTALLA y no por sistema operativo: una tablet y un
  /// teléfono son el mismo `Platform`, y una ventana de escritorio achicada a
  /// la mitad se parece más a la tablet. Además acompaña en vivo cuando el
  /// usuario arrastra el borde de la ventana, cosa que el sistema operativo
  /// nunca puede contestar.
  static double anchoPara(Ancho a) => a.elegir(
        compacto: 126,
        medio: 150,
        amplio: 176,
        enorme: 196,
      );

  static double altoPortadaPara(Ancho a) => anchoPara(a) * 3 / 2;

  /// Portada + aire + dos líneas de título + una de subtítulo.
  ///
  /// Se calcula acá y no en la fila para que las dos no puedan discrepar: si
  /// la fila reservara menos de lo que la tarjeta mide, se recorta el texto.
  static double altoTotalPara(Ancho a) => altoPortadaPara(a) + 8 + 36 + 16;

  @override
  State<TarjetaDeCatalogo> createState() => _TarjetaDeCatalogoState();
}

class _TarjetaDeCatalogoState extends State<TarjetaDeCatalogo> {
  bool _encima = false;

  /// En pantalla táctil no hay «pasar por encima», así que el primer toque
  /// muestra el panel y el segundo abre. Es la forma de que el usuario de
  /// celular vea la fecha y la descripción sin tener que entrar a la ficha —
  /// justo lo que el mouse resuelve solo en escritorio.
  bool _abierto = false;

  bool get _hayPanel =>
      widget.fecha != null ||
      widget.descripcion != null ||
      widget.encabezado != null;

  @override
  Widget build(BuildContext context) {
    final a = Ancho.de(context);
    final ancho = TarjetaDeCatalogo.anchoPara(a);
    final altoPortada = TarjetaDeCatalogo.altoPortadaPara(a);
    final radio = BorderRadius.circular(8);

    final conMouse = a.alMenosAmplio;
    // Se muestra por mouse en escritorio y por toque en celular.
    final panelVisible = _hayPanel && (conMouse ? _encima : _abierto);
    final resaltada = _encima || _abierto;

    return SizedBox(
      width: ancho,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _encima = true),
        onExit: (_) => setState(() => _encima = false),
        child: GestureDetector(
          // Con mouse, tocar abre directo: el panel ya se ve solo con pasar
          // por encima.
          //
          // Sin mouse el toque ALTERNA el panel — lo abre y lo cierra. Antes el
          // segundo toque abría la ficha, así que una vez abierto el panel no
          // había forma de sacárselo de encima sin entrar a algún lado. Ahora
          // lo único que abre la ficha es el botón «Ver detalles», que para eso
          // está.
          onTap: () {
            if (conMouse || !_hayPanel) {
              widget.onTap?.call();
              return;
            }
            setState(() => _abierto = !_abierto);
          },
          behavior: HitTestBehavior.opaque,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Crece un poco, y nada más: ni sombras ni bordes que aparecen,
              // que es lo que ensucia la fila cuando el mouse la recorre.
              AnimatedScale(
                scale: resaltada ? 1.04 : 1.0,
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOut,
                // La sombra va AFUERA del recorte: adentro, el ClipRRect la
                // corta contra el borde del póster y no se ve nada.
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  decoration: BoxDecoration(
                    borderRadius: radio,
                    boxShadow: resaltada
                        ? [
                            // Dos sombras: una oscura que despega la tarjeta
                            // del fondo, y un halo del color de acento que le
                            // da la vida. Con una sola, o queda plana o queda
                            // de neón.
                            const BoxShadow(
                              color: Color(0x99000000),
                              blurRadius: 18,
                              offset: Offset(0, 8),
                            ),
                            BoxShadow(
                              color: widget.acento.withValues(alpha: 0.34),
                              blurRadius: 22,
                              spreadRadius: -2,
                            ),
                          ]
                        : const [],
                  ),
                  child: ClipRRect(
                    borderRadius: radio,
                    child: SizedBox(
                      width: ancho,
                      height: altoPortada,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _portada(ancho, altoPortada),
                          if (widget.duracion != null) _insigniaDeDuracion(),
                          if (_hayPanel)
                            AnimatedOpacity(
                              opacity: panelVisible ? 1 : 0,
                              duration: const Duration(milliseconds: 160),
                              // Sin esto, el panel invisible se sigue comiendo
                              // los toques del póster.
                              child: IgnorePointer(
                                ignoring: !panelVisible,
                                child: _panel(ancho),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Alto fijo para dos líneas: ver la regla de arriba.
              SizedBox(
                height: 36,
                child: Text(
                  widget.titulo,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.32,
                    fontWeight: FontWeight.w600,
                    color: resaltada ? widget.acento : HomeTheme.textPrimary,
                  ),
                ),
              ),
              SizedBox(
                height: 16,
                child: widget.subtitulo == null
                    ? null
                    : Text(
                        widget.subtitulo!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: HomeTheme.textMuted,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Cuánto dura, abajo a la derecha del póster.
  Widget _insigniaDeDuracion() {
    return Positioned(
      right: 6,
      bottom: 6,
      child: DecoratedBox(
        decoration: BoxDecoration(
          // Bien opaco: va encima de la portada, que puede ser de cualquier
          // color. Con un fondo translúcido se vuelve ilegible sobre imágenes
          // claras.
          color: const Color(0xE6000000),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Text(
            '${widget.duracion}m',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  /// El panel que aparece al pasar el mouse, DENTRO del póster.
  Widget _panel(double ancho) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xF00E0E16)),
      child: Padding(
        padding: const EdgeInsets.all(11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.encabezado != null) ...[
              Text(
                widget.encabezado!.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 9.5,
                  letterSpacing: 0.9,
                  fontWeight: FontWeight.w700,
                  color: HomeTheme.textMuted,
                ),
              ),
              const SizedBox(height: 6),
            ],
            Text(
              widget.titulo,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.25,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            if (widget.fecha != null) ...[
              const SizedBox(height: 5),
              Row(
                children: [
                  const Icon(Icons.calendar_today_rounded,
                      size: 11, color: HomeTheme.textMuted),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      widget.fecha!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: HomeTheme.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (widget.descripcion != null) ...[
              const SizedBox(height: 8),
              // Expanded y no un alto fijo: la descripción usa lo que sobre
              // después del título y la fecha. Con alto fijo, un título de tres
              // líneas la empujaba fuera del panel.
              Expanded(
                child: Text(
                  widget.descripcion!,
                  overflow: TextOverflow.fade,
                  style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.35,
                    color: Color(0xFFC9C4D4),
                  ),
                ),
              ),
            ] else
              const Spacer(),
            const SizedBox(height: 6),
            // El ÚNICO que abre la ficha cuando el panel está abierto. Tocar
            // en cualquier otro lado lo cierra, así el panel no es una trampa.
            //
            // GestureDetector propio y opaco: sin esto el toque se lo llevaba
            // la tarjeta de atrás y el botón no hacía nada.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => widget.onTap?.call(),
              child: Padding(
                // Aire de sobra alrededor del texto: es el objetivo más chico
                // del panel y en un teléfono tiene que poder tocarse sin
                // apuntar.
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(Icons.play_arrow_rounded,
                        size: 17, color: widget.acento),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'home.view-detail'.i18n.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          letterSpacing: 0.6,
                          fontWeight: FontWeight.w800,
                          color: widget.acento,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// La portada, **entera y sin recortar**.
  ///
  /// ── Por qué algunas se veían cortadas ─────────────────────────────────────
  ///
  /// Con `cover` la imagen llena el marco y lo que sobra se tira. Eso está
  /// perfecto para una portada 2:3, que entra justa — y esas se veían bien.
  /// Pero cada extensión entrega la forma que quiere: cuadradas, anchas,
  /// capturas de vídeo. A esas `cover` les comía media imagen, y por eso unas
  /// se veían completas y otras no.
  ///
  /// La solución es la misma que ya usa la ficha: **la imagen dos veces**. Atrás
  /// con `cover` y apagada, para rellenar; adelante con `contain`, entera. Una
  /// portada 2:3 sigue viéndose exactamente igual que antes —tapa el relleno
  /// por completo— y las otras dejan de perder la mitad.
  ///
  /// Sin desenfoque a propósito. La ficha sí lo usa, pero ahí hay UNA imagen; en
  /// una fila hay treinta, y treinta desenfoques es de las formas más caras de
  /// arruinar el desplazamiento. Dibujar dos veces algo que ya está decodificado
  /// no cuesta prácticamente nada.
  Widget _portada(double ancho, double alto) {
    final url = widget.portada;
    if (url == null || url.isEmpty) return _sinPortada(ancho);
    Widget pic(BoxFit fit) => CacheNetWorkImagePic(
          url,
          width: ancho,
          height: alto,
          fit: fit,
          headers: widget.cabeceras,
          placeholder: _mientrasCarga(),
          fallback: _sinPortada(ancho),
        );
    return Stack(
      fit: StackFit.expand,
      children: [
        Opacity(opacity: 0.45, child: pic(BoxFit.cover)),
        pic(BoxFit.contain),
      ],
    );
  }

  /// Lo que se ve mientras la portada baja.
  ///
  /// La carta de respaldo de la app en vez de un rectángulo vacío: una fila de
  /// huecos negros mientras cargan treinta imágenes se lee como que algo se
  /// rompió, y esto se lee como «todavía no llegó».
  ///
  /// `cover` a propósito: la carta tiene su propia forma y acá tiene que llenar
  /// el marco sin dejar franjas — es un relleno, no contenido que haya que ver
  /// entero.
  Widget _mientrasCarga() => const DecoratedBox(
        decoration: BoxDecoration(color: HomeTheme.cardSurface),
        child: Opacity(
          opacity: 0.55,
          child: Image(
            image: AssetImage('assets/carddefaultoffline.png'),
            fit: BoxFit.cover,
          ),
        ),
      );

  /// Sin portada NO se deja un hueco negro: se dibuja un degradado con la
  /// inicial. Un hueco en medio de una fila de pósters parece un error de
  /// carga; esto parece una tapa sin arte, que es lo que realmente es.
  Widget _sinPortada(double ancho) {
    final inicial = widget.titulo.trim().isEmpty
        ? '?'
        : widget.titulo.trim().characters.first.toUpperCase();
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            widget.acento.withValues(alpha: 0.30),
            HomeTheme.cardSurface,
          ],
        ),
      ),
      child: Center(
        child: Text(
          inicial,
          style: TextStyle(
            fontSize: ancho * 0.34,
            fontWeight: FontWeight.w800,
            color: Colors.white.withValues(alpha: 0.22),
          ),
        ),
      ),
    );
  }
}
