import 'package:flutter/widgets.dart';

/// Los tamaños de pantalla, con nombre.
///
/// ── Por qué no alcanza con `Platform.isAndroid` ───────────────────────────
///
/// Porque «Android» no dice nada del tamaño: una tablet de 10 pulgadas y un
/// teléfono chico son el mismo `Platform`, y una ventana de escritorio
/// achicada a la mitad se parece más a la tablet que al escritorio. Preguntar
/// por el sistema operativo hacía que la app se viera bien solo en los dos
/// extremos.
///
/// Y hay un caso que el sistema operativo NUNCA puede contestar: **el usuario
/// arrastrando el borde de la ventana**. Eso pasa en vivo, y el diseño tiene
/// que acompañarlo.
///
/// Se mide el ANCHO y nada más. El alto importa poco acá: lo que decide si
/// entran tres tarjetas o siete es cuán ancha es la pantalla.
enum Ancho {
  /// Teléfono en vertical, o una ventana muy angosta.
  compacto,

  /// Teléfono en horizontal, tablet en vertical, media ventana.
  medio,

  /// Tablet en horizontal, laptop, escritorio.
  amplio,

  /// Monitores grandes y televisores.
  enorme;

  /// Los cortes, en píxeles lógicos.
  ///
  /// Son los de Material, que no salieron de la nada: 600 es donde una tablet
  /// deja de comportarse como teléfono y 1240 donde sobra lugar para más
  /// columnas sin que las tarjetas queden ridículas.
  static Ancho de(BuildContext context) =>
      desde(MediaQuery.sizeOf(context).width);

  static Ancho desde(double ancho) {
    if (ancho < 600) return Ancho.compacto;
    if (ancho < 1000) return Ancho.medio;
    if (ancho < 1600) return Ancho.amplio;
    return Ancho.enorme;
  }

  bool get esCompacto => this == Ancho.compacto;
  bool get alMenosMedio => index >= Ancho.medio.index;
  bool get alMenosAmplio => index >= Ancho.amplio.index;

  /// Elige un valor por tamaño. Los que no se pasan caen al anterior, así que
  /// alcanza con dar el de teléfono y el de escritorio.
  T elegir<T>({
    required T compacto,
    T? medio,
    T? amplio,
    T? enorme,
  }) =>
      switch (this) {
        Ancho.compacto => compacto,
        Ancho.medio => medio ?? compacto,
        Ancho.amplio => amplio ?? medio ?? compacto,
        Ancho.enorme => enorme ?? amplio ?? medio ?? compacto,
      };
}
