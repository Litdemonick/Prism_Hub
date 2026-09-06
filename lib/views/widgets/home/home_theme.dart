import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:prismhub/utils/breakpoints.dart';

/// Qué modo de color usa la app.
///
/// ── Por qué un interruptor global y no el tema de Flutter ────────────────
///
/// Porque los colores de esta app ya estaban escritos como constantes de
/// [HomeTheme] y usados en casi ochocientos sitios, en las dos plataformas. Y
/// una de esas plataformas no corre sobre Material: en escritorio la raíz es
/// FluentApp, así que un `Theme.of(context)` no llega a la mitad de la app.
///
/// Convirtiendo esas constantes en getters que miran esta marca, las
/// ochocientas se adaptan solas y sin tocar una sola de ellas. Es la diferencia
/// entre un cambio de un archivo y un recorrido por sesenta.
///
/// El precio es que hay que avisarle al árbol cuando cambia, porque no es un
/// InheritedWidget: de eso se encarga [ModoDeColor.notificador], que la raíz
/// escucha para redibujar.
class ModoDeColor {
  ModoDeColor._();

  /// Si está puesto el modo claro.
  ///
  /// Arranca en oscuro, que es como nació la app y como la vio siempre todo el
  /// mundo. El claro es una elección, no el punto de partida.
  static final notificador = ValueNotifier<bool>(false);

  static bool get claro => notificador.value;

  static set claro(bool valor) {
    if (notificador.value == valor) return;
    notificador.value = valor;
    // ── Y se fuerza el redibujado de TODO ────────────────────────────────
    //
    // El oyente de la raíz rehace el árbol desde arriba, pero eso NO alcanza:
    // Flutter reusa los elementos cuyo widget no cambió, y las pantallas que
    // el Navigator tiene guardadas viven en su propio estado — se quedaban con
    // los colores de antes hasta salir y volver a entrar, o hasta reiniciar la
    // app. Reportado en vivo.
    //
    // `forceAppUpdate` marca cada elemento como pendiente de rehacer. Es caro,
    // sí: pasa una vez, cuando alguien toca el interruptor, y es exactamente el
    // caso para el que existe.
    Get.forceAppUpdate();
    aplicarBarrasDelSistema();
  }

  /// Le dice al sistema de qué color tiene que dibujar SUS iconos.
  ///
  /// ── Por qué hace falta ──────────────────────────────────────────────────
  ///
  /// La hora, la batería y la señal las dibuja Android, no la app, y las pinta
  /// del color que la app le pida. Estaban pedidas en claro —lo correcto sobre
  /// un fondo oscuro— y al encender el modo claro quedaban blancas sobre casi
  /// blanco: la barra de arriba se veía vacía.
  ///
  /// Se llama al cambiar el modo y también al arrancar, porque la preferencia
  /// se lee de disco y puede venir en claro desde el primer cuadro.
  ///
  /// `systemNavigationBar` va con el mismo criterio: es la barra de los tres
  /// botones de abajo, y ahí pasaba lo mismo.
  static void aplicarBarrasDelSistema() {
    if (!Platform.isAndroid) return;
    // Brightness.dark = iconos OSCUROS. El nombre confunde: se refiere al
    // contenido que hay DETRÁS, no al color de los iconos.
    final iconos = claro ? Brightness.dark : Brightness.light;
    // ── Color PROPIO, no `transparent` ──────────────────────────────────────
    //
    // Estaban las dos en transparente, y eso deja el fondo de las barras a
    // merced de lo que haya pintado abajo. Con el modo claro puesto, arriba
    // seguía asomando algo oscuro y encima los iconos ya iban en oscuro (que
    // es lo correcto sobre claro): quedaban negros sobre negro y la barra de
    // estado se veía vacía — reportado en vivo con captura, en oscuro no se
    // notaba porque ahí ese fondo oscuro es justo el que va.
    //
    // Pidiendo el color de la app deja de depender de quién pinte atrás: en
    // claro queda clara con iconos oscuros y en oscuro como estaba.
    //
    // Android lo respeta porque el targetSdk es 28 (ver android/app/
    // build.gradle). De subirlo a 35 o más, statusBarColor deja de tener
    // efecto y esto hay que resolverlo pintando la app detrás de la barra.
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: HomeTheme.bg,
      statusBarIconBrightness: iconos,
      statusBarBrightness: claro ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: HomeTheme.bg,
      systemNavigationBarIconBrightness: iconos,
    ));
  }
}

