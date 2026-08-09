import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';

/// Bloques grises que brillan mientras se espera contenido.
///
/// ── Por qué esto y no una rueda girando ───────────────────────────────────
///
/// Porque una rueda solo dice «esperá». Estos bloques dicen **qué va a
/// aparecer y dónde**: tienen la forma y el lugar exactos de las tarjetas que
/// los van a reemplazar, así que cuando llega el contenido nada se mueve. Con
/// la rueda, en cambio, la pantalla salta entera en el momento en que carga.
///
/// Y se siente más rápido aunque tarde lo mismo, que es la mitad del asunto.
///
/// ── Cuándo NO usarlos ─────────────────────────────────────────────────────
///
/// Cuando ya se sabe que no va a llegar nada. Un esqueleto brillando para
/// siempre es peor que un mensaje de error: el usuario se queda esperando algo
/// que nunca va a venir. Para eso está la línea con el botón de reintentar.
///
/// ── Lo que costaba la primera versión ─────────────────────────────────────
///
/// Dos cosas, y las dos se multiplicaban por cada bloque en pantalla:
///
///   · **Un AnimationController propio.** Con una grilla cargando son diez
///     bloques, más siete de los chips, más los del carrusel: treinta relojes
///     independientes latiendo a la vez, cada uno pidiendo su cuadro.
///   · **Un ShaderMask.** Eso obliga a Flutter a dibujar el bloque en una capa
///     aparte para después aplicarle el degradado — un `saveLayer` por bloque
///     y por cuadro, que es de las operaciones más caras que hay.
///
/// Ahora hay **un solo reloj compartido** por toda la app y el reflejo se
/// dibuja como una franja recortada encima del bloque. Sin capas de más.
class Esqueleto extends StatefulWidget {
  const Esqueleto({
    super.key,
    this.width,
    this.height,
    this.radio = 8,
    this.child,
  });

  final double? width;
  final double? height;
  final double radio;

  /// Para armar formas compuestas: el hijo se dibuja con el mismo brillo.
  final Widget? child;

  @override
  State<Esqueleto> createState() => _EsqueletoState();
}

/// El reloj de TODOS los esqueletos.
///
/// Uno solo, estático, que arranca cuando aparece el primer bloque y se apaga
/// cuando se va el último. Antes cada bloque traía el suyo: treinta relojes
/// para animar exactamente lo mismo.
class _RelojDelBrillo with WidgetsBindingObserver {
  static final _valor = ValueNotifier<double>(0);
  static Ticker? _ticker;
  static int _cuantos = 0;

  /// ── Por qué hace falta escuchar el ciclo de vida ─────────────────────────
  ///
  /// Un `Ticker` creado a mano —sin un TickerProvider de widget— NO se calla
  /// cuando la app pasa a segundo plano ni cuando la pestaña se oculta: sigue
  /// pidiendo un cuadro por vez, para siempre.
  ///
  /// Normalmente no se nota porque los bloques desaparecen en cuanto llega el
  /// contenido. Pero SIN CONEXIÓN no llega nunca: la app queda con los bloques
  /// puestos, el usuario la manda al fondo, y el reloj sigue latiendo a
  /// sesenta cuadros por segundo gastando batería sin que nadie lo vea.
  static final _vigia = _RelojDelBrillo();
  static bool _vigilando = false;

