import 'package:flutter/material.dart';
import 'package:prismhub/views/widgets/pared_de_portadas.dart';

/// La pantalla de arranque.
///
/// ── Qué se cuidó, porque es la primera impresión ──────────────────────────
///
/// Esto se dibuja mientras la app todavía se está inicializando, o sea en el
/// momento en que el hilo de UI está MÁS ocupado. Un tirón acá se ve como una
/// app pesada, aunque después vuele. Por eso:
///
///   · **Sin desenfoque.** El fondo de la referencia se hace con un
///     `BackdropFilter`, que es lo más caro que hay en Flutter. La pared de
///     portadas consigue lo mismo pintándose ya apagada — ver
///     [ParedDePortadas], donde está el porqué completo.
///   · **Sin red y sin base de datos.** No espera nada para dibujarse: en el
///     primer arranque y sin internet se ve exactamente igual.
///   · **Dos animaciones y nada más**: la pared que se desplaza y el logo que
///     aparece. Cada una es un transform, no un repintado.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.soloLogo = false});

  /// Volviendo de segundo plano: solo el logo, sin presentación.
  ///
  /// ── Qué se estaba viendo, y por qué ─────────────────────────────────────
  ///
  /// Al volver a la app después de un rato, Android suele haber matado el
  /// proceso, así que es un arranque en frío: el sistema dibuja su splash con
  /// el logo. Hasta acá, igual que cualquier app.
  ///
  /// El problema venía después. Para no repetirle la presentación a quien
  /// estuvo hace un minuto, en ese caso se dibujaba un rectángulo oscuro y
  /// nada más. O sea que el logo del sistema aparecía y **se apagaba**,
  /// dejando la pantalla en negro mientras la carga real seguía, y recién ahí
  /// entraba el contenido. Reportado en vivo: «sale el logo, luego pantalla
  /// negra, luego carga».
  ///
  /// Lo que hacen las apps de verdad es un relevo continuo: el logo del
  /// sistema le entrega a uno igual, y de ahí al contenido. Nunca hay un
  /// hueco.
  ///
  /// Con esto se dibuja solo el logo —sin la pared de portadas, sin el título,
  /// sin la frase y sin la rueda— que es exactamente lo que venía mostrando el
  /// sistema. La presentación completa se guarda para cuando la app se abre de
  /// verdad, que es cuando tiene sentido.
  ///
  /// Y sigue sin costar tiempo: la espera artificial de 1,4 s se saltea igual
  /// (ver `_volviendo` en main.dart). Esto dura lo que tarde la carga real y
  /// ni un milisegundo más.
  final bool soloLogo;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const _fondo = Color(0xFF08080F);
  static const _acento = Color(0xFFD777ED);

  /// El latido del logo.
  ///
  /// Reemplaza a la rueda de siempre. La rueda dice "esperá"; esto dice "estoy
  /// vivo", que es lo que corresponde en una pantalla de arranque — no hay
  /// nada que el usuario tenga que esperar a propósito.
  ///
  /// Un solo controller para las dos cosas —el tamaño y la luz— porque van
  /// juntas: el resplandor crece cuando el logo crece, como un corazón.
  late final AnimationController _latido = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat(reverse: true);

  late final Animation<double> _pulso = CurvedAnimation(
    parent: _latido,
    // easeInOutSine da un vaivén parejo, sin el tironcito que deja easeInOut
    // en los extremos. En algo que late en bucle, ese tirón se nota.
    curve: Curves.easeInOutSine,
  );

  @override
  void dispose() {
    _latido.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _fondo,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // La pared y su velo solo en el arranque de verdad. Volviendo, el
          // fondo tiene que ser el mismo liso que venía mostrando el sistema:
          // cualquier cosa detrás delata el corte. Ver [soloLogo].
          if (!widget.soloLogo) ...[
            const ParedDePortadas(opacidad: 0.45),
            // El velo. Va DESPUÉS de la pared y antes del logo: oscurece hacia
            // el centro para que el logo se lea sobre cualquier tarjeta que
            // quede pasando por detrás, sin tener que apagar la pared entera.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  radius: 1.1,
                  colors: [
                    Color(0xE608080F),
                    Color(0xF208080F),
                    _fondo,
                  ],
                  stops: [0.0, 0.55, 1.0],
                ),
              ),
              child: SizedBox.expand(),
            ),
          ],
          // LayoutBuilder + tamaño relativo al alto: con un ancho fijo, en
          // horizontal —donde el alto de un teléfono es mucho menor— la
          // columna no entraba y desbordaba. Confirmado en vivo.
          LayoutBuilder(
            builder: (context, caja) {
              // ── El logo, y por qué no puede medir lo mismo en un televisor
              //
              // La cuenta original —30% del alto, hasta 240— está pensada para
              // un teléfono en vertical, donde el alto es mucho y el ancho
              // poco. En una pantalla apaisada esa misma cuenta deja un logo
              // desproporcionado: se mira desde lejos y ocupa media pantalla.
              // Reportado en vivo en un televisor.
              //
              // Se decide por la FORMA de la pantalla y no preguntando «¿esto
              // es una TV?» a propósito: acá todavía no se sabe —la detección
              // necesita el canal con la parte nativa y se resuelve más
              // adelante, mientras esta pantalla ya se está dibujando— y
              // además la forma es lo que de verdad importa. Un televisor
              // siempre es apaisado, y una ventana de escritorio apaisada
              // agradece exactamente lo mismo.
              //
              // En vertical la cuenta queda idéntica a la de siempre: en
              // teléfono no cambia nada.
              final apaisado = caja.maxWidth > caja.maxHeight * 1.4;
              final ladoDelLogo = (caja.maxHeight * (apaisado ? 0.20 : 0.30))
                  .clamp(110.0, apaisado ? 150.0 : 240.0)
                  .toDouble();
              return Center(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Volviendo, el logo NO entra con la animación de
                      // aparecer: el sistema ya lo tenía puesto, así que
                      // volver a desvanecerlo desde cero sería un parpadeo.
                      _Aparece(
                        demora: Duration.zero,
                        saltear: widget.soloLogo,
                        // El latido, en su propia capa: es lo único que se
                        // mueve en el centro de la pantalla, y sin esto cada
                        // cuadro suyo obliga a repintar también el título, la
                        // frase y la rueda de abajo.
                        child: RepaintBoundary(
                          child: AnimatedBuilder(
                          animation: _pulso,
                          // El logo va como `child`: se construye UNA vez y el
                          // builder solo lo envuelve. Sin esto, cada cuadro
                          // reconstruiría el Image.asset entero.
                          child: Image.asset(
                            'assets/iconoapp2.png',
                            width: ladoDelLogo,
                            // Se le pide el tamaño de decodificación al motor:
                            // el archivo es grande y sin esto se guarda en
                            // memoria a resolución completa para mostrarlo
                            // chiquito.
                            cacheWidth: (ladoDelLogo *
                                    MediaQuery.of(context).devicePixelRatio)
                                .round(),
                            filterQuality: FilterQuality.medium,
                          ),
                          builder: (context, hijo) {
                            final t = _pulso.value;
                            // ── El resplandor, con un degradado y no con una
                            //    sombra desenfocada ────────────────────────
                            //
                            // Acá había un `BoxShadow` cuyo `blurRadius` iba
                            // de 40 a 86 y cuyo `spreadRadius` iba de 2 a 12,
                            // los dos atados al latido. O sea: hasta 86
                            // píxeles de desenfoque REGENERÁNDOSE sesenta
                            // veces por segundo, y justo mientras la app se
                            // está inicializando, que es cuando menos aire
                            // hay. Era el cuadro más caro de toda la app, y
                            // en un televisor se veía como que la pantalla de
                            // arranque va a tirones.
                            //
                            // Un degradado radial da el mismo resplandor —se
                            // apaga hacia afuera igual— y no cuesta nada
                            // parecido: no hay capa aparte ni desenfoque, es
                            // un relleno. Lo que late es el tamaño del círculo
                            // y su intensidad, que es lo que se ve.
                            return Stack(
                              alignment: Alignment.center,
                              children: [
                                SizedBox(
                                  width: ladoDelLogo * (1.7 + t * 0.35),
                                  height: ladoDelLogo * (1.7 + t * 0.35),
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: RadialGradient(
                                        colors: [
                                          _acento.withValues(
                                              alpha: 0.20 + t * 0.16),
                                          _acento.withValues(alpha: 0),
                                        ],
                                        // El color vive en el centro y se
                                        // apaga antes del borde: sin esto el
                                        // círculo termina en un filo visible
                                        // en vez de fundirse con el fondo.
                                        stops: const [0.25, 1.0],
                                      ),
                                    ),
                                  ),
                                ),
                                // Late poco: 3% de más y de menos. Un latido
                                // grande marea y encima delata que es un
                                // bucle; uno chico se siente vivo sin llamar
                                // la atención.
                                Transform.scale(
                                  scale: 0.97 + t * 0.06,
                                  child: hijo,
                                ),
                              ],
                            );
                          },
                          ),
                        ),
                      ),
                      if (!widget.soloLogo) ...[
                        const SizedBox(height: 22),
                        const _Aparece(
                          demora: Duration(milliseconds: 220),
                          child: Text(
                            'PrismHub',
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const _Aparece(
                          demora: Duration(milliseconds: 380),
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 32),
                            child: Text(
                              'Anime, series, películas, mangas y novelas '
                              '— todo en un solo lugar.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13.5,
                                height: 1.4,
                                color: Color(0xFFB9B4C7),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 34),
                        // La rueda va con el latido, no en lugar de él: el logo
                        // dice que la app está viva y la rueda dice que todavía
                        // está preparando algo. Es lo último en aparecer, así
                        // que cuando el arranque es corto casi ni se ve.
                        //
                        // Fina y chica a propósito: al lado de un logo que late,
                        // una rueda gruesa le compite la atención al centro de
                        // la pantalla en vez de acompañarlo.
                        const _Aparece(
                          demora: Duration(milliseconds: 520),
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.0,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(_acento),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Aparece subiendo un poco, con una demora.
///
/// Encadenadas con demoras distintas, las piezas entran una detrás de otra en
/// vez de todas de golpe. Es lo que hace que se sienta armado y no cargado.
///
/// `TweenAnimationBuilder` y no un controller: corre una sola vez, no hace
/// falta nada que mantener vivo ni que liberar.
class _Aparece extends StatelessWidget {
  const _Aparece({
    required this.child,
    required this.demora,
    this.saltear = false,
  });

  final Widget child;
  final Duration demora;

  /// Se dibuja ya puesto, sin la entrada. Ver [SplashScreen.soloLogo].
  final bool saltear;

  @override
  Widget build(BuildContext context) {
    if (saltear) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 520),
      // La demora se hace con la curva y no con un Future: así no queda un
      // temporizador suelto que pueda dispararse con la pantalla ya cerrada.
      curve: Interval(
        (demora.inMilliseconds / 1100).clamp(0.0, 0.9),
        1.0,
        curve: Curves.easeOutCubic,
      ),
      builder: (context, t, hijo) => Opacity(
        opacity: t,
        child:
            Transform.translate(offset: Offset(0, 14 * (1 - t)), child: hijo),
      ),
      child: child,
    );
  }
}
