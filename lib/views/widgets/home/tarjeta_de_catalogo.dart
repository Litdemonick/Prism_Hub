import 'package:flutter/material.dart';
import 'package:prismhub/utils/breakpoints.dart';
import 'package:prismhub/views/widgets/home/rejilla_de_tarjetas.dart';
import 'package:prismhub/views/widgets/cache_network_image.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/home/panel_info_hover.dart';
import 'package:prismhub/utils/platform_tv.dart';

/// Si el aparato se maneja con el dedo.
///
/// Es lo mismo que mira el Inicio (`home_page.dart`): los dos apuntan a la
/// única definición, en `platform_tv.dart`. Antes estaba escrita acá y allá
/// con el mismo cuerpo copiado, que es como se termina cambiando una sola de
/// las dos.
bool get _esTactil => esPantallaTactil;

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
    this.tvFoco = false,
    this.tituloEnUnaLinea = false,
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

  /// El D-pad de TV tiene el foco en esta tarjeta AHORA MISMO.
  ///
  /// ── Por qué es un parámetro y no algo que la tarjeta detecte sola ────
  ///
  /// El resaltado (escala + sombra) de acá adentro está apagado a
  /// propósito en TV — lo pone `FocusableCard`, que envuelve esta tarjeta
  /// por fuera, y tenerlo en los dos lugares a la vez ya se probó y se
  /// sacó (ver `resaltada` más abajo: dos escalas encimadas rompían el
  /// recorte). Pero el PANEL de info (título/fecha/descripción, lo mismo
  /// que ya se ve al pasar el mouse en PC) nunca tenía forma de aparecer
  /// en TV con ese apagado — quedaba con el marco de foco puesto pero sin
  /// ninguna de las dos cosas que ese marco anuncia. `FocusableCard` sabe
  /// cuándo tiene el foco (es quien lo maneja); pasándoselo acá, la
  /// tarjeta puede mostrar el panel SIN prender de nuevo su propia
  /// escala/sombra.
  final bool tvFoco;

  /// Si debajo de la portada va UNA sola línea de título, sin metadatos.
  /// Ver [altoDeUnaLineaDeAncho].
  final bool tituloEnUnaLinea;

  /// Ancho a la fuerza, para cuando la tarjeta va en una **grilla**.
  ///
  /// En una fila horizontal cada tarjeta elige su ancho por breakpoint y punto.
  /// En una grilla no puede: el ancho lo manda la celda —cuántas columnas
  /// entran y cuánto margen hay— y si la tarjeta usara el suyo quedaría
  /// desalineada de la cuadrícula o se saldría de la celda.
  final double? ancho;

  /// El ancho ideal de una tarjeta de catálogo, EN ESTA pantalla.
  ///
  /// Fuera de televisor sale del breakpoint y punto: el ancho en píxeles y la
  /// distancia a la que se mira van juntos, así que un número por tamaño
  /// alcanza. Esos peldaños están subidos respecto de 126/150/176/196 por un
  /// pedido explícito de tarjetas más grandes en las filas de Inicio.
  ///
  /// ── En televisor no alcanza un número ───────────────────────────────────
  ///
  /// Acá había 320 px fijos, con este argumento: un televisor de 1280 cae en
  /// `enorme` y con 240 px entran cinco columnas, que desde el sillón son
  /// cinco estampillas.
  ///
  /// El argumento era correcto y el arreglo no: los televisores le declaran a
  /// Flutter anchos lógicos muy distintos —960, 1280, 1920— y todos se miran
  /// desde la misma distancia. Con 320 fijos, el televisor donde se mide
  /// entraba en DOS columnas, con las portadas ocupando la pantalla entera y
  /// sin ver la fila de abajo ni la de arriba. Reportado con foto.
  ///
  /// Entonces en televisor el ancho sale de dividir la pantalla, con la misma
  /// cuenta que usa la grilla (`RejillaDeTarjetas`) — así una fila horizontal
  /// y una grilla muestran tarjetas del mismo tamaño en la misma pantalla.
  ///
  /// Recibe el `BuildContext` y no un `Ancho` justamente por eso: en televisor
  /// hace falta el ancho REAL, no el peldaño en el que cae.
  static double anchoPara(BuildContext context) {
    final pantalla = MediaQuery.sizeOf(context).width;
    final a = Ancho.desde(pantalla);
    if (!PlatformTv.esTelevisionSync) {
      return RejillaDeTarjetas.anchoIdealFueraDeTv(a);
    }
    return RejillaDeTarjetas.calcular(
      disponible: pantalla - _alrededorEnTv,
      separacion: 20,
      televisor: true,
      pantalla: a,
    ).ancho;
  }

  /// Lo que en televisor NO es franja de tarjetas: la barra lateral contraída
  /// (64–80 según la pantalla), el aire que la separa del contenido y los
  /// márgenes de `HomeTheme.margenTv`.
  ///
  /// Es una estimación a propósito. Las grillas miden su franja de verdad con
  /// un `LayoutBuilder`; las filas horizontales no pueden —el ancho de la
  /// tarjeta se necesita ANTES, para reservar el alto de la fila— y una
  /// estimación de más acá solo hace la tarjeta unos píxeles más angosta, que
  /// no rompe nada.
  static const _alrededorEnTv = 170.0;

  static double altoPortadaPara(BuildContext context) =>
      anchoPara(context) * 3 / 2;

  /// Portada + aire + dos líneas de título + una de subtítulo.
  ///
  /// Se calcula acá y no en la fila para que las dos no puedan discrepar: si
  /// la fila reservara menos de lo que la tarjeta mide, se recorta el texto.
  static double altoTotalPara(BuildContext context) =>
      altoTotalDeAncho(anchoPara(context));

  /// Lo mismo, pero partiendo de un ancho ya decidido — el de una celda.
  static double altoTotalDeAncho(double ancho) => ancho * 3 / 2 + 8 + 36 + 16;

  /// La variante de UNA línea, sin la fila de metadatos.
  ///
  /// ── Por qué existe ────────────────────────────────────────────────────
  ///
  /// La tarjeta normal reserva dos líneas de título más una de metadatos:
  /// cincuenta y dos puntos de texto debajo de cada portada. En una grilla
  /// de escritorio eso está bien —hay sitio y el dato ayuda—, pero en las
  /// filas de un televisor ese espacio de más se multiplica por fila y
  /// termina empujando la siguiente fuera de la pantalla: se veía el
  /// principio de la de abajo con el título ya cortado por el borde.
  ///
  /// Reportado en vivo: «las de abajo, la que sigue, ese título no se ve
  /// porque ya es el borde; corregí esas proporciones, esos espacios».
  static double altoDeUnaLineaDeAncho(double ancho) => ancho * 3 / 2 + 6 + 19;

  @override
  State<TarjetaDeCatalogo> createState() => _TarjetaDeCatalogoState();
}