  /// ── Solo se apaga si la app NO se está viendo ──────────────────────────
  ///
  /// Antes se apagaba con cualquier estado que no fuera `resumed`, y ahí entra
  /// `inactive`, que en Android y en escritorio significa apenas «perdí el
  /// foco»: la app se sigue viendo enterita. Basta con que se corra una
  /// notificación por arriba, que se gire la pantalla o —en un emulador— que el
  /// puntero se vaya de la ventana.
  ///
  /// Lo que se veía: los bloques que ya estaban puestos se quedaban quietos,
  /// grises, sin brillar. Y no volvían solos, porque el reloj solo se reenciende
  /// con un `resumed` explícito, que no llega si la app nunca se fue del todo.
  /// Los bloques que se montaban DESPUÉS sí brillaban —`sumar` reenciende— así
  /// que quedaba la mitad de la pantalla animada y la otra mitad congelada.
  ///
  /// Ahora se apaga solo con `paused` y `detached`, que son los dos estados en
  /// los que de verdad no hay nadie mirando. Que era el motivo de todo esto: no
  /// gastar batería animando algo que no se ve.
  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    final aLaVista = estado != AppLifecycleState.paused &&
        estado != AppLifecycleState.detached;
    if (aLaVista) {
      if (_cuantos > 0) _encender();
      return;
    }
    _apagar();
  }

  /// Cuánto tarda el reflejo en cruzar de un lado al otro.
  static const _vuelta = Duration(milliseconds: 1400);

  static ValueListenable<double> get valor => _valor;

  static void _encender() {
    if (_ticker != null) return;
    _ticker = Ticker((elapsed) {
      _valor.value = (elapsed.inMilliseconds % _vuelta.inMilliseconds) /
          _vuelta.inMilliseconds;
    })
      ..start();
  }

  static void _apagar() {
    _ticker?.dispose();
    _ticker = null;
  }

  static void sumar() {
    _cuantos++;
    if (!_vigilando) {
      _vigilando = true;
      WidgetsBinding.instance.addObserver(_vigia);
    }
    _encender();
  }

  static void restar() {
    _cuantos--;
    if (_cuantos > 0) return;
    // Sin bloques en pantalla no hay nada que animar: se apaga en vez de
    // seguir pidiendo cuadros de gusto.
    _cuantos = 0;
    _apagar();
  }
}

