import 'dart:async';

/// Prueba varios sitios de descarga solapándolos, pero sin bajar dos veces.
///
/// ── El problema que resuelve ────────────────────────────────────────────────
///
/// Un mismo pedacito de vídeo suele estar en varios nodos de un CDN. Probarlos
/// de a uno significa aguantarle a cada nodo caído su plazo entero antes de
/// pasar al siguiente. Medido en un teléfono con jkanime, cinco nodos caídos
/// seguidos:
///
///     cdn6 no dio el pedacito en 8001 ms, se prueba otro nodo
///     cdn4 no dio el pedacito en 8001 ms, se prueba otro nodo
///     cdn1 no dio el pedacito en 8006 ms, se prueba otro nodo
///     cdn2 no dio el pedacito en 8014 ms, se prueba otro nodo
///     cdn5 no dio el pedacito en 8007 ms, se prueba otro nodo
///
/// Cuarenta segundos mirando una rueda para terminar bajando de un nodo que
/// contestaba en dos.
///
/// ── Y por qué no se lanzan todos de una ─────────────────────────────────────
///
/// Porque sería bajar el mismo pedacito seis veces con los datos de la persona.
/// La regla es sumar nodos **de a uno, y solo mientras ninguno dé señales**: en
/// cuanto uno empieza a mandar bytes se deja de sumar y se lo espera a él.
///
/// La diferencia entre «muerto» y «lento» la marca [darSenales]: el muerto no
/// manda nada, el lento manda despacio. Sin esa señal habría que elegir entre
/// esperar de más al muerto o duplicar la descarga del lento.
///
/// ── Qué garantiza ───────────────────────────────────────────────────────────
///
///  - Devuelve el primer resultado bueno que llegue.
///  - Devuelve null solo cuando TODOS los candidatos fallaron. Nunca se queda
///    esperando para siempre, ni siquiera si el que estaba contestando se cae
///    después de haber mandado bytes.
///  - Con un candidato sano no lanza ninguna petición de más.
class CarreraDeNodos {
  CarreraDeNodos._();

  /// [intentar] recibe el candidato y una función que ese intento debe llamar
  /// en cuanto reciba la primera señal de vida. [alFallar] se avisa por cada
  /// intento que no pudo, para dejarlo anotado.
  ///
  /// [paciencia] es cuánto se espera sin señales antes de sumar otro candidato.
  /// [tope] es lo máximo que se espera a uno que sí está contestando.
  static Future<T?> correr<C, T>({
    required List<C> candidatos,
    required Future<T> Function(C cual, void Function() darSenales) intentar,
    required Duration paciencia,
    required Duration tope,
    void Function(C cual, Object error)? alFallar,
    void Function(C cual, T resultado)? alGanar,
  }) async {
    if (candidatos.isEmpty) return null;

    final resultado = Completer<T?>();
    var lanzados = 0;
    var fallados = 0;
    var todosLanzados = false;
    var alguienContesta = false;

    // Para despertar al que espera en vez de sondearlo. Se rehace en cada aviso
    // porque un Completer se completa una sola vez.
    Completer<void>? cambio;
    void avisar() {
      final c = cambio;
      cambio = null;
      if (c != null && !c.isCompleted) c.complete();
    }

    void quizaRendirse() {
      if (resultado.isCompleted) return;
      // Solo cuando no queda nadie: ni en el aire, ni por lanzar.
      if (todosLanzados && fallados == lanzados) resultado.complete(null);
    }

    void lanzar(C cual) {
      lanzados++;
      unawaited(() async {
        try {
          final valor = await intentar(cual, () {
            alguienContesta = true;
            avisar();
          }).timeout(tope);
          if (resultado.isCompleted) {
            // Llegó segundo. Los dos andaban; esto ya no le sirve a nadie.
            return;
          }
          alGanar?.call(cual, valor);
          resultado.complete(valor);
        } catch (e) {
          fallados++;
          alFallar?.call(cual, e);
          quizaRendirse();
        } finally {
          avisar();
        }
      }());
    }

    /// Espera a que [listo] se cumpla, o a que se acabe [cuanto].
    Future<void> esperar(bool Function() listo, Duration cuanto) async {
      final hasta = DateTime.now().add(cuanto);
      while (!listo()) {
        final resta = hasta.difference(DateTime.now());
        if (resta <= Duration.zero) return;
        final c = cambio ??= Completer<void>();
        await Future.any<void>([c.future, Future<void>.delayed(resta)]);
      }
    }

    for (var i = 0; i < candidatos.length; i++) {
      lanzar(candidatos[i]);
      if (i == candidatos.length - 1) todosLanzados = true;

      // 1) ¿Da señales alguno dentro de la paciencia?
      await esperar(
        () => resultado.isCompleted || alguienContesta || fallados == lanzados,
        paciencia,
      );
      if (resultado.isCompleted) break;

      // 2) Con uno mandando bytes no se suma nadie: sumar acá sería bajar lo
      //    mismo dos veces.
      if (alguienContesta) {
        await esperar(
          () => resultado.isCompleted || fallados == lanzados,
          tope,
        );
        if (resultado.isCompleted) break;
        // Se cayó igual, después de haber mandado algo. Se sigue con el
        // siguiente candidato en vez de darse por vencido — este es
        // justamente el caso en el que una versión anterior se quedaba
        // esperando para siempre.
        alguienContesta = false;
      }
    }
    // Puede quedar alguno en el aire: si termina bien completa el resultado, y
    // si falla, esto ya está en true y se rinde por el camino de arriba.
    todosLanzados = true;
    quizaRendirse();
    return resultado.future;
  }
}
