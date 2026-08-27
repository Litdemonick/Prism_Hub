import 'package:flutter/material.dart';

/// La pantalla de arranque.
///
/// ── Qué se cuidó, porque es la primera impresión ──────────────────────────
///
/// Esto se dibuja mientras la app todavía se está inicializando, o sea en el
/// momento en que el hilo de UI está MÁS ocupado. Un tirón acá se ve como una
/// app pesada, aunque después vuele. Por eso el arranque en frío es un
/// banner ESTÁTICO —pedido explícito, estilo Magis TV: nada de capas que
/// desplazar ni animar, un solo `Image.asset` con `cacheWidth` puesto para
/// no decodificar a resolución completa en un aparato de gama baja.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.soloLogo = false});

  /// Volviendo de segundo plano: solo el logo, sin el banner.
  ///
  /// ── Qué se estaba viendo, y por qué ─────────────────────────────────────
  ///
  /// Al volver a la app después de un rato, Android suele haber matado el
  /// proceso, así que es un arranque en frío: el sistema dibuja su splash con
  /// el logo. Hasta acá, igual que cualquier app.
  ///
  /// El problema venía después. Para no repetirle la presentación al banner
  /// a quien estuvo hace un minuto, en ese caso se dibujaba un rectángulo
  /// oscuro y nada más. O sea que el logo del sistema aparecía y **se
  /// apagaba**, dejando la pantalla en negro mientras la carga real seguía, y
  /// recién ahí entraba el contenido. Reportado en vivo: «sale el logo,
  /// luego pantalla negra, luego carga».
  ///
  /// Lo que hacen las apps de verdad es un relevo continuo: el logo del
  /// sistema le entrega a uno igual, y de ahí al contenido. Nunca hay un
  /// hueco. Con esto se dibuja solo el logo —el mismo que venía mostrando el
  /// sistema, sin el banner entero de golpe— que es lo que corresponde acá.
  /// La presentación completa se guarda para cuando la app se abre de
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

  /// El latido del logo — solo hace falta en el camino de "solo logo"
  /// (volviendo de segundo plano). El banner de arranque en frío es estático
  /// a propósito, sin nada que animar.
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
    return widget.soloLogo ? _buildSoloLogo(context) : _buildBanner(context);
  }

  /// El banner completo, para el arranque en frío de verdad.
  ///
  /// Un solo `Image.asset`, sin overlays ni texto aparte: el banner ya trae
  /// el logo, el nombre y "Cargando tu contenido..." dibujados adentro —
  /// agregar algo más encima sería duplicar lo mismo. `cacheWidth` pide la
  /// decodificación al ancho real de pantalla (y no a los 2752px del
  /// archivo): sin esto, un televisor de gama baja decodifica la imagen
  /// entera en memoria para después mostrarla achicada.
  Widget _buildBanner(BuildContext context) {
    final ancho = MediaQuery.sizeOf(context).width;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    return Scaffold(
      backgroundColor: _fondo,
      body: SizedBox.expand(
        child: Image.asset(
          'assets/banner_cargando_launch.jpg',
          fit: BoxFit.cover,
          cacheWidth: (ancho * dpr).round(),
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }

  /// Solo el logo latiendo, para cuando se vuelve de segundo plano — ver
  /// [SplashScreen.soloLogo].
  Widget _buildSoloLogo(BuildContext context) {
    return Scaffold(
      backgroundColor: _fondo,
      body: LayoutBuilder(
        builder: (context, caja) {
          // ── Por qué no puede medir lo mismo en un televisor ──────────────
          //
          // La cuenta original —30% del alto, hasta 240— está pensada para
          // un teléfono en vertical, donde el alto es mucho y el ancho poco.
          // En una pantalla apaisada esa misma cuenta deja un logo
          // desproporcionado: se mira desde lejos y ocupa media pantalla.
          // Reportado en vivo en un televisor.
          //
          // Se decide por la FORMA de la pantalla y no preguntando «¿esto es
          // una TV?» a propósito: acá todavía no se sabe —la detección
          // necesita el canal con la parte nativa y se resuelve más
          // adelante, mientras esta pantalla ya se está dibujando— y además
          // la forma es lo que de verdad importa. Un televisor siempre es
          // apaisado, y una ventana de escritorio apaisada agradece
          // exactamente lo mismo.
          final apaisado = caja.maxWidth > caja.maxHeight * 1.4;
          final ladoDelLogo = (caja.maxHeight * (apaisado ? 0.20 : 0.30))
              .clamp(110.0, apaisado ? 150.0 : 240.0)
              .toDouble();
          return Center(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _pulso,
                // El logo va como `child`: se construye UNA vez y el builder
                // solo lo envuelve. Sin esto, cada cuadro reconstruiría el
                // Image.asset entero.
                child: Image.asset(
                  'assets/iconoapp2.png',
                  width: ladoDelLogo,
                  cacheWidth: (ladoDelLogo * MediaQuery.of(context).devicePixelRatio)
                      .round(),
                  filterQuality: FilterQuality.medium,
                ),
                builder: (context, hijo) {
                  final t = _pulso.value;
                  // ── El resplandor, con un degradado y no con una sombra
                  //    desenfocada ──────────────────────────────────────────
                  //
                  // Un `BoxShadow` con blur/spread atados al latido es el
                  // cuadro más caro que había en esta pantalla: hasta 86px de
                  // desenfoque regenerándose 60 veces por segundo, justo
                  // mientras la app se está inicializando. Un degradado
                  // radial da el mismo resplandor sin desenfoque ni capa
                  // aparte — es un relleno, y lo único que late es el tamaño
                  // del círculo y su intensidad.
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
                                _acento.withValues(alpha: 0.20 + t * 0.16),
                                _acento.withValues(alpha: 0),
                              ],
                              // El color vive en el centro y se apaga antes
                              // del borde: sin esto el círculo termina en un
                              // filo visible en vez de fundirse con el fondo.
                              stops: const [0.25, 1.0],
                            ),
                          ),
                        ),
                      ),
                      // Late poco: 3% de más y de menos. Un latido grande
                      // marea y encima delata que es un bucle; uno chico se
                      // siente vivo sin llamar la atención.
                      Transform.scale(
                        scale: 0.97 + t * 0.06,
                        child: hijo,
                      ),
                    ],
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}
