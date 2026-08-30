import 'dart:async';

import 'package:prismhub/utils/log.dart';
import 'package:prismhub/utils/platform_tv.dart';
import 'package:prismhub/utils/prismhub_storage.dart';

/// Baja el nivel del aparato en caliente si la app va a tirones de verdad.
///
/// ── El agujero que tapa ─────────────────────────────────────────────────────
///
/// El nivel del aparato se decide al arrancar, mirando memoria y núcleos. Eso
/// contesta «¿cuánto puede este aparato?», y suele acertar. Pero no contesta
/// «¿cuánto puede AHORA?», que es otra cosa: el televisor puede tener otra app
/// abierta detrás, el sistema puede estar actualizándose, o el aparato puede
/// ser uno que los números no delatan —hay televisores con 2 GB que rinden peor
/// que otros con 1—.
///
/// La app ya medía cada cuadro y lo escribía en el registro. Lo que faltaba era
/// hacer algo con esa medición.
///
/// ── Cómo decide, y por qué así ──────────────────────────────────────────────
///
/// Un cuadro lento suelto no significa nada: pasa al abrir una pantalla, al
/// cargar una imagen grande, cada vez que el recolector de basura entra. Lo que
/// sí significa algo es que la mayoría de los cuadros de un tramo seguido vayan
/// lentos, y que eso se repita.
///
/// Por eso se mira una ventana de cuadros y se pide que se cumplan DOS ventanas
/// seguidas. Una sola podría ser una pantalla pesada abriéndose.
///
/// ── Y lo que NO hace, a propósito ───────────────────────────────────────────
///
/// **No baja durante el arranque.** Los primeros segundos son los más pesados
/// de toda la sesión —se cargan las extensiones, se piden los carruseles, se
/// decodifican decenas de portadas— y son transitorios. Bajar ahí condenaría a
/// la sesión entera por su peor minuto.
///
/// **No vuelve a subir.** Subir y bajar solo es cómo se llega a una app que
/// cambia de comportamiento cada treinta segundos, que se nota más que ir un
/// poco más lento. Se baja una vez y se queda.
///
/// **No baja más de un escalón.** Si con un escalón menos sigue yendo mal, el
/// problema no es el nivel y bajarlo otra vez solo empeora la imagen sin
/// arreglar nada. Queda escrito en el registro, que es lo que hace falta.
///
/// **Se puede deshacer.** Si alguna vez bajara el nivel de un aparato que sí
/// podía, en Ajustes → PrismHub+ está «volver a medir», que olvida lo aprendido
/// y arranca de cero. Es la única salida que hace falta: lo demás no es una
/// preferencia sino la app enterándose de con qué cuenta.
class DegradacionEnCaliente {
  DegradacionEnCaliente._();

  /// Cuántos cuadros se miran de una vez.
  ///
  /// 180: a 60 por segundo son unos tres segundos, que es el tiempo que uno
  /// tarda en decir «esto va a tirones». Menos sería reaccionar a un tropiezo;
  /// mucho más, tardar en reaccionar a algo que ya se está viendo.
  static const _cuadrosPorVentana = 180;

  /// A partir de cuánto un cuadro cuenta como lento, en milisegundos.
  ///
  /// 32 ms es haber perdido un cuadro a 60 Hz con margen. No se usa el umbral
  /// del registro (50 ms) porque ese está puesto para no llenarlo de líneas, y
  /// acá lo que interesa es la fluidez, que se rompe antes.
  static const _lentoMs = 32;

  /// Qué proporción de la ventana tiene que ir lenta.
  ///
  /// 40 %: por debajo de eso hay tirones pero la app se sigue usando; por
  /// encima, se nota en todo lo que uno toca.
  static const _proporcionParaBajar = 0.4;

  /// Cuántas ventanas seguidas hacen falta.
  static const _ventanasSeguidas = 2;

  /// Cuánto se espera desde el arranque antes de juzgar nada.
  ///
  /// Los primeros veinte segundos son los más pesados de la sesión y son
  /// transitorios. Ver la nota de la clase.
  static const _graciaAlArrancar = Duration(seconds: 20);

  static DateTime? _arranque;
  static int _enLaVentana = 0;
  static int _lentosEnLaVentana = 0;
  static int _ventanasMalasSeguidas = 0;
  static bool _yaBajo = false;

  /// Se llama una vez, al arrancar, para saber desde cuándo contar la gracia.
  static void empezar() {
    _arranque = DateTime.now();
  }

