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
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  static const _fondo = Color(0xFF08080F);
  static const _acento = Color(0xFFD777ED);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _fondo,
      body: Stack(
        fit: StackFit.expand,
        children: [
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
          // LayoutBuilder + tamaño relativo al alto: con un ancho fijo, en
          // horizontal —donde el alto de un teléfono es mucho menor— la
          // columna no entraba y desbordaba. Confirmado en vivo.
          LayoutBuilder(
            builder: (context, caja) {
              final ladoDelLogo =
                  (caja.maxHeight * 0.30).clamp(110.0, 240.0).toDouble();
              return Center(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _Aparece(
                        demora: Duration.zero,
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
                      ),
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
                      const _Aparece(
                        demora: Duration(milliseconds: 520),
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            valueColor: AlwaysStoppedAnimation<Color>(_acento),
                          ),
                        ),
                      ),
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
  const _Aparece({required this.child, required this.demora});

  final Widget child;
  final Duration demora;

  @override
  Widget build(BuildContext context) {
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
        child: Transform.translate(offset: Offset(0, 14 * (1 - t)), child: hijo),
      ),
      child: child,
    );
  }
}