/// Envuelve una pantalla EMPUJADA para que se rehaga al cambiar el modo.
///
/// ── El agujero que tapa ─────────────────────────────────────────────────
///
/// El oyente de la raíz rehace el árbol desde arriba, y eso alcanza para las
/// pantallas que cuelgan de ahí. Pero una pantalla empujada
/// (`Get.to(() => Scaffold(...))`, `Navigator.push`) se arma UNA vez, cuando
/// se abre: el color que se le pase en ese momento —`backgroundColor:
/// HomeTheme.bg`— queda congelado en el widget que guarda la ruta.
///
/// Lo confuso es que la pantalla igual cambiaba **a medias**: lo de adentro
/// son widgets propios que vuelven a leer los colores cada vez que se
/// construyen, así que los títulos pasaban a la paleta clara mientras el fondo
/// seguía oscuro. Se veía peor que si no hubiera cambiado nada: texto casi
/// negro sobre fondo casi negro.
///
/// Con esto la pantalla queda suscrita al interruptor y se rehace entera.
class SigueElModo extends StatelessWidget {
  const SigueElModo({super.key, required this.builder});

  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: ModoDeColor.notificador,
        builder: (context, _, __) => builder(context),
      );
}

// Colores exactos del diseño (Figma → HTML exportado), convertidos de OKLCH
// a hex. No se cambia la tipografía de la app (Plus Jakarta Sans requeriría
// empaquetar fuentes nuevas) — el resto del estilo (color, espaciado, forma)
// sí se replica igual que el diseño.
//
// ── Y ahora hay dos paletas ─────────────────────────────────────────────
//
// La oscura es la de siempre, sin tocar un solo valor. La clara se derivó de
// ella respetando los MISMOS papeles: el fondo más apagado que las superficies,
// el borde apenas más marcado que el fondo, el texto secundario legible pero
// claramente por detrás del principal.
//
// Los acentos NO son los mismos en las dos. El rosa del diseño es claro, y un
// color claro sobre blanco no se lee: para el modo claro se oscurecen hasta
// que pasan el contraste, conservando el tono. Es el mismo criterio que ya se
// había usado para el borde de las tarjetas.
class HomeTheme {
  HomeTheme._();

  // ── Oscuro (el original) ─────────────────────────────────────────────────
  static const _bgOscuro = Color(0xFF08090D);
  static const _textPrimaryOscuro = Color(0xFFEAEBF2);
  static const _textMutedOscuro = Color(0xFF7E8087);
  static const _textPlaceholderOscuro = Color(0xFF676870);
  static const _borderOscuro = Color(0xFF2C2D35);
  static const _accentPinkOscuro = Color(0xFFD777ED);
  static const _accentRedOscuro = Color(0xFFE5484D);
  static const _cardSurfaceOscuro = Color(0xFF15151C);

  // ── Claro ────────────────────────────────────────────────────────────────
  //
  // El fondo NO es blanco puro: con las tarjetas en blanco, un fondo blanco las
  // hace desaparecer. Un gris muy claro deja que la tarjeta se lea como una
  // superficie por encima, que es el mismo papel que cumple en el modo oscuro.
  static const _bgClaro = Color(0xFFF3F4F8);
  static const _textPrimaryClaro = Color(0xFF14151A);
  static const _textMutedClaro = Color(0xFF5D5F68);
  static const _textPlaceholderClaro = Color(0xFF8A8C95);
  static const _borderClaro = Color(0xFFDCDEE6);
  // El rosa del diseño (0xFFD777ED) sobre blanco no llega al contraste mínimo
  // para texto. Este conserva el tono y baja la luminosidad hasta que sí.
  static const _accentPinkClaro = Color(0xFF9B3BB8);
  static const _accentRedClaro = Color(0xFFC0272D);
  static const _cardSurfaceClaro = Color(0xFFFFFFFF);

