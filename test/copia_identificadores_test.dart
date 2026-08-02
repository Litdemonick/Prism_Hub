// Direcciones y paquetes NO se limpian ni se recortan.
//
// Estas pruebas existen por un fallo real y visible: se les estaba aplicando el
// limpiador del NOMBRE de la copia, que corta a 40 caracteres y agrega «…». Al
// importar, toda dirección larga quedaba truncada y la ficha abría en "Página
// no encontrada" con cero episodios.
//
// La regla: un identificador se usa TAL CUAL o se descarta el registro.
// "Arreglarlo" lo convierte en otro identificador, que no lleva a ningún lado.

import 'package:flutter_test/flutter_test.dart';
import 'package:prismhub/utils/copia_seguridad.dart';

void main() {
  // Una de las que rompieron de verdad.
  const larga = 'https://jkanime.net/kimi-no-koto-ga-daidaidaidaidai-suki-na-'
      '100-nin-no-kanojo-2nd-season/';

  group('direcciones', () {
    test('una dirección larga pasa entera', () {
      expect(CopiaSeguridad.direccionDePrueba(larga), larga);
      expect(larga.length, greaterThan(60),
          reason: 'si no fuera larga, la prueba no probaría nada');
    });

    test('el limpiador de nombres la habría roto', () {
      // Deja constancia del fallo: si alguien vuelve a usar limpiarNombre para
      // una dirección, esto explica por qué no.
      final rota = CopiaSeguridad.limpiarNombre(larga);
      expect(rota, isNot(larga));
      expect(rota.endsWith('…'), isTrue);
    });

    test('sin esquema también vale', () {
      // Muchas extensiones guardan los enlaces así.
      expect(CopiaSeguridad.direccionDePrueba('//sitio.com/anime/x'),
          '//sitio.com/anime/x');
      expect(CopiaSeguridad.direccionDePrueba('/anime/x'), '/anime/x');
    });

    test('un esquema que no es de red se rechaza', () {
      // Sin esto, un archivo preparado a mano podría dejar en el historial una
      // entrada que se abre sola al tocar la tarjeta.
      for (final mala in [
        'javascript:alert(1)',
        'file:///etc/passwd',
        'data:text/html,<script>',
      ]) {
        expect(() => CopiaSeguridad.direccionDePrueba(mala),
            throwsA(isA<FormatException>()),
            reason: 'pasó "$mala"');
      }
    });

    test('con caracteres invisibles se descarta el registro', () {
      // No se limpian: limpiarlos cambiaría la dirección.
      expect(() => CopiaSeguridad.direccionDePrueba('https://a.com/x\u202Ey'),
          throwsA(isA<FormatException>()));
      expect(() => CopiaSeguridad.direccionDePrueba('https://a.com/x\ny'),
          throwsA(isA<FormatException>()));
    });

    test('vacía o larguísima se descarta', () {
      expect(() => CopiaSeguridad.direccionDePrueba(''),
          throwsA(isA<FormatException>()));
      expect(() => CopiaSeguridad.direccionDePrueba('https://a.com/${'x' * 3000}'),
          throwsA(isA<FormatException>()));
    });
  });

  group('portadas', () {
    test('una portada normal pasa entera', () {
      const p = 'https://cdn.jkanime.net/assets/images/animes/image/'
          'kimi-no-koto-ga-daidaidaidaidai-suki-na-100-nin-no-kanojo.jpg';
      expect(CopiaSeguridad.portadaDePrueba(p), p);
    });

    test('sin esquema vale: es como se escriben en la web', () {
      // Rechazarlas dejaba tarjetas sin imagen después de importar, que fue
      // exactamente lo que se vio.
      expect(CopiaSeguridad.portadaDePrueba('//cdn.sitio.com/x.jpg'),
          '//cdn.sitio.com/x.jpg');
    });

    test('una portada rota no rompe el registro, solo se pierde', () {
      expect(CopiaSeguridad.portadaDePrueba('javascript:x'), isNull);
      expect(CopiaSeguridad.portadaDePrueba(''), isNull);
      expect(CopiaSeguridad.portadaDePrueba(123), isNull);
    });
  });
}