class _TarjetaDeCatalogoState extends State<TarjetaDeCatalogo> {
  Color get _acento => widget.acento ?? HomeTheme.accentPink;

  bool _encima = false;

  /// En pantalla táctil, el panel se revela con toque LARGO — pedido
  /// explícito: "si se presiona sale la info y luego al tocarla entra al
  /// detalle; si solo se toca se entra directamente". El toque simple
  /// sigue yendo derecho a la ficha (ver el `onTap` de abajo); esto es
  /// solo para quien quiere espiar el título/fecha/descripción antes de
  /// decidir, sin que haga falta ese paso siempre.
  bool _abierto = false;

  bool get _hayPanel =>
      widget.fecha != null ||
      widget.descripcion != null ||
      widget.encabezado != null;

  @override
  Widget build(BuildContext context) {
    final ancho = widget.ancho ?? TarjetaDeCatalogo.anchoPara(context);
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
    // Con mouse, el hover ya lo revela sin gastar ningún click. Sin mouse,
    // el toque LARGO lo revela (`_abierto`, ver `onLongPress` abajo) — el
    // toque simple sigue yendo derecho a la ficha.
    final panelVisible =
        _hayPanel && (widget.tvFoco || (conMouse ? _encima : _abierto));
    // En TV la tarjeta NO se resalta sola.
    //
    // `_encima` es el hover del mouse, y en TV el resaltado lo pone
    // FocusableCard, que la envuelve por fuera. Con los dos a la vez había
    // DOS escalas encimadas (esta de 1.04 y la del foco): la portada crecía
    // más que el marco y se salía por los bordes — el marco quedaba
    // dibujado "por dentro" de la imagen. Reportado en vivo.
    final resaltada = !PlatformTv.esTelevisionSync && (_encima || _abierto);

    final tarjeta = SizedBox(
      width: ancho,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _encima = true),
        onExit: (_) => setState(() => _encima = false),
        child: GestureDetector(
          // Con mouse, tocar abre directo: el panel ya se ve solo con pasar
          // por encima.
          //
          // Sin mouse (celular/tablet), el toque TAMBIÉN abre directo —
          // pedido explícito: "en Android tocar la card debe ir de una vez
          // al detalle, no como Windows que selecciona y hay que volver a
          // tocar". Antes acá el primer toque solo ALTERNABA el panel (había
          // que tocar de nuevo «Ver detalles» para entrar) — un paso de más
          // que tenía sentido con mouse (el panel ya se ve con el hover, sin
          // gastar ningún toque) pero no con el dedo, donde no hay ningún
          // "pasar por encima" previo: el primer contacto YA es la intención
          // de abrir.
          //
          // ── Y sin `onTap` propio, la tarjeta no atiende el toque ──────────
          //
          // Esto es lo que pasa en televisor: ahí el toque lo maneja el
          // FocusableCard que la envuelve por fuera, y por eso llega sin
          // `onTap`. Devolviendo null, el toque sigue de largo hasta quien sí
          // sabe qué hacer con él.
          onTap: widget.onTap,
          // Solo en pantalla táctil, y solo si hay algo que mostrar: un
          // toque largo revela el panel sin navegar — pedido explícito. Con
          // mouse no hace falta (`onHover` ya lo muestra) y en TV el gesto
          // no existe.
          onLongPress: (!conMouse && _hayPanel)
              ? () => setState(() => _abierto = true)
              : null,
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
                    // Son tres capas, no una: la profunda despega la tarjeta
                    // del fondo, la cercana le da peso justo debajo, y el halo
                    // de color la enciende. Con una sola sombra la tarjeta o
                    // queda plana o queda de neón.
                    //
                    // ── Por qué el alcance de las tres está topado a ~13px ──
                    //
                    // Esta misma tarjeta se usa en filas horizontales de Inicio
                    // con solo 14px de separación entre una y la siguiente
                    // (home_page_windows.dart, separatorBuilder). Un halo de
                    // blur 40 + spread 6 (~46px de alcance real) se mete de
                    // sobra en el hueco y sigue de largo hacia la tarjeta de al
                    // lado — que, al pintarse DESPUÉS en la lista, lo tapa de
                    // golpe contra su propio borde. Eso se veía como una línea
                    // vertical recta donde la sombra "se corta", justo del lado
                    // en el que la vecina se pinta encima (reportado en vivo:
                    // pasaba de un lado sí y del otro no, según el orden de
                    // pintado). Manteniendo cada capa por debajo del hueco más
                    // chico que existe hoy, la sombra siempre termina de
                    // apagarse sola antes de tocar a la tarjeta de al lado.
                    boxShadow: resaltada
                        ? [
                            const BoxShadow(
                              color: Color(0x8A000000),
                              blurRadius: 16,
                              offset: Offset(0, 8),
                            ),
                            const BoxShadow(
                              color: Color(0x66000000),
                              blurRadius: 8,
                              offset: Offset(0, 3),
                            ),
                            BoxShadow(
                              color: _acento.withValues(alpha: 0.24),
                              blurRadius: 11,
                            ),
                          ]
                        : const [],
                  ),
                  child: ClipRRect(
                    borderRadius: radio,
                    // ── El pelo de gris en un borde al agrandarse ─────────
                    //
                    // Reportado en vivo: al pasar el mouse (cuando esta caja
                    // ya está adentro de un AnimatedScale a 1.04) aparecía
                    // una línea fina en UN borde —abajo, arriba o a la
                    // derecha según la tarjeta, nunca el mismo en todas—.
                    // Es un problema conocido de Flutter: escalar un
                    // ClipRRect con `Transform` (que es lo que usa
                    // AnimatedScale por dentro) redondea el recorte a
                    // píxeles de pantalla de forma independiente del
                    // contenido, así que en ciertos tamaños el contenido
                    // queda un pixel más chico que el hueco recortado — el
                    // fondo detrás de la tarjeta se asoma por esa rendija.
                    // Se agranda el contenido un poco de más (2%) para que
                    // siempre desborde el recorte en vez de quedarse corto,
                    // sea cual sea el redondeo.
                    child: Transform.scale(
                      scale: 1.02,
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
                                // Sin esto, el panel invisible se sigue
                                // comiendo los toques del póster.
                                child: IgnorePointer(
                                  ignoring: !panelVisible,
                                  // ── En TV el panel NO tapa la portada ───
                                  //
                                  // Reportado en vivo con foto: la tarjeta
                                  // enfocada "pierde toda la imagen". El
                                  // panel cubre el póster entero con un
                                  // degradado casi opaco — con mouse eso
                                  // está bien (uno pasa por arriba a
                                  // propósito para leer, y se va al correr
                                  // el puntero), pero con un mando la
                                  // tarjeta enfocada es justamente la que
                                  // se está mirando: taparla entera deja al
                                  // usuario sin ver qué eligió.
                                  //
                                  // Pegado abajo y midiendo lo que necesita.
                                  //
                                  // Antes se le forzaba el 52 % del alto de la
                                  // tarjeta. Con un título de una línea eso
                                  // dejaba un hueco enorme entre el título y
                                  // «Ver detalles», y el panel se veía cortado
                                  // por la mitad — reportado con foto.
                                  //
                                  // Midiendo su contenido ocupa lo justo, y
                                  // con el degradado arrancando transparente
                                  // no hay ningún borde que se note.
                                  child: PlatformTv.esTelevisionSync
                                      ? Align(
                                          alignment: Alignment.bottomCenter,
                                          child: _panel(compacto: true),
                                        )
                                      : _panel(),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: widget.tituloEnUnaLinea ? 6 : 8),
              if (widget.tituloEnUnaLinea)
                SizedBox(
                  height: 19,
                  child: Text(
                    widget.titulo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: HomeTheme.textPrimary,
                    ),
                  ),
                )
              else ...[
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
            ],
          ),
        ),
      ),
    );
    // ── La tarjeta, en su propia capa ───────────────────────────────────
    //
    // Lo caro de acá es la portada, que es una imagen decodificada y es
    // justo lo que MENOS cambia. Sin un límite de repintado, cualquier cosa
    // que se mueva en la tarjeta —el panel que aparece al pasar el mouse, la
    // escala, el marco de foco en televisor— obliga a repintar también todo
    // lo que la rodea: en una fila, las tarjetas vecinas.
    //
    // Con el límite, la portada se compone como una textura ya lista y lo
    // único que se rehace es lo que de verdad cambió.
    return RepaintBoundary(child: tarjeta);
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
  /// El contenido vive en `PanelInfoHover` — compartido con `_TarjetaGrande`
  /// del carrusel de Inicio (`home_page_android.dart`), pedido explícito:
  /// "que en el carrusel también salga al poner el mouse la selección como
  /// en las otras cards, reutiliza eso". Una mejora acá vale para las dos.
  Widget _panel({bool compacto = false}) {
    return PanelInfoHover(
      titulo: widget.titulo,
      encabezado: widget.encabezado,
      fecha: widget.fecha,
      descripcion: widget.descripcion,
      acento: widget.acento,
      onTap: widget.onTap,
      compacto: compacto,
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