  // ── La paleta oscura, accesible a propósito ─────────────────────────────
  //
  // Para las pantallas que se quedan oscuras SIEMPRE, gane el modo que gane: el
  // reproductor y el lector. Ahí el contenido es un vídeo o una página de
  // manga sobre negro, y una interfaz clara alrededor de eso no es una opción
  // de estilo — encandila y compite con lo que se está mirando. Es lo que hace
  // cualquier reproductor, incluso los que tienen tema claro.
  //
  // Se exponen los mismos valores de siempre, sin duplicarlos: si mañana cambia
  // el oscuro, cambia también acá.
  static const oscuroFondo = _bgOscuro;
  static const oscuroSuperficie = _cardSurfaceOscuro;
  static const oscuroTexto = _textPrimaryOscuro;
  static const oscuroTextoTenue = _textMutedOscuro;
  static const oscuroBorde = _borderOscuro;
  static const oscuroAcento = _accentPinkOscuro;
  static const oscuroAcentoRojo = _accentRedOscuro;

  static bool get _claro => ModoDeColor.claro;

  static Color get bg => _claro ? _bgClaro : _bgOscuro;
  static Color get textPrimary =>
      _claro ? _textPrimaryClaro : _textPrimaryOscuro;
  static Color get textMuted => _claro ? _textMutedClaro : _textMutedOscuro;
  static Color get textPlaceholder =>
      _claro ? _textPlaceholderClaro : _textPlaceholderOscuro;
  static Color get border => _claro ? _borderClaro : _borderOscuro;
  static Color get accentPink => _claro ? _accentPinkClaro : _accentPinkOscuro;

  /// Acento de la Zona +18 — mismo rol que [accentPink] (hover, progreso,
  /// brillo ambiental) pero rojo, para que esa pantalla se sienta claramente
  /// distinta del Home normal. Ver AnimatedBackgroundGlow/HomeSection/
  /// HomeMediaCard, que aceptan `accent` en vez de tener este color fijo.
  static Color get accentRed => _claro ? _accentRedClaro : _accentRedOscuro;

  static Color get cardSurface =>
      _claro ? _cardSurfaceClaro : _cardSurfaceOscuro;

  /// El color que CONTRASTA con el fondo de la app.
  ///
  /// Blanco en oscuro, casi negro en claro. Es para lo que antes estaba escrito
  /// como `Colors.white` a mano: textos e iconos dibujados encima de una
  /// superficie de la app. En oscuro devuelve exactamente lo de siempre, así
  /// que reemplazarlo no cambia nada allá.
  ///
  /// OJO con dónde se usa: NO sirve para lo que va encima de una PORTADA. Ahí
  /// el fondo es la imagen, no la app, y el blanco es correcto en los dos modos
  /// —por eso esas encima llevan un velo oscuro—. Cambiarlo ahí dejaría texto
  /// oscuro sobre una imagen oscura.
  static Color get contraste => _claro ? _textPrimaryClaro : Colors.white;

  /// El color que se lee ENCIMA de [contraste] y de [textPrimary].
  ///
  /// O sea el inverso: casi negro en oscuro, blanco en claro. Lo usan los
  /// botones rellenos, que se pintan con el color de máximo contraste y llevan
  /// su texto en el opuesto. Sin esto, el botón principal del Inicio quedaba en
  /// modo claro como una caja negra con el texto negro adentro: invisible.
  static Color get sobreContraste =>
      _claro ? _cardSurfaceClaro : const Color(0xFF17141F);

  /// El color del texto que va ENCIMA de una portada.
  ///
  /// Siempre blanco, en los dos modos, y no es un olvido: ahí el fondo no es la
  /// app sino la imagen, que puede ser de cualquier color. Por eso esas
  /// pantallas llevan un velo oscuro debajo del texto — con el velo puesto, el
  /// blanco se lee sobre cualquier portada.
  ///
  /// El título de la ficha usaba [textPrimary] y en modo claro pasó a ser casi
  /// negro sobre una imagen oscura: no se leía nada. Este es el que va ahí.
  static const sobrePortada = Color(0xFFFFFFFF);

