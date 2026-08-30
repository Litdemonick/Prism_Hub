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
}
