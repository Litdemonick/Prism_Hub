import 'dart:io';

import 'package:flutter/material.dart';
import 'package:prismhub/utils/breakpoints.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/views/widgets/cache_network_image.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';

/// Si el aparato se maneja con el dedo.
///
/// Es lo mismo que mira el Inicio (`home_page.dart`), y va por sistema
/// operativo a propósito: el ancho de la ventana no dice si hay mouse.
bool get _esTactil => Platform.isAndroid || Platform.isIOS;

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
    this.acento,
    this.encabezado,
    this.fecha,
    this.descripcion,
    this.duracion,
    this.ancho,
  });

  final String titulo;
  final String? subtitulo;
  final String? portada;
  final Map<String, String>? cabeceras;
  final VoidCallback? onTap;
  /// En null usa el acento del tema. Ver HomeHeroBanner.gradient.
  final Color? acento;

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

  /// Ancho a la fuerza, para cuando la tarjeta va en una **grilla**.
  ///
  /// En una fila horizontal cada tarjeta elige su ancho por breakpoint y punto.
  /// En una grilla no puede: el ancho lo manda la celda —cuántas columnas
  /// entran y cuánto margen hay— y si la tarjeta usara el suyo quedaría
  /// desalineada de la cuadrícula o se saldría de la celda.
  final double? ancho;

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
  static double altoTotalPara(Ancho a) => altoTotalDeAncho(anchoPara(a));

  /// Lo mismo, pero partiendo de un ancho ya decidido — el de una celda.
  static double altoTotalDeAncho(double ancho) => ancho * 3 / 2 + 8 + 36 + 16;

  @override
  State<TarjetaDeCatalogo> createState() => _TarjetaDeCatalogoState();
}

class _TarjetaDeCatalogoState extends State<TarjetaDeCatalogo> {
  Color get _acento => widget.acento ?? HomeTheme.accentPink;

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
    final ancho = widget.ancho ?? TarjetaDeCatalogo.anchoPara(a);
    final altoPortada = ancho * 3 / 2;
    final radio = BorderRadius.circular(8);

