import 'dart:async';
import 'dart:collection';

import 'package:dio/dio.dart';
import 'package:prismhub/utils/platform_tv.dart';
import 'package:prismhub/utils/prismhub_mas.dart';

/// Cuántas cosas pueden estar en el aire a la vez.
///
/// Se prueba sola, sin red: lo que hay que asegurar es que nunca deje pasar más
/// de las que se le dijeron, que siempre libere el sitio —también cuando lo que
/// estaba haciendo falla— y que no se quede nadie esperando para siempre.
class ColaDeConcurrencia {
  ColaDeConcurrencia(int tope) : _tope = (() => tope);

  /// Con el tope leído cada vez en vez de fijado al construirla.
  ///
  /// Hace falta porque PrismHub+ se puede apagar desde Ajustes y eso tiene que
  /// notarse sin reiniciar la app. Con el número copiado al arrancar, la cola
  /// se quedaba con el tope de cuando se creó.
  ColaDeConcurrencia.segun(int Function() tope) : _tope = tope;

  final int Function() _tope;

  /// Cuántas a la vez. Con 0 o menos no hay cola: pasa todo.
  int get tope => _tope();

  var _enVuelo = 0;
  final _esperando = Queue<Completer<void>>();

  int get enVuelo => _enVuelo;
  int get haciendoCola => _esperando.length;

  /// Espera a que haya sitio. Hay que llamar a [salir] sí o sí después.
  Future<void> entrar() {
    if (tope <= 0) return Future<void>.value();
    if (_enVuelo < tope) {
      _enVuelo++;
      return Future<void>.value();
    }
    final turno = Completer<void>();
    _esperando.add(turno);
    return turno.future;
  }

  /// Devuelve el sitio y le da paso al siguiente.
  void salir() {
    if (tope <= 0) return;
    final siguiente = _esperando.isEmpty ? null : _esperando.removeFirst();
    if (siguiente != null) {
      // El sitio pasa directo al siguiente: no se baja el contador y se vuelve
      // a subir, porque entre las dos cosas podría colarse otro.
      if (!siguiente.isCompleted) siguiente.complete();
      return;
    }
    if (_enVuelo > 0) _enVuelo--;
  }
}

/// Frena cuántas peticiones de extensiones corren a la vez.
///
/// ── El problema que resuelve ────────────────────────────────────────────────
///
/// Al abrir la app, todas las zonas piden sus carruseles a la vez y cada
/// extensión dispara las suyas. Medido en un televisor MediaTek de 0,9 GB con
/// Android 9 y cuatro núcleos: **unas ciento treinta peticiones en catorce
/// segundos**, y en esa misma ventana el sistema pidió memoria cuatro veces
/// —bajando el techo de imágenes de 48 a 28 MB— con los cuadros lentos
/// concentrados justo ahí.
///
/// Una de esas peticiones tardó 15,4 segundos. En un teléfono, la misma tardaba
/// menos de uno. No es que el sitio fuera lento: era la propia app compitiendo
/// consigo misma por cuatro núcleos y por lo poco que quedaba de memoria.
///
/// ── Por qué esto no hace las cosas más lentas ───────────────────────────────
///
/// Porque un aparato que no puede atender treinta conexiones a la vez no las
/// atiende igual: las encola el sistema operativo, más abajo y peor. Cada
/// conexión abierta cuesta su saludo TLS y sus búferes, y cada respuesta trae
/// una portada que hay que decodificar. Ponerles turno arriba es hacer visible
/// —y controlable— una cola que ya existía.
///
/// Los navegadores hacen exactamente esto desde siempre, con seis por sitio.
///
/// ── Y por qué solo en aparatos modestos ─────────────────────────────────────
///
/// En un teléfono actual o un PC no hay nada que arreglar: las mismas peticiones
/// entran en menos de un segundo y el sistema no pide memoria ni una vez. Poner
/// un tope ahí solo podría empeorarlo, así que no se pone.
class ColaDeExtensiones extends Interceptor {
  /// Cuántas peticiones de extensiones a la vez, según el aparato.
  ///
  /// Cuatro en uno modesto: alcanza para que la espera de la red se solape
  /// —que es de lo que se trata— sin que cuatro núcleos tengan que repartirse
  /// treinta descifrados de TLS y treinta decodificaciones de imagen a la vez.
  ///
  /// Ocho en uno medio, que aguanta más pero tampoco es un teléfono nuevo.
  ///
  /// Sin tope en el resto: ver la nota de la clase.
  /// Lo decide PrismHub+, que es donde están todos los ajustes por aparato.
  /// Se conserva acá para poder probarlo sin montar el resto.
  static int topeParaNivel(NivelDeAparato nivel) => switch (nivel) {
        NivelDeAparato.bajo => 4,
        NivelDeAparato.medio => 8,
        NivelDeAparato.alto => 0,
      };

  /// La cola es ÚNICA para todas las extensiones.
  ///
  /// Hay un cliente HTTP por extensión, así que una cola por cliente no serviría
  /// de nada: con trece extensiones y cuatro cada una siguen siendo cincuenta y
  /// dos a la vez. Lo que satura al aparato es el total, no el reparto.
  static final ColaDeConcurrencia cola =
      ColaDeConcurrencia.segun(() => PrismHubMas.peticionesALaVez);

  /// La marca que dice que esta petición ya tomó su sitio.
  ///
  /// Hace falta para no devolver el sitio dos veces: Dio puede llamar al
  /// interceptor de error después del de respuesta en algunos caminos, y dos
  /// `salir()` por una sola `entrar()` dejarían la cuenta rota y el tope sin
  /// efecto para el resto de la sesión.
  static const _marca = 'prismhub-cola';

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    await cola.entrar();
    options.extra[_marca] = true;
    handler.next(options);
  }

  @override
  void onResponse(
      Response<dynamic> response, ResponseInterceptorHandler handler) {
    _devolver(response.requestOptions);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _devolver(err.requestOptions);
    handler.next(err);
  }

  void _devolver(RequestOptions options) {
    if (options.extra.remove(_marca) == true) cola.salir();
  }
}
