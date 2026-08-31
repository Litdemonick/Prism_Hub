import 'package:flutter_test/flutter_test.dart';
import 'package:prismhub/utils/degradacion_en_caliente.dart';
import 'package:prismhub/utils/platform_tv.dart';

/// El vigilante que baja el nivel del aparato cuando la app va a tirones.
///
/// Se prueba sin pantalla: lo que hay que asegurar es CUÁNDO decide bajar, y
/// eso son cuentas sobre los tiempos de cada cuadro. Provocar tirones de verdad
/// en una prueba no se puede, y provocarlos «casi» daría una prueba que pasa o
/// falla según la máquina donde corra.
void main() {
  /// Le da de comer [cuantos] cuadros, de los cuales [lentos] van lentos.
  void alimentar({required int cuantos, required int lentos}) {
    for (var i = 0; i < cuantos; i++) {
      DegradacionEnCaliente.mirarCuadro(i < lentos ? 40 : 8);
    }
  }

  setUp(() {
    // Arranque muy atrás, para que la gracia de los primeros veinte segundos
    // no tape lo que se está probando. Ese caso tiene su prueba aparte.
    DegradacionEnCaliente.reiniciarParaPruebas(
      arranque: DateTime.now().subtract(const Duration(minutes: 5)),
    );
    PerfilDeAparato.nivel = NivelDeAparato.alto;
  });

  group('cuándo baja el nivel', () {
    test('con todo yendo bien no toca nada', () {
      alimentar(cuantos: 1000, lentos: 0);
      expect(PerfilDeAparato.nivel, NivelDeAparato.alto);
      expect(DegradacionEnCaliente.yaBajo, isFalse);
    });

    test('unos pocos cuadros lentos sueltos no bastan', () {
      // Pasa constantemente: al abrir una pantalla, al cargar una imagen
      // grande, cada vez que entra el recolector de basura. Reaccionar a eso
      // sería bajarle el nivel a cualquier aparato.
      alimentar(cuantos: 360, lentos: 40);
      expect(PerfilDeAparato.nivel, NivelDeAparato.alto);
    });

    test('una sola ventana mala tampoco: puede ser una pantalla pesada', () {
      alimentar(cuantos: 180, lentos: 180);
      expect(PerfilDeAparato.nivel, NivelDeAparato.alto,
          reason: 'hacen falta dos ventanas seguidas');
    });

    test('dos ventanas malas seguidas sí bajan un escalón', () {
      alimentar(cuantos: 360, lentos: 360);
      expect(PerfilDeAparato.nivel, NivelDeAparato.medio);
      expect(DegradacionEnCaliente.yaBajo, isTrue);
    });

    test('una ventana buena en el medio corta la racha', () {
      alimentar(cuantos: 180, lentos: 180);
      alimentar(cuantos: 180, lentos: 0);
      alimentar(cuantos: 180, lentos: 180);
      expect(PerfilDeAparato.nivel, NivelDeAparato.alto,
          reason: 'la racha se cortó, así que vuelve a hacer falta otra');
    });

    test('baja UN escalón y no sigue bajando', () {
      // Si con un escalón menos sigue yendo mal, el problema no es el nivel.
      alimentar(cuantos: 3600, lentos: 3600);
      expect(PerfilDeAparato.nivel, NivelDeAparato.medio);
    });

    test('desde el nivel más bajo no hay a dónde bajar', () {
      PerfilDeAparato.nivel = NivelDeAparato.bajo;
      alimentar(cuantos: 3600, lentos: 3600);
      expect(PerfilDeAparato.nivel, NivelDeAparato.bajo);
    });
  });

  group('la gracia del arranque', () {
    test('durante los primeros segundos no juzga', () {
      // Los primeros segundos son los más pesados de toda la sesión —se cargan
      // las extensiones, se piden los carruseles, se decodifican decenas de
      // portadas— y son transitorios. Bajar ahí condenaría a la sesión entera
      // por su peor minuto.
      DegradacionEnCaliente.reiniciarParaPruebas(arranque: DateTime.now());
      PerfilDeAparato.nivel = NivelDeAparato.alto;
      alimentar(cuantos: 3600, lentos: 3600);
      expect(PerfilDeAparato.nivel, NivelDeAparato.alto);
    });

    test('sin haber arrancado, tampoco', () {
      DegradacionEnCaliente.reiniciarParaPruebas();
      PerfilDeAparato.nivel = NivelDeAparato.alto;
      alimentar(cuantos: 3600, lentos: 3600);
      expect(PerfilDeAparato.nivel, NivelDeAparato.alto);
    });
  });

  group('la rebaja caduca sola', () {
    // El botón de Ajustes para volver a medir el aparato se sacó — nada de lo
    // que PrismHub+ decide se toca desde la interfaz—, así que esta es ahora
    // la ÚNICA salida si una racha mala rebaja a un aparato que sí podía.
    // Si esto se rompe, ese aparato queda recortado para siempre y sin nadie
    // que pueda arreglarlo.
    final ahora = DateTime(2026, 8, 30, 12);

    String anotado(NivelDeAparato n, Duration hace) =>
        '${n.name}|${ahora.subtract(hace).millisecondsSinceEpoch}';

    test('una rebaja reciente vale', () {
      expect(
        DegradacionEnCaliente.loAprendidoDe(
          anotado(NivelDeAparato.medio, const Duration(days: 3)),
          ahora: ahora,
        ),
        NivelDeAparato.medio,
      );
    });

    test('justo en el plazo todavía vale', () {
      expect(
        DegradacionEnCaliente.loAprendidoDe(
          anotado(NivelDeAparato.bajo, DegradacionEnCaliente.caducidad),
          ahora: ahora,
        ),
        NivelDeAparato.bajo,
      );
    });

    test('pasado el plazo se olvida', () {
      expect(
        DegradacionEnCaliente.loAprendidoDe(
          anotado(NivelDeAparato.bajo,
              DegradacionEnCaliente.caducidad + const Duration(minutes: 1)),
          ahora: ahora,
        ),
        isNull,
      );
    });

    test('una fecha en el futuro se olvida, no dura para siempre', () {
      // Pasa de verdad: alcanza con que el reloj del aparato estuviera
      // adelantado cuando se anotó. Restando a secas, el plazo sale negativo
      // y la rebaja no caducaría nunca.
      expect(
        DegradacionEnCaliente.loAprendidoDe(
          anotado(NivelDeAparato.bajo, const Duration(days: -400)),
          ahora: ahora,
        ),
        isNull,
      );
    });

    test('lo guardado por una versión vieja, sin fecha, sigue valiendo', () {
      // Antes se guardaba solo el nombre del nivel. Descartarlo haría que
      // todo el que actualice pague de nuevo el rato de ir a tirones.
      expect(
        DegradacionEnCaliente.loAprendidoDe('bajo', ahora: ahora),
        NivelDeAparato.bajo,
      );
    });

    test('basura guardada no se aplica', () {
      expect(DegradacionEnCaliente.loAprendidoDe('', ahora: ahora), isNull);
      expect(
        DegradacionEnCaliente.loAprendidoDe('lentisimo|123', ahora: ahora),
        isNull,
      );
      expect(
        DegradacionEnCaliente.loAprendidoDe('bajo|no-es-un-numero',
            ahora: ahora),
        isNull,
      );
    });
  });
}