  /// Se le pasa cada cuadro medido. Tiene que ser barato: corre en cada cuadro.
  static void mirarCuadro(int totalMs) {
    if (_yaBajo) return;
    final desde = _arranque;
    if (desde == null) return;
    if (DateTime.now().difference(desde) < _graciaAlArrancar) return;
    // El nivel más bajo no tiene a dónde bajar.
    if (PerfilDeAparato.nivel == NivelDeAparato.bajo) {
      _yaBajo = true;
      return;
    }

    _enLaVentana++;
    if (totalMs >= _lentoMs) _lentosEnLaVentana++;
    if (_enLaVentana < _cuadrosPorVentana) return;

    final proporcion = _lentosEnLaVentana / _enLaVentana;
    final mala = proporcion >= _proporcionParaBajar;
    _ventanasMalasSeguidas = mala ? _ventanasMalasSeguidas + 1 : 0;
    final porcentaje = (proporcion * 100).round();
    _enLaVentana = 0;
    _lentosEnLaVentana = 0;

    if (_ventanasMalasSeguidas < _ventanasSeguidas) return;
    _yaBajo = true;
    _bajarUnEscalon(porcentaje);
  }

  static void _bajarUnEscalon(int porcentaje) {
    final antes = PerfilDeAparato.nivel;
    final despues = antes == NivelDeAparato.alto
        ? NivelDeAparato.medio
        : NivelDeAparato.bajo;
    PerfilDeAparato.nivel = despues;
    logger.warning(
      'PrismHub+ bajó el nivel de ${antes.name} a ${despues.name}: el '
      '$porcentaje % de los cuadros iba lento durante varios segundos '
      'seguidos. Los números del aparato decían que podía con más de lo que '
      'está pudiendo ahora mismo.',
    );
    // Se guarda para el arranque siguiente.
    //
    // Sin esto, cada vez que se abre la app se vuelve a pagar el rato de ir a
    // tirones hasta que esto salte de nuevo. Con esto, un aparato que ya se
    // demostró más lento de lo que decían sus números arranca directamente
    // donde corresponde.
    //
    // Con `catchError` y no con try/catch: `setSetting` guarda en disco y falla
    // de forma ASÍNCRONA, así que un try alrededor de la llamada no atrapa
    // nada y el fallo sale como error sin manejar — justo en el momento en que
    // esto actúa, que es el peor. Se descubrió con la prueba de acá al lado.
    //
    // Que no se pueda recordar no invalida haberlo bajado en esta sesión.
    unawaited(
      PrismHubStorage.setSetting(SettingKey.nivelRebajado, despues.name)
          .catchError((Object e) {
        logger.info('PrismHub+: no se pudo recordar el nivel rebajado — $e');
      }),
    );
  }

  /// El nivel rebajado de una sesión anterior, si lo hubo.
  ///
  /// Se aplica al arrancar, después de medir el aparato: lo que se aprendió
  /// usándolo vale más que lo que dicen sus números.
  static void aplicarLoAprendido() {
    final Object? guardado;
    try {
      guardado = PrismHubStorage.getSetting(SettingKey.nivelRebajado);
    } catch (_) {
      // Sin almacenamiento no hay nada que aplicar, y no es un fallo.
      return;
    }
    if (guardado is! String || guardado.isEmpty) return;
    final rebajado = NivelDeAparato.values
        .where((n) => n.name == guardado)
        .firstOrNull;
    if (rebajado == null) return;
    // Solo si es MÁS bajo que el que se acaba de medir: si el aparato mejoró
    // —o si la medición de antes era de otra situación— no hay que castigarlo
    // para siempre por una sesión mala.
    if (rebajado.index <= PerfilDeAparato.nivel.index) return;
    logger.info(
      'PrismHub+: en una sesión anterior este aparato fue más lento de lo que '
      'dicen sus números, así que arranca en ${rebajado.name} en vez de '
      '${PerfilDeAparato.nivel.name}.',
    );
    PerfilDeAparato.nivel = rebajado;
    _yaBajo = true;
  }

  /// Olvida lo aprendido, para volver a medir el aparato desde cero.
  static Future<void> olvidar() async {
    _yaBajo = false;
    _ventanasMalasSeguidas = 0;
    try {
      await PrismHubStorage.setSetting(SettingKey.nivelRebajado, '');
    } catch (e) {
      logger.info('PrismHub+: no se pudo olvidar el nivel rebajado — $e');
    }
  }

  /// Para las pruebas: deja todo como recién arrancado.
  static void reiniciarParaPruebas({DateTime? arranque}) {
    _arranque = arranque;
    _enLaVentana = 0;
    _lentosEnLaVentana = 0;
    _ventanasMalasSeguidas = 0;
    _yaBajo = false;
  }

  /// Para las pruebas: si ya bajó el nivel en esta sesión.
  static bool get yaBajo => _yaBajo;
}