class _EsqueletoState extends State<Esqueleto> {
  /// Si este bloque está en una pantalla que se ve.
  ///
  /// ── El desperdicio que había ────────────────────────────────────────────
  ///
  /// Al abrir un capítulo, la ficha NO se desmonta: queda debajo, tapada por
  /// el lector o el reproductor. Y con ella quedan sus bloques grises, cada uno
  /// escuchando el reloj y reconstruyéndose sesenta veces por segundo durante
  /// todo el rato que dura el capítulo. No se ven —hay una pantalla opaca
  /// encima— pero se rehacen igual.
  ///
  /// Flutter ya avisa de esto: el Navigator envuelve cada ruta en un
  /// `TickerMode` y lo apaga cuando queda tapada. Lo que pasa es que eso
  /// silencia a los Ticker de los widgets con TickerProvider, y el reloj del
  /// brillo es uno solo, creado a mano —está explicado más arriba—, así que no
  /// se enteraba. Ahora se mira acá.
  ///
  /// Se lee en didChangeDependencies porque TickerMode es un InheritedWidget:
  /// avisa solo cuando cambia, sin que nadie tenga que preguntar.
  bool _seVe = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ahora = TickerMode.valuesOf(context).enabled;
    if (ahora == _seVe) return;
    if (_seVe) {
      _RelojDelBrillo.restar();
    } else {
      _RelojDelBrillo.sumar();
    }
    _seVe = ahora;
  }

  @override
  void dispose() {
    if (_seVe) _RelojDelBrillo.restar();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final radio = BorderRadius.circular(widget.radio);
    final forma =
        widget.child ?? SizedBox(width: widget.width, height: widget.height);

    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: radio,
        child: Stack(
          children: [
            // El bloque de base. Si vino un hijo, es él el que da la forma.
            DecoratedBox(
              decoration: BoxDecoration(
                color: HomeTheme.esqueletoBase,
                borderRadius: radio,
              ),
              child: forma,
            ),
            // Y el reflejo, encima y recortado. Se corre con un Transform, así
            // que cada cuadro solo mueve una franja ya dibujada.
            //
            // Tapado por otra pantalla no se escucha al reloj: sin esto, cada
            // bloque se rehacía sesenta veces por segundo sin que nadie lo
            // viera. Ver _seVe.
            if (!_seVe)
              const SizedBox.shrink()
            else
              Positioned.fill(
                child: IgnorePointer(
                  child: ValueListenableBuilder<double>(
                    valueListenable: _RelojDelBrillo.valor,
                    builder: (context, t, _) {
                      // ── El reflejo se MUEVE dentro de la caja ────────────
                      //
                      // Antes se corría la caja entera con FractionalTranslation,
                      // de -1 a +2 de su propio ancho. El problema: durante buena
                      // parte del ciclo la caja está fuera del recorte, así que la
                      // franja aparecía a medias, se cortaba contra el borde y
                      // desaparecía — se veía como si la tarjeta estuviera
                      // partida.
                      //
                      // Ahora la caja se queda quieta y lo que viaja son las
                      // paradas del degradado. Rearmar un degradado por cuadro no
                      // cuesta una capa de dibujo, así que sigue siendo barato, y
                      // la franja cruza completa de lado a lado.
                      final x = -1 + 3 * t;
                      return DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment(x - 0.6, -0.4),
                            end: Alignment(x + 0.6, 0.4),
                            colors: [
                              HomeTheme.esqueletoBrillo.withValues(alpha: 0),
                              HomeTheme.esqueletoBrillo,
                              HomeTheme.esqueletoBrillo.withValues(alpha: 0),
                            ],
                            stops: const [0.0, 0.5, 1.0],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// El esqueleto con forma de tarjeta de catálogo: póster y dos líneas.
///
/// Mide exactamente lo mismo que [TarjetaDeCatalogo] con el mismo ancho, así
/// que al llegar el contenido la grilla no se mueve ni un píxel.
///
/// Un solo [Esqueleto] para las tres piezas y no uno por pieza: el brillo
/// cruza la tarjeta entera de una vez, que es como se ve en cualquier app, y
/// cuesta un tercio.
class EsqueletoTarjeta extends StatelessWidget {
  const EsqueletoTarjeta({super.key, required this.ancho});

  final double ancho;

  @override
  Widget build(BuildContext context) {
    return Esqueleto(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _bloque(ancho, ancho * 3 / 2, 8),
          const SizedBox(height: 8),
          _bloque(ancho * 0.9, 12, 4),
          const SizedBox(height: 6),
          _bloque(ancho * 0.6, 12, 4),
        ],
      ),
    );
  }

  static Widget _bloque(double w, double h, double r) => DecoratedBox(
        decoration: BoxDecoration(
          color: HomeTheme.esqueletoBase,
          borderRadius: BorderRadius.circular(r),
        ),
        child: SizedBox(width: w, height: h),
      );
}

/// Una fila horizontal de tarjetas fantasma que **llega hasta el borde**.
///
/// ── Por qué no un número fijo ───────────────────────────────────────────
///
/// Estaba a ojo —seis en el Inicio de escritorio, ocho en Buscar— y eso alcanza
/// en una ventana angosta. En una ancha se nota enseguida: la fila se cortaba a
/// media pantalla y quedaba un vacío al costado, justo donde va a haber
/// tarjetas. Se leía como que esa extensión ya había cargado y traído poco, que
/// es lo contrario de lo que está pasando.
///
/// Acá se cuentan los que entran de verdad. Con `ceil`, así el último asoma
/// cortado por el borde — que es exactamente lo que hace una fila con contenido
/// real, y por eso al llegar las tarjetas la forma no cambia.
class EsqueletoDeFila extends StatelessWidget {
  const EsqueletoDeFila({
    super.key,
    required this.ancho,
    this.separacion = 12,
    this.padding = EdgeInsets.zero,
    this.paddingDeCadaUno = EdgeInsets.zero,
  });

  /// El ancho de UNA tarjeta, el mismo que va a tener la de verdad.
  final double ancho;

  final double separacion;

  /// El de la fila entera.
  final EdgeInsets padding;

  /// El de cada bloque — en el Inicio las tarjetas llevan aire arriba para
  /// poder crecer al pasarles el mouse sin pisar el título de la fila.
  final EdgeInsets paddingDeCadaUno;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, caja) {
      // Se descuenta solo el margen IZQUIERDO: el de la derecha no acota nada,
      // porque la idea es justamente pasarse del borde.
      final util = caja.maxWidth - padding.left;
      // Un tope por las dudas: si el ancho llegara raro —cero, infinito, una
      // ventana en pleno arrastre— esto no puede pedir mil bloques.
      final cuantos = (util.isFinite && util > 0 && ancho > 0)
          ? ((util + separacion) / (ancho + separacion)).ceil().clamp(1, 24)
          : 1;
      return ListView.separated(
        scrollDirection: Axis.horizontal,
        // Quieta: mientras carga no hay a dónde ir, y dejarla desplazarse hace
        // que los bloques se muevan como si fueran contenido de verdad.
        physics: const NeverScrollableScrollPhysics(),
        padding: padding,
        itemCount: cuantos,
        separatorBuilder: (_, __) => SizedBox(width: separacion),
        itemBuilder: (_, __) => Padding(
          padding: paddingDeCadaUno,
          child: EsqueletoTarjeta(ancho: ancho),
        ),
      );
    });
  }
}

/// Una lista de bloques con forma de fila, para las zonas que no son grilla.
///
/// El repositorio y las extensiones instaladas no muestran portadas sino filas
/// anchas con el ícono, el nombre y un botón. Un bloque por fila, del alto de
/// la fila real, es lo que hace que al llegar el contenido nada se corra.
class EsqueletoDeLista extends StatelessWidget {
  const EsqueletoDeLista({
    super.key,
    required this.alto,
    this.separacion = 12,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 8),
  });

  final double alto;
  final double separacion;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, restricciones) {
      // Los que entran y uno más. Con techo: una pantalla alta pedía veinte
      // bloques de gusto, y son relleno, no un dato.
      final cuantos =
          ((restricciones.maxHeight - padding.vertical) / (alto + separacion))
                  .ceil()
                  .clamp(1, 8) +
              1;
      return ListView.separated(
        // Quieta: mientras carga no hay a dónde ir, y dejarla desplazarse hace
        // que los bloques se muevan como si fueran contenido de verdad.
        physics: const NeverScrollableScrollPhysics(),
        padding: padding,
        itemCount: cuantos,
        separatorBuilder: (_, __) => SizedBox(height: separacion),
        itemBuilder: (_, __) => Esqueleto(radio: 12, height: alto),
      );
    });
  }
}

