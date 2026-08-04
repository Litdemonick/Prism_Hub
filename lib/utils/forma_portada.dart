import 'package:flutter/widgets.dart';
import 'package:prismhub/utils/prismhub_storage.dart';

/// Qué forma tienen las portadas de cada extensión.
///
/// No todas las extensiones de vídeo publican lo mismo: las de anime usan
/// pósters verticales y otras usan fotogramas apaisados. Meter las dos en la
/// misma tarjeta obliga a recortar una, y se nota — el póster pierde la mitad
/// de arriba y abajo, o el fotograma pierde los costados.
///
/// En vez de anotar a mano cuál es cuál (una lista que se desactualiza en
/// cuanto se agrega una extensión) se mira la portada: la app ya la descarga
/// para mostrarla, así que leerle el ancho y el alto no cuesta nada.
class FormaPortada {
  FormaPortada._();

  /// Cuánto más ancha que alta tiene que ser para contarla como apaisada.
  ///
  /// Con margen a propósito: una portada casi cuadrada no es un fotograma, y
  /// ante la duda conviene la forma vertical, que es la de siempre.
  static const _margen = 1.15;

  /// Con cuántas portadas se da por decidida una extensión.
  ///
  /// Con una sola alcanzaría casi siempre, pero un título puntual puede traer
  /// una imagen rara —un aviso, un avatar genérico— y esa no puede decidir por
  /// todo el catálogo. Con cuatro y por mayoría, una rareza no manda.
  static const _muestrasParaDecidir = 4;

  /// Cambia de valor cada vez que una extensión cambia de forma, para que las
  /// grillas que estén en pantalla se rearmen.
  static final ValueNotifier<int> revision = ValueNotifier(0);

  /// Clave nueva: guarda la PROPORCIÓN (ancho ÷ alto) y no solo si es
  /// apaisada. La anterior guardaba un sí/no y con eso solo se puede elegir
  /// entre dos formas fijas; una portada más angosta que la caja quedaba con
  /// barras a los costados. Sabiendo la proporción real, la caja se hace del
  /// tamaño exacto y no sobra nada.
  static const _claveGuardada = 'proporcion_portadas';

  /// Lo ya resuelto y guardado en disco: paquete → ancho ÷ alto.
  static final Map<String, double> _decidido = {};

  /// Las proporciones vistas mientras todavía no hay muestras suficientes.
  static final Map<String, List<double>> _muestras = {};

  static bool _cargado = false;

  static void _cargar() {
    if (_cargado) return;
    _cargado = true;
    final guardado = PrismHubStorage.settings.get(_claveGuardada);
    if (guardado is! Map) return;
    guardado.forEach((paquete, proporcion) {
      if (paquete is String && proporcion is num && proporcion > 0) {
        _decidido[paquete] = proporcion.toDouble();
      }
    });
  }

  /// La proporción de las portadas de esta extensión: ancho ÷ alto.
  ///
  /// Null mientras no se sepa. Quien pregunta decide qué hacer con eso: la
  /// grilla y la ficha usan la forma vertical de siempre hasta que llegue.
  static double? proporcion(String paquete) {
    _cargar();
    final resuelta = _decidido[paquete];
    if (resuelta != null) return resuelta;
    final vistas = _muestras[paquete];
    if (vistas == null || vistas.isEmpty) return null;
    return _tipica(vistas);
  }

  /// Si las portadas de esta extensión son apaisadas.
  static bool? esApaisada(String paquete) {
    final p = proporcion(paquete);
    return p == null ? null : p > _margen;
  }

  /// La proporción vertical de siempre: la de una tapa de libro.
  ///
  /// Es la que se usa mientras no se sabe nada del sitio, y la que se le
  /// impone a las extensiones de lectura.
  static const proporcionVertical = 100 / 150;

  /// Qué proporción usar para dibujar las tarjetas de esta extensión.
  ///
  /// [esDeLectura] fuerza la vertical: un manga o una novela llevan tapa de
  /// libro, y que alguna portada suelta venga apaisada no cambia eso.
  ///
  /// El recorte de los extremos es para que una imagen rarísima —un banner
  /// larguísimo, una tira finita— no deforme la pantalla entera.
  static double paraDibujar(String paquete, {required bool esDeLectura}) {
    final medida = proporcion(paquete);
    if (medida == null) return proporcionVertical;
    if (esDeLectura && medida > _margen) return proporcionVertical;
    return medida.clamp(0.45, 2.2);
  }

  /// La proporción representativa de un puñado de muestras.
  ///
  /// La del medio y no el promedio: un título con una imagen rara (un aviso,
  /// un avatar genérico) desviaría el promedio de todo el catálogo, mientras
  /// que a la del medio no la mueve.
  static double _tipica(List<double> valores) {
    final ordenadas = [...valores]..sort();
    return ordenadas[ordenadas.length ~/ 2];
  }

  /// Anota el tamaño real de una portada recién cargada.
  ///
  /// Se llama desde el propio widget de la imagen, así que puede caer en
  /// mitad de un dibujado: por eso el aviso de que algo cambió se manda
  /// recién en el fotograma siguiente, nunca en el momento.
  static void anotar(String paquete, int ancho, int alto) {
    if (paquete.isEmpty || ancho <= 0 || alto <= 0) return;
    _cargar();
    // Ya resuelta: no hace falta seguir mirando portadas de esta extensión.
    if (_decidido.containsKey(paquete)) return;

    final antes = proporcion(paquete);
    final vistas = _muestras[paquete] ??= [];
    vistas.add(ancho / alto);

    if (vistas.length >= _muestrasParaDecidir) {
      _decidido[paquete] = _tipica(vistas);
      _muestras.remove(paquete);
      // Sin esperar a que termine de escribirse: es un dato de presentación, y
      // que se pierda una escritura solo significa volver a medir otro día.
      PrismHubStorage.settings.put(
        _claveGuardada,
        Map<String, double>.from(_decidido),
      );
    }

    if (proporcion(paquete) != antes) {
      WidgetsBinding.instance.addPostFrameCallback((_) => revision.value++);
    }
  }
}
