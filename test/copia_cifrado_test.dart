// La clave de la copia de seguridad.
//
// El archivo lleva el historial completo, incluido el de la Zona +18: es
// exactamente lo que no puede leerse si termina en una carpeta compartida o en
// un teléfono prestado. Estas pruebas comprueban que la clave sirve de verdad y
// no solo de cartel.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:prismhub/utils/copia_cifrado.dart';

void main() {
  const secreto = '{"historial":[{"title":"algo muy privado"}]}';

  test('lo que se cierra con una clave se abre con esa clave', () {
    final c = CopiaCifrado.cerrar(secreto, 'mi clave 123');
    final abierto = CopiaCifrado.abrir(
      sal: c.sal,
      nonce: c.nonce,
      datos: c.datos,
      clave: 'mi clave 123',
    );
    expect(abierto, secreto);
  });

  test('con otra clave no se abre', () {
    final c = CopiaCifrado.cerrar(secreto, 'la buena');
    expect(
      CopiaCifrado.abrir(
        sal: c.sal,
        nonce: c.nonce,
        datos: c.datos,
        clave: 'la mala',
      ),
      isNull,
    );
  });

  test('una clave casi igual tampoco abre', () {
    final c = CopiaCifrado.cerrar(secreto, 'Clave123');
    for (final intento in ['clave123', 'Clave124', 'Clave123 ', '']) {
      expect(
        CopiaCifrado.abrir(
            sal: c.sal, nonce: c.nonce, datos: c.datos, clave: intento),
        isNull,
        reason: 'abrió con "$intento"',
      );
    }
  });

  test('el contenido no se ve en el archivo', () {
    final c = CopiaCifrado.cerrar(secreto, 'x');
    expect(c.datos.contains('privado'), isFalse);
    expect(utf8.decode(base64Decode(c.datos), allowMalformed: true)
        .contains('privado'), isFalse);
  });

  test('si tocaron el archivo, no se abre', () {
    // AES-GCM no solo oculta: detecta que le cambiaron algo. Sin esto se
    // devolverían datos a medias que después irían derecho a la base.
    final c = CopiaCifrado.cerrar(secreto, 'clave');
    final bytes = base64Decode(c.datos);
    bytes[0] = bytes[0] ^ 0xFF;
    expect(
      CopiaCifrado.abrir(
        sal: c.sal,
        nonce: c.nonce,
        datos: base64Encode(bytes),
        clave: 'clave',
      ),
      isNull,
    );
  });

  test('la misma clave da un archivo distinto cada vez', () {
    // La sal y el nonce son nuevos en cada copia. Si no, dos copias del mismo
    // contenido se verían idénticas y eso ya filtra información.
    final a = CopiaCifrado.cerrar(secreto, 'igual');
    final b = CopiaCifrado.cerrar(secreto, 'igual');
    expect(a.sal, isNot(b.sal));
    expect(a.nonce, isNot(b.nonce));
    expect(a.datos, isNot(b.datos));
  });

  test('un archivo con basura no revienta, devuelve null', () {
    expect(
      CopiaCifrado.abrir(
          sal: 'no-es-base64!!', nonce: 'x', datos: 'y', clave: 'z'),
      isNull,
    );
  });
}
