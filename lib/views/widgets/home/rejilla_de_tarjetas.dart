import 'package:prismhub/utils/breakpoints.dart';

/// Cuántas tarjetas de catálogo entran en una franja, y de qué ancho queda
/// cada una.
///
/// Estaba copiada en tres pantallas —la grilla de zonas, la grilla de Inicio
/// en televisor y la de buscar— y las tres discrepaban en algún detalle. Acá
/// está una sola vez, sin nada de Flutter adentro, para poder probarla.
///
/// ── En televisor manda la CANTIDAD, no el ancho ─────────────────────────
///
/// Fuera de televisor la cuenta empieza por un ancho ideal por tamaño de
/// pantalla y mete todas las columnas que entren. Eso funciona porque el
/// ancho en píxeles y la distancia a la que se mira van juntos: una ventana
/// más grande se mira igual de cerca.
///
/// En televisor no van juntos. La app corre en pantallas que le declaran a
/// Flutter anchos lógicos muy distintos —960, 1280, 1920— y todas se miran
/// desde el mismo sillón, a tres metros. Con un ancho fijo, el mismo número
/// da dos columnas en una y ocho en otra.
///
/// Y eso fue exactamente lo que pasó. Con 320 px por tarjeta, el televisor
/// donde se mide entraba en DOS columnas: dos portadas ocupando la pantalla
/// entera, sin ver la fila de abajo ni la de arriba. Reportado con foto.
///
/// Entonces en televisor se fija la cantidad —seis, que es lo que hacen las
/// apps de televisor— y el ancho sale de dividir. Los topes de abajo son
/// para que en una pantalla rara no queden ni estampillas ni carteles.
class RejillaDeTarjetas {
  /// A cuántas por fila se apunta en un televisor.
  static const columnasEnTv = 6;

  /// Menos que esto y el título de abajo no se lee desde el sillón.
  static const _anchoMinimoEnTv = 112.0;

  /// Más que esto y vuelve el problema de arriba: pocas por fila y enormes.
  static const _anchoMaximoEnTv = 210.0;

  /// Hasta dónde se puede llegar sumando columnas en una pantalla muy ancha.
  static const _topeEnTv = 10;

  /// [disponible] es el ancho ÚTIL: ya sin márgenes ni barra lateral.
  ///
  /// El ancho devuelto es el de la CELDA, que es lo que reparte `GridView`
  /// —estire o no la tarjeta de adentro—, así que sirve igual para calcular
  /// la proporción de la celda y para pasárselo a la tarjeta.
  static ({int columnas, double ancho}) calcular({
    required double disponible,
    required double separacion,
    required bool televisor,
    required Ancho pantalla,
    int tope = 10,
  }) {
    double anchoCon(int n) => (disponible - separacion * (n - 1)) / n;

    if (televisor) {
      var columnas = columnasEnTv;
      // Pantalla angosta: con seis quedarían estampillas, se sacan.
      while (columnas > 2 && anchoCon(columnas) < _anchoMinimoEnTv) {
        columnas--;
      }
      // Pantalla muy ancha: con seis quedarían carteles, se agregan. Se
      // comprueba que la columna de más siga entrando antes de sumarla, para
      // no cruzarse con el tope de abajo y quedar oscilando.
      while (columnas < _topeEnTv &&
          anchoCon(columnas) > _anchoMaximoEnTv &&
          anchoCon(columnas + 1) >= _anchoMinimoEnTv) {
        columnas++;
      }
      return (columnas: columnas, ancho: anchoCon(columnas));
    }

    final ideal = anchoIdealFueraDeTv(pantalla);
    final columnas = ((disponible + separacion) / (ideal + separacion))
        .floor()
        .clamp(2, tope);
    return (columnas: columnas, ancho: anchoCon(columnas));
  }

  /// El ancho de una tarjeta cuando NO es un televisor, por tamaño de
  /// pantalla. Es el mismo que usan las filas horizontales de Inicio.
  static double anchoIdealFueraDeTv(Ancho a) => a.elegir(
        compacto: 150,
        medio: 180,
        amplio: 210,
        enorme: 240,
      );
}
