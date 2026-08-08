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

  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    if (estado == AppLifecycleState.resumed) {
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
  @override
  void initState() {
    super.initState();
    _RelojDelBrillo.sumar();
  }

  @override
  void dispose() {
    _RelojDelBrillo.restar();
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
                color: HomeTheme.cardSurface,
                borderRadius: radio,
              ),
              child: forma,
            ),
            // Y el reflejo, encima y recortado. Se corre con un Transform, así
            // que cada cuadro solo mueve una franja ya dibujada.
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
                          colors: const [
                            Color(0x00FFFFFF),
                            Color(0x14FFFFFF),
                            Color(0x00FFFFFF),
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
          color: HomeTheme.cardSurface,
          borderRadius: BorderRadius.circular(r),
        ),
        child: SizedBox(width: w, height: h),
      );
}
