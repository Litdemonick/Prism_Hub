// Que portadas se llevan en una copia y cuales no.
//
// Existe por un fallo visto en vivo: al importar, las tarjetas de VIDEO
// quedaban oscuras y las de LECTURA no. La causa es que en video la portada
// puede ser la captura del fotograma donde quedaste, y eso se guarda como una
// RUTA DEL DISCO (ver PortadaHistorial.de). Esa ruta viaja perfecta dentro del
// archivo, llega al otro equipo, y ahi apunta a algo que no existe.

import 'package:flutter_test/flutter_test.dart';
import 'package:prismhub/utils/copia_seguridad.dart';

void main() {
  String? p(Object? v) => CopiaSeguridad.portadaDePrueba(v);

  test('una portada de red pasa entera', () {
    const url = 'https://cdn.jkanime.net/assets/images/animes/x.jpg';
    expect(p(url), url);
    expect(p('http://sitio.com/x.png'), 'http://sitio.com/x.png');
  });

  test('sin esquema pero de red tambien pasa', () {
    // "//cdn/x.jpg" es una forma normalisima de escribirlas en la web.
    expect(p('//cdn.sitio.com/x.jpg'), '//cdn.sitio.com/x.jpg');
  });

  group('las rutas del disco se descartan', () {
    test('Android y Linux', () {
      // Esta es la que se colaba: no trae esquema, igual que "//cdn/x.jpg".
      expect(p('/data/user/0/com.prismhub.app/cache/frames/x.jpg'), isNull);
      expect(p('/home/alguien/imagen.png'), isNull);
    });

    test('Windows', () {
      expect(p(r'C:\Users\Alguien\AppData\frames\x.jpg'), isNull);
      expect(p('D:/carpeta/x.jpg'), isNull);
    });

    test('con esquema file:', () {
      expect(p('file:///data/x.jpg'), isNull);
      expect(p('FILE:///data/x.jpg'), isNull);
    });
  });

  test('esquemas que no son de red se descartan', () {
    expect(p('javascript:alert(1)'), isNull);
    expect(p('data:image/png;base64,AAAA'), isNull);
  });

  test('descartarla no descarta el registro', () {
    // Devuelve null y el registro entra SIN portada: el otro equipo se la
    // consigue solo, que ademas es la imagen buena y no la captura de la
    // sesion de otra persona.
    expect(p(''), isNull);
    expect(p(null), isNull);
    expect(p(123), isNull);
  });
}