    // ── Si hay mouse lo decide el APARATO, no el ancho de la ventana ──────
    //
    // Estaba en `a.alMenosAmplio`, o sea que se preguntaba por el tamaño. En
    // PC con la ventana achicada eso daba «no hay mouse», y la tarjeta pasaba
    // al comportamiento de pantalla táctil: el primer clic abría el panel y
    // había que dar un segundo clic en «Ver detalles» para entrar a la ficha.
    // A pantalla completa abría de una. La misma tarjeta, el mismo mouse, dos
    // comportamientos según cómo estuviera la ventana.
    //
    // El ancho sirve para decidir cuántas tarjetas entran; para saber si hay
    // con qué «pasar por encima» hay que preguntar por el aparato.
    final conMouse = !_esTactil;
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
                    // ── La sombra: difusa, nunca un contorno ──────────────
                    //
                    // Antes el halo iba con poco desenfoque y una expansión
                    // NEGATIVA, y eso lo pegaba al borde: se leía como una
                    // línea de color alrededor de la tarjeta en vez de como
                    // luz. Ahora el desenfoque es grande y la expansión
                    // positiva, así el color se va apagando hacia afuera y no
                    // deja ningún filo.
                    //
                    // Y son tres capas, no una: la profunda despega la tarjeta
                    // del fondo, la cercana le da peso justo debajo, y el halo
                    // de color la enciende. Con una sola sombra la tarjeta o
                    // queda plana o queda de neón.
                    boxShadow: resaltada
                        ? [
                            const BoxShadow(
                              color: Color(0x8A000000),
                              blurRadius: 34,
                              spreadRadius: 2,
                              offset: Offset(0, 14),
                            ),
                            const BoxShadow(
                              color: Color(0x66000000),
                              blurRadius: 12,
                              offset: Offset(0, 4),
                            ),
                            BoxShadow(
                              color: _acento.withValues(alpha: 0.22),
                              blurRadius: 40,
                              spreadRadius: 6,
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
                    color: resaltada ? _acento : HomeTheme.textPrimary,
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
                        style: TextStyle(
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
  ///
  /// Es un DEGRADADO y no un color plano: arriba deja ver un poco la portada y
  /// hacia abajo se cierra para que el texto se lea. Un rectángulo opaco tapaba
  /// la imagen por completo y se veía como un bloque pegado encima — justo lo
  /// que se quiere evitar. Así el panel se siente parte de la tarjeta.
  Widget _panel(double ancho) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xA6101019), Color(0xE0101019), Color(0xF2101019)],
          stops: [0.0, 0.45, 1.0],
        ),
      ),
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
                style: TextStyle(
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
                  Icon(Icons.calendar_today_rounded,
                      size: 11, color: HomeTheme.textMuted),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      widget.fecha!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
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
                        size: 17, color: _acento),
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
                          color: _acento,
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

  /// La portada, llenando la tarjeta.
  ///
  /// `cover` a secas: la imagen ocupa el marco entero y lo que sobra se
  /// recorta. Se probó dibujarla dos veces —una apagada de fondo y otra
  /// entera adelante— para que las portadas de forma rara no perdieran nada, y
  /// se volvió atrás **a pedido explícito**: dejaba una franja de fondo visible
  /// dentro de la tarjeta y se veía peor que el recorte.
  ///
  /// La contra queda dicha: una portada que no venga en 2:3 pierde los bordes.
  /// La gran mayoría vienen en 2:3 y entran justas.
  Widget _portada(double ancho, double alto) {
    final url = widget.portada;
    if (url == null || url.isEmpty) return _sinPortada();
    // ── Decodificar al tamaño que se VE, no al que vino ────────────────
    //
    // Una portada llega en 600×900 o más. Sin esto, cada una se decodifica
    // entera y después se dibuja en una celda de 100 píxeles de ancho: se paga
    // el mapa de bits completo en memoria y en GPU para tirar el 95%.
    //
    // En el Home de celular hay seis por página y varias filas cerca de la
    // pantalla, así que se multiplica — y ahí es donde el desplazamiento se
    // sentía pesado.
    //
    // Va por la densidad real del aparato: en una pantalla 3x, 100 píxeles
    // lógicos son 300 de verdad, y decodificar menos que eso se vería borroso.
    final cacheWidth =
        (ancho * MediaQuery.devicePixelRatioOf(context)).ceil().clamp(1, 4096);
    return CacheNetWorkImagePic(
      cacheWidth: cacheWidth,
      url,
      width: ancho,
      height: alto,
      fit: BoxFit.cover,
      headers: widget.cabeceras,
      placeholder: _mientrasCarga(),
      fallback: _sinPortada(),
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
  Widget _mientrasCarga() => DecoratedBox(
        decoration: BoxDecoration(color: HomeTheme.cardSurface),
        child: const Opacity(
          opacity: 0.55,
          child: Image(
            image: AssetImage('assets/carddefaultoffline.png'),
            fit: BoxFit.cover,
          ),
        ),
      );

  /// Sin portada NO se deja un hueco negro: se usa el arte de respaldo de la
  /// app. Un hueco en medio de una fila de pósters parece un error de carga;
  /// esto parece una tapa sin arte, que es lo que realmente es.
  ///
  /// Antes era un degradado con la inicial del título, propio de esta
  /// tarjeta. Se cambia por `carddefaultoffline.png` para que sea la MISMA
  /// imagen de respaldo en toda la app —la ficha, el lector, las tarjetas del
  /// resto del Home— y no una variante distinta solo acá.
  Widget _sinPortada() => const Image(
        image: AssetImage('assets/carddefaultoffline.png'),
        fit: BoxFit.cover,
      );
}