  /// El gris de los bloques que esperan contenido.
  ///
  /// No puede ser [cardSurface]: en claro esa superficie es BLANCA, igual que
  /// la tarjeta que va a reemplazarla, así que el bloque desaparecía contra el
  /// fondo y no se veía nada cargando. Tiene que ser un tono por DEBAJO de la
  /// superficie, que es el papel que cumple en oscuro.
  static Color get esqueletoBase =>
      _claro ? const Color(0xFFE4E6EE) : _cardSurfaceOscuro;

  /// El reflejo que cruza el bloque.
  ///
  /// En oscuro es un blanco muy tenue, porque el bloque es oscuro y lo que se
  /// nota es un ACLARADO. En claro hay que hacer lo contrario: sobre un gris
  /// claro, un reflejo blanco no se ve; el que se nota es un oscurecido.
  static Color get esqueletoBrillo =>
      _claro ? const Color(0x12000000) : const Color(0x14FFFFFF);

  /// El título de una zona: «Inicio», «Biblioteca», «Buscar», «Historial».
  ///
  /// ── Por qué está acá y no escrito en cada pantalla ──────────────────────
  ///
  /// Estaba repetido a mano en cada una, y con el tiempo se separaron: 25 en
  /// Biblioteca, 22 en Buscar y en Historial, 20 y 24 en Ajustes. Cinco
  /// pantallas hermanas con cuatro tamaños distintos, y solo la de Inicio en
  /// blanco puro — el resto caía en textPrimary, que es gris clarito. Se
  /// notaba al pasar de una a otra: el título cambiaba de peso y de color sin
  /// que nada lo justificara.
  ///
  /// El de Inicio es el bueno y el que manda, porque es el que lleva el nombre
  /// de la app: 25, bien grueso, con el interletrado cerrado y en BLANCO. Los
  /// demás lo copian desde acá.
  ///
  /// En modo claro el blanco puro no sirve —no se vería— y pasa a ser el texto
  /// principal, que ahí es casi negro. El papel es el mismo: el color de máximo
  /// contraste contra el fondo.
  ///
  /// [bajo] es para pantalla baja —un teléfono acostado— donde 25 se come una
  /// franja que le hace falta al contenido.
  static TextStyle tituloDeZona({bool bajo = false}) => TextStyle(
        fontSize: bajo ? 21 : 25,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.6,
        color: _claro ? _textPrimaryClaro : Colors.white,
      );

