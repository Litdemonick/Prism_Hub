import 'package:flutter_test/flutter_test.dart';
import 'package:prismhub/utils/bloqueador_anuncios.dart';

/// Guardias contra el fallo que dejó Android inservible el 2026-08-06.
///
/// El bloqueador tenía DOS caminos que crecían con la cantidad de dominios, y
/// con las listas de fábrica puestas (326.685) los dos se volvían impagables en
/// el teléfono. En la computadora no se notaba, así que desde afuera parecía que
/// fallaban las extensiones.
///
/// No se prueba "que sea rápido" con un reloj —eso da falsos fallos en una
/// máquina cargada—, sino **que no vuelva a aparecer la forma que era lenta**.

void main() {
  group('el bloqueo nativo del WebView', () {
    test('fuera de Android no se construye ninguna regla', () {
      // En Windows el valor nativo de la acción "bloquear" resuelve a null y
      // construir una sola regla tumba la pantalla entera. Esta prueba corre en
      // el escritorio, así que comprueba justo eso.
      expect(BloqueadorAnuncios.reglasNativas('https://unlimplay.com/f/1'),
          isEmpty);
    });

    test('Mega queda marcado para abrirse SIN bloqueo nativo', () {
      // Medido por el usuario el 2026-08-06: con el bloqueador encendido Mega
      // no carga en Android, y apagado sí. No es que las reglas coincidan con
      // algo suyo —se comprobó dirección por dirección— sino que estar puestas
      // obliga al motor a interceptar cada pedido.
      expect(BloqueadorAnuncios.sinBloqueoNativo('https://mega.nz/embed/abc'),
          isTrue);
      expect(
          BloqueadorAnuncios.sinBloqueoNativo('https://g.api.mega.co.nz/cs'),
          isTrue);
    });

    test('los demás servidores SÍ llevan bloqueo nativo', () {
      // El anuncio de vídeo entra por un `<script src>` ya escrito en el HTML,
      // y ahí el guion no llega: solo lo corta el motor. Visto en vivo en
      // unlimplay.com — «el guion está en la página · no cortó nada» y salió el
      // anuncio igual.
      for (final u in [
        'https://unlimplay.com/f/embed/tv/82452/1/1',
        'https://mixdrop.top/e/abc',
        'https://vimeos.net/embed-abc.html',
      ]) {
        expect(BloqueadorAnuncios.sinBloqueoNativo(u), isFalse, reason: u);
      }
    });

    test('el patrón nativo es chico y reconoce subdominios sin pasarse', () {
      // Con las listas del usuario adentro llegó a medir 6,9 MB y el motor
      // tardaba 574 ms por pedido. Solo va la base de fábrica.
      final patron = BloqueadorAnuncios.patronPara(['anuncios.com']);
      expect(patron, isNotNull);
      expect(patron!.length, lessThan(10 * 1024));
      final re = RegExp(patron, caseSensitive: false);
      expect(re.hasMatch('https://cdn.anuncios.com/x.js'), isTrue);
      expect(re.hasMatch('https://noanuncios.com/x.js'), isFalse,
          reason: 'no es subdominio: no puede caer');
      expect(re.hasMatch('https://anuncios.com.ar/x.js'), isFalse,
          reason: 'es otro dominio');
    });
  });

  group('el guion inyectado no puede recorrer la lista entera', () {
    test('usa un conjunto y pregunta por los dominios padre', () {
      final guion = BloqueadorAnuncios.guionPara(['anuncios.com', 'rastreo.net']);
      expect(guion, isNotEmpty);

      expect(guion, contains('new Set('),
          reason: 'los dominios van en un conjunto: recorrerlos uno por uno '
              'costaba 6,79 ms por pedido con la mitad de las listas puestas');
      expect(guion, contains('dominios.has('),
          reason: 'la consulta tiene que ser al conjunto');

      // La forma vieja, la que dejaba el teléfono muerto. Que no vuelva.
      expect(guion.contains("h.endsWith('.' + dominios["), isFalse,
          reason: 'ese era el barrido lineal sobre la lista entera');
      expect(guion.contains('dominios.length'), isFalse,
          reason: 'un conjunto no tiene length: si esto aparece, volvió a ser '
              'una lista');
    });

    test('sin dominios no se inyecta nada', () {
      expect(BloqueadorAnuncios.guionPara(const []), isEmpty);
    });

    test('los dominios viajan tal cual al guion', () {
      final guion = BloqueadorAnuncios.guionPara(['anuncios.com', 'rastreo.net']);
      expect(guion, contains('"anuncios.com"'));
      expect(guion, contains('"rastreo.net"'));
    });
  });
}
