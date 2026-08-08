import 'package:flutter/material.dart';
import 'package:prismhub/router/router.dart';

class LayoutUtils {
  /// El ancho y el alto de AHORA. Cambian al girar el aparato.
  static double get width {
    return MediaQuery.of(currentContext).size.width;
  }

  static double get height {
    return MediaQuery.of(currentContext).size.height;
  }

  /// El aparato es una tablet.
  ///
  /// ── Se mide el lado corto, y no se guarda ─────────────────────────────────
  ///
  /// Antes era `ancho > 800`, calculado UNA vez y guardado para toda la sesión
  /// (`_isTablet ??= ...`). Las dos mitades de esa frase estaban mal:
  ///
  /// · **El ancho cambia al girar.** Un teléfono acostado mide 900 de ancho y
  ///   pasaba por tablet. El lado corto es el mismo esté como esté puesto el
  ///   aparato, que es lo que corresponde para una pregunta sobre el APARATO.
  ///
  /// · **Guardarlo lo dejaba clavado al azar.** El valor quedaba fijado por la
  ///   primera pantalla que preguntara, y de ahí no se movía. Un teléfono que
  ///   abría acostado quedaba marcado como tablet para toda la sesión, y una
  ///   tablet que abría derecha quedaba marcada como teléfono.
  ///
  /// El peor caso de eso es concreto y no es cosmético: si la primera en
  /// preguntar era el reproductor —que corre SIEMPRE acostado— el teléfono
  /// quedaba marcado como tablet, y al salir no se devolvía la rotación libre
  /// (ver `video_controller` y `webview_player_page`, que se saltean ese paso
  /// en tablet porque nunca le forzaron la orientación). La app entera se
  /// quedaba trabada en horizontal hasta reiniciarla.
  ///
  /// 600 de lado corto es el corte de siempre para separar teléfono de tablet.
  ///
  /// ── Ojo: esto NO sirve para decidir un diseño ─────────────────────────────
  ///
  /// Contesta «qué aparato es», no «cuánto ancho tengo». Para elegir entre un
  /// panel y dos, o cuántas columnas entran, hay que medir el ancho disponible
  /// de verdad —con `LayoutBuilder` o `MediaQuery.sizeOf`— porque una tablet en
  /// vertical y un teléfono acostado no se parecen en nada aunque las dos
  /// contesten lo mismo acá. Ver `DetailPage._fichaArmada` y `Ancho.de`.
  static bool get esTablet {
    return MediaQuery.of(currentContext).size.shortestSide >= 600;
  }
}