/// Una grilla llena de bloques, con la misma forma que la de verdad.
///
/// ── Por qué hace falta una para grillas ─────────────────────────────────
///
/// [EsqueletoTarjeta] sirve para una fila, donde el ancho de la tarjeta lo pone
/// quien la dibuja. En una grilla no: el ancho sale de dividir el espacio entre
/// las columnas, así que copiar el cálculo en cada pantalla es pedir que se
/// separen del grid real y que al llegar el contenido todo se corra.
///
/// Acá se le pasan los MISMOS [columnas] y [proporcion] que al grid de verdad y
/// el ancho se calcula solo. Si mañana cambia el grid, cambia el bloque con él.
class EsqueletoDeGrilla extends StatelessWidget {
  const EsqueletoDeGrilla({
    super.key,
    required this.columnas,
    required this.proporcion,
    this.separacion = 16,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  final int columnas;

  /// El `childAspectRatio` del grid real: ancho dividido alto.
  final double proporcion;
  final double separacion;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, restricciones) {
      final cols = columnas < 1 ? 1 : columnas;
      final util =
          restricciones.maxWidth - padding.horizontal - separacion * (cols - 1);
      final ancho = util / cols;
      final alto = proporcion > 0 ? ancho / proporcion : ancho;
      // Los que entran en pantalla y una fila más: son relleno, no un dato. Sin
      // el techo, una pantalla alta pedía cincuenta bloques de gusto.
      final filas = ((restricciones.maxHeight / (alto + separacion)).ceil() + 1)
          .clamp(1, 6);
      return GridView.builder(
        // Quieta: mientras carga no hay a dónde ir, y dejarla desplazarse hace
        // que los bloques se muevan como si fueran contenido de verdad.
        physics: const NeverScrollableScrollPhysics(),
        padding: padding,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          childAspectRatio: proporcion,
          crossAxisSpacing: separacion,
          mainAxisSpacing: separacion,
        ),
        itemCount: cols * filas,
        itemBuilder: (_, __) =>
            Esqueleto(radio: 12, width: ancho, height: alto),
      );
    });
  }
}