  /// El degradado grande de la cabecera.
  ///
  /// En claro se conserva el mismo recorrido de tonos —violeta a azul a fondo—
  /// pero muy lavado: sobre él van a ir textos oscuros, y un degradado saturado
  /// se los come igual que uno oscuro se come los claros.
  static LinearGradient get heroGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: _claro
            ? const [Color(0xFFE7D7EE), Color(0xFFDCE4F2), Color(0xFFF3F4F8)]
            : const [Color(0xFF573160), Color(0xFF0C1A32), Color(0xFF0B0C16)],
        stops: const [0.0, 0.65, 1.0],
      );

  /// Variante roja del hero, mismo patrón de 3 paradas — Zona +18.
  static LinearGradient get heroGradientRed => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: _claro
            ? const [Color(0xFFF2DADB), Color(0xFFE8D2D3), Color(0xFFF3F4F8)]
            : const [Color(0xFF5C1B22), Color(0xFF2A0C10), Color(0xFF0B0C16)],
        stops: const [0.0, 0.65, 1.0],
      );

  // Un gradiente por posición — mismo patrón round-robin que usa el diseño
  // para las tarjetas cuando no hay portada real.
  static const _cardGradientsOscuro = [
    [Color(0xFF65396F), Color(0xFF1E142E)], // violeta
    [Color(0xFF294778), Color(0xFF071727)], // azul
    [Color(0xFF853538), Color(0xFF2E0F15)], // rojo
    [Color(0xFF005D39), Color(0xFF001C13)], // verde
    [Color(0xFF654C00), Color(0xFF1F1702)], // dorado
  ];

  // Los mismos cinco tonos, subidos de luminosidad: acá va a ir el título de la
  // obra en texto oscuro, así que el degradado tiene que ser el fondo y no la
  // figura.
  static const _cardGradientsClaro = [
    [Color(0xFFD9C4E0), Color(0xFFEDE4F1)], // violeta
    [Color(0xFFC3D3EC), Color(0xFFE3EAF5)], // azul
    [Color(0xFFEFC9CB), Color(0xFFF7E5E6)], // rojo
    [Color(0xFFBFE0D0), Color(0xFFE2F1EA)], // verde
    [Color(0xFFEDDDB0), Color(0xFFF7EFD9)], // dorado
  ];

  static List<List<Color>> get cardGradients =>
      _claro ? _cardGradientsClaro : _cardGradientsOscuro;

  static List<Color> gradientFor(int index) =>
      cardGradients[index % cardGradients.length];

  // ─── Medidas de televisor (regla de los 10 pies) ─────────────────────────
  //
  // Un televisor se mira desde el sillón, a unos tres metros, no a treinta
  // centímetros como un teléfono. Un tamaño que en PC se lee perfecto ahí es
  // ilegible, y un margen que en un monitor no se nota, en un televisor que
  // recorta el borde de la imagen se pierde entero.
  //
  // Estaba resuelto a ojo y por separado en cada pantalla de TV — el overscan
  // llegó a estar escrito DOS VECES con el mismo cuerpo
  // (`home_page_tv.dart`/`detail_page_tv.dart`), al 2,5%, y ninguna otra
  // pantalla de TV lo aplicaba. Acá queda uno solo, y con criterio: todo sale
  // de `Ancho.elegir<T>()`, el mismo mecanismo que ya usa el resto de la app
  // para adaptarse a un tamaño real en vez de tirar un número fijo pensado
  // para una sola resolución — así una TV 1080p, una 4K, o el emulador en una
  // ventana chica se acomodan solas.

  /// El margen de seguridad contra el borde de la pantalla (overscan).
  ///
  /// 5%, el mínimo que recomienda la propia guía de diseño de Android TV —
  /// antes eran 2,5%, cortos para lo que de verdad recortan algunos
  /// televisores viejos.
  static double overscanTv(BuildContext context) =>
      (MediaQuery.sizeOf(context).width * 0.05).clamp(16, 64);

  /// El margen contra el borde de la pantalla, repartido como corresponde.
  ///
  /// ── Por qué NO es el mismo por los cuatro lados ─────────────────────────
  ///
  /// Se usaba `EdgeInsets.all(overscanTv)`, o sea el 5 % del ancho arriba,
  /// abajo y a los costados. En una pantalla de 1280x720 son 64 px arriba y 64
  /// abajo: el 18 % de la altura, regalado. Reportado en vivo: «usá toda la
  /// pantalla del televisor, veo que usás una porción».
  ///
  /// El recorte de los televisores viejos —lo que este margen existe para
  /// esquivar— se lleva sobre todo los costados, que es donde se pierde texto.
  /// En vertical, además, las pantallas de la app son desplazables o tienen su
  /// propio aire arriba, así que ahí ese margen no protege: solo achica.
  ///
  /// Queda un tercio arriba y abajo: alcanza para que nada toque el borde, sin
  /// perder el alto de una fila entera.
  static EdgeInsets margenTv(BuildContext context) {
    final m = overscanTv(context);
    // ── Y abajo, todavía menos ────────────────────────────────────────────
    //
    // El margen de abajo no protege de nada: lo que hay ahí es contenido
    // que sigue, y cada punto que se le da es un punto MENOS de la tarjeta
    // que asoma — justo la señal de «hay más para abajo». Reportado con
    // foto, señalando la franja muerta bajo la última fila: «hasta ahí debe
    // verse la imagen, para que se vea que hay más cosas abajo».
    //
    // Arriba se conserva el tercio: ahí sí hay borde de pantalla y nada que
    // se pierda por dejarlo.
    return EdgeInsets.fromLTRB(m, m / 3, m, m / 6);
  }

  /// El título de una ficha, o de un destacado grande. Mucho más grande que
  /// en PC/teléfono a propósito: se lee de un vistazo desde el sillón, no de
  /// cerca.
  static TextStyle tituloTv(BuildContext context) => TextStyle(
        fontSize: Ancho.de(context).elegir(compacto: 30, enorme: 40),
        fontWeight: FontWeight.w800,
        letterSpacing: -0.6,
        height: 1.1,
        color: sobrePortada,
      );

  /// El nombre de una fila («Continuar viendo», el nombre de una extensión).
  static TextStyle tituloDeFilaTv(BuildContext context) => TextStyle(
        fontSize: Ancho.de(context).elegir(compacto: 18, enorme: 22),
        fontWeight: FontWeight.w700,
        color: _claro ? _textPrimaryClaro : Colors.white,
      );

  /// El párrafo de sinopsis de una ficha. Breve por diseño —la pantalla ya
  /// limita cuántas líneas entran— pero cuando hay, tiene que leerse entera
  /// desde lejos.
  static TextStyle sinopsisTv(BuildContext context) => TextStyle(
        fontSize: Ancho.de(context).elegir(compacto: 15, enorme: 17),
        height: 1.5,
        color: textMuted,
      );

  /// La etiqueta de un botón o de una entrada del menú.
  static TextStyle etiquetaTv(BuildContext context) => TextStyle(
        fontSize: Ancho.de(context).elegir(compacto: 13, enorme: 15),
        fontWeight: FontWeight.w600,
      );

  /// El alto mínimo de cualquier cosa enfocable: un botón, una entrada del
  /// menú, una fila de Ajustes. Con el dedo alcanza con que el blanco sea
  /// grande; con el D-pad lo que hace falta es que el SALTO entre un elemento
  /// y el siguiente sea inconfundible, y eso lo da la altura mínima, no el
  /// ancho.
  static double altoEnfocableTv(BuildContext context) =>
      Ancho.de(context).elegir(compacto: 48, enorme: 56);

  /// El radio de esquina que usan las tarjetas y los paneles de TV. Un poco
  /// más suave que el de PC/teléfono (8): a la distancia de un sillón, un
  /// radio chico casi no se distingue de una esquina recta.
  static const radioTv = 12.0;

  /// El aire MÍNIMO que hay que dejar alrededor de cualquier cosa enfocable
  /// en televisor.
  ///
  /// ── Por qué es un número con nombre y no uno suelto en cada sitio ──────
  ///
  /// El marco de selección NO se dibuja dentro de la tarjeta: sale unos
  /// píxeles hacia afuera, y lleva encima un resplandor bastante más ancho.
  /// Donde el contenido llega justo al filo —de la pantalla, del panel de
  /// categorías, del recorte de una fila, del borde de una lista— ese marco
  /// queda mordido y la tarjeta se ve cortada.
  ///
  /// Eso volvió del televisor una y otra vez, siempre igual y siempre en un
  /// sitio distinto: la primera tarjeta de la fila, la última contra el
  /// borde derecho, la de arriba contra el recorte de la lista, la de
  /// abajo. Cada vez se arreglaba con un número puesto a mano ahí, y el
  /// siguiente sitio volvía a nacer sin él.
  ///
  /// Con el mínimo acá, quien escriba una pantalla nueva tiene el número a
  /// mano y no tiene que redescubrirlo. Regla del proyecto, dicha así:
  /// «siempre debe haber aire para que los bordes se vean bien, que no se
  /// corte nada, y que el usuario se dé cuenta de que hay más cosas a la
  /// derecha y abajo».
  ///
  /// Doce: el marco mide tres y el resplandor se apaga solo, así que con
  /// esto el borde entra entero y todavía se lee el degradado alrededor.
  /// Los sitios que ya dan MÁS (el recorte de fila, el margen contra el
  /// rail) se quedan como están: esto es un piso, no una medida exacta.
  static const aireDeFocoTv = 12.0;
}
