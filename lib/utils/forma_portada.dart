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

  static const _claveGuardada = 'forma_portadas';

  /// Lo ya resuelto y guardado en disco: paquete → si es apaisada.
  static final Map<String, bool> _decidido = {};

  /// Recuento mientras todavía no hay muestras suficientes.
  static final Map<String, List<int>> _recuento = {};

  static bool _cargado = false;

  static void _cargar() {
    if (_cargado) return;
    _cargado = true;
    final guardado = PrismHubStorage.settings.get(_claveGuardada);
    if (guardado is! Map) return;
    guardado.forEach((paquete, apaisada) {
      if (paquete is String && apaisada is bool) _decidido[paquete] = apaisada;
    });
  }

  /// Si las portadas de esta extensión son apaisadas.
  ///
  /// Null mientras no se sepa: quien pregunta decide qué hacer con eso (la
  /// grilla usa la forma vertical de siempre hasta que llegue la primera).
  static bool? esApaisada(String paquete) {
    _cargar();
    final resuelto = _decidido[paquete];
    if (resuelto != null) return resuelto;
    final cuenta = _recuento[paquete];
    if (cuenta == null) return null;
    return cuenta[0] > cuenta[1];
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

    final antes = esApaisada(paquete);
    final cuenta = _recuento[paquete] ??= [0, 0];
    if (ancho > alto * _margen) {
      cuenta[0]++;
    } else {
      cuenta[1]++;
    }

    if (cuenta[0] + cuenta[1] >= _muestrasParaDecidir) {
      _decidido[paquete] = cuenta[0] > cuenta[1];
      _recuento.remove(paquete);
      // Sin esperar a que termine de escribirse: es un dato de presentación, y
      // que se pierda una escritura solo significa volver a medir otro día.
      PrismHubStorage.settings.put(
        _claveGuardada,
        Map<String, bool>.from(_decidido),
      );
    }

    if (esApaisada(paquete) != antes) {
      WidgetsBinding.instance.addPostFrameCallback((_) => revision.value++);
    }
  }
}
