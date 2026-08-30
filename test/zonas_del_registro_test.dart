// Que cada línea del registro caiga en la zona que le toca.
//
// Estas reglas deciden qué se ve al filtrar y qué sale en cada sección del
// archivo exportado. Un error acá no se nota mirando: la pantalla se ve
// perfecta, simplemente le falta la línea que explicaba el fallo. Por eso se
// comprueba con líneas reales de la app y no a ojo.

import 'package:flutter_test/flutter_test.dart';
import 'package:prismhub/utils/zonas_del_registro.dart';

/// Líneas tal como las escribe la app, con el encabezado de `logging`.
String _linea(String nivel, String mensaje) =>
    'PrismHub $nivel 2026-08-29 21:45:03.123456: $mensaje';

void main() {
  group('«Todo» muestra todo', () {
    test('sin excepciones: es el punto de la zona', () {
      const muestras = [
        'cualquier cosa',
        '',
        'PrismHub INFO 2026-08-29 21:45:03.123456: algo raro',
      ];
      for (final l in muestras) {
        expect(ZonaDelRegistro.todo.acepta(l), isTrue, reason: l);
      }
    });
  });

  group('reproductor', () {
    final suyas = [
      _linea('INFO', 'recorte fMP4: se pidió 120s'),
      _linea('INFO', 'rueda apagada: primer cuadro listo'),
      _linea('INFO', 'media_kit error: algo'),
      _linea('INFO', 'mpv: cambio de pista'),
      _linea('INFO', 'exoplayer: preparado'),
      _linea('INFO', 'salto a 90s ignorado'),
      _linea('INFO', 'bomba · el servidor local falló'),
      _linea('INFO', 'FRAME LENTO detectado'),
      _linea('INFO', 'Motor de vídeo: mpv'),
      _linea('INFO', '[relay] sirviendo segmento'),
    ];
    for (final l in suyas) {
      test('entra: ${l.split(': ').last}', () {
        expect(ZonaDelRegistro.reproductor.acepta(l), isTrue);
      });
    }

    test('no se lleva lo de las extensiones', () {
      expect(
        ZonaDelRegistro.reproductor
            .acepta(_linea('INFO', '[extensiones] catálogo listo')),
        isFalse,
      );
    });
  });

  group('extensiones', () {
    final suyas = [
      _linea('INFO', '[extensiones] no se pudo reintentar'),
      _linea('INFO', '[home] 12 fichas'),
      _linea('INFO', '[catálogo] 3 zonas'),
      _linea('INFO', '[vista previa] no se pudo cargar'),
      _linea('INFO', '[sniffer/embeds] 2 candidatos'),
      _linea('INFO', '[webview-html] render listo'),
      _linea('INFO', 'switchServer: VOE'),
      _linea('INFO', 'ficha · VOE · un solo nodo'),
      _linea('INFO', 'RESULTADO · VOE · ok'),
      _linea('INFO', 'extension com.ejemplo · dijo algo'),
    ];
    for (final l in suyas) {
      test('entra: ${l.split(': ').last}', () {
        expect(ZonaDelRegistro.extensiones.acepta(l), isTrue);
      });
    }

    test('el bloqueador de anuncios NO entra: es de la app, no de una extension',
        () {
      // Sus listas se descargan al arrancar, sin ninguna extension de por
      // medio. En esta zona eran cuatro lineas de arranque que no tienen que
      // ver con lo que se busca aca.
      final l = _linea('INFO', '[bloqueador] 58052 dominios en 1 lista(s)');
      expect(ZonaDelRegistro.extensiones.acepta(l), isFalse);
      expect(esGeneral(l), isTrue);
    });

    test('no se lleva lo del reproductor', () {
      expect(
        ZonaDelRegistro.extensiones
            .acepta(_linea('INFO', 'recorte fMP4: se pidió 120s')),
        isFalse,
      );
    });
  });

  group('fallos', () {
    test('los tres niveles que no son informativos', () {
      for (final nivel in ['SEVERE', 'SHOUT', 'WARNING']) {
        expect(
          ZonaDelRegistro.fallos.acepta(_linea(nivel, 'lo que sea')),
          isTrue,
          reason: nivel,
        );
      }
    });

    test('lo informativo no entra', () {
      expect(
        ZonaDelRegistro.fallos.acepta(_linea('INFO', 'todo bien')),
        isFalse,
      );
    });

    test('el rastro de un cierre inesperado entra', () {
      expect(
        ZonaDelRegistro.fallos.acepta('LO ULTIMO QUE HIZO: +12s abre'),
        isTrue,
      );
    });

    test('un fallo del reproductor entra ADEMÁS en fallos', () {
      // Quien abre «Fallos» quiere los de todos lados, no elegir primero de
      // qué parte de la app.
      final l = _linea('WARNING', 'recorte fMP4: no se pudo bajar la lista');
      expect(ZonaDelRegistro.fallos.acepta(l), isTrue);
      expect(ZonaDelRegistro.reproductor.acepta(l), isTrue);
    });
  });

  group('nada se pierde', () {
    test('lo que no es de ninguna zona cae en general', () {
      final l = _linea('INFO', '[red] GET https://a.com/… → 200 · 120 ms');
      expect(ZonaDelRegistro.reproductor.acepta(l), isFalse);
      expect(ZonaDelRegistro.extensiones.acepta(l), isFalse);
      expect(ZonaDelRegistro.fallos.acepta(l), isFalse);
      expect(esGeneral(l), isTrue);
    });

    test('un pedido de red que falla sí aparece en fallos', () {
      final l = _linea('WARNING', '[red] GET https://a.com/… → sin conexión');
      expect(ZonaDelRegistro.fallos.acepta(l), isTrue);
    });

    test('lo que entra en una zona no cae también en general', () {
      final l = _linea('INFO', 'switchServer: VOE');
      expect(esGeneral(l), isFalse);
    });
  });

  group('la cabecera de sesión se ve con cualquier filtro', () {
    // Sin ella, lo que queda son líneas sueltas sin decir de qué arranque ni
    // de qué aparato salieron.
    const cabecera = '║      █████ █████  ███  █████ █   █           ║';
    for (final z in ZonaDelRegistro.values) {
      test('con ${z.name}', () {
        expect(z.seVe(cabecera), isTrue);
      });
    }

    test('los apartados de la presentación también, no solo el nombre', () {
      // Se miraba solo el marco de arriba, asi que «QUÉ ES ESTO» y «QUÉ NO
      // LLEVA» —dibujados con otros caracteres— desaparecían al filtrar. Se
      // veía el nombre en grande y debajo, directo, líneas técnicas.
      const apartado = '  │  · No lleva qué estuviste viendo.';
      const borde = '  ┌─ QUÉ ES ESTO ──────────────────────';
      for (final z in ZonaDelRegistro.values) {
        expect(z.seVe(apartado), isTrue, reason: '${z.name} · apartado');
        expect(z.seVe(borde), isTrue, reason: '${z.name} · borde');
      }
    });

    test('la lista de extensiones instaladas también', () {
      const linea = '  │  io.prismhub.animeav1 · v1.2.3';
      expect(ZonaDelRegistro.reproductor.seVe(linea), isTrue);
    });

    test('pero no se repite dentro de cada sección del exportado', () {
      expect(ZonaDelRegistro.reproductor.acepta(cabecera), isFalse);
    });
  });

  test('cada zona sabe cómo se titula en el archivo', () {
    expect(ZonaDelRegistro.todo.area, isNull);
    expect(ZonaDelRegistro.fallos.area, ZonaDelRegistro.fallos.seccion);
    for (final z in ZonaDelRegistro.values) {
      expect(z.seccion, isNotEmpty);
    }
  });
}
