import 'package:flutter_test/flutter_test.dart';
import 'package:prismhub/utils/audio_hls.dart';

/// Los idiomas de audio de una lista HLS.
///
/// Esta lógica dio dos fallos que el usuario vio en pantalla, los dos el
/// 2026-08-06 y los dos de mirar una cadena de texto:
///
///  - En Goodstream el menú decía «Español» y se escuchaba inglés.
///  - El mismo idioma salía repetido varias veces en el menú.
///
/// Estaba metida en un archivo de miles de líneas donde no se podía probar. Se
/// sacó aparte para esto.

/// Un maestro como los que devuelven estos servidores.
const _dosIdiomas = '''
#EXTM3U
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="Español",LANGUAGE="es",DEFAULT=YES,URI="index-a1.m3u8"
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="English",LANGUAGE="en",DEFAULT=NO,URI="index-a2.m3u8"
#EXT-X-STREAM-INF:BANDWIDTH=1500000,AUDIO="audio"
index-v1-a2.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=800000,AUDIO="audio"
index-v2-a2.m3u8
''';

void main() {
  group('leer los idiomas del maestro', () {
    test('los encuentra y dice cuál viene pegado al vídeo', () {
      final r = AudioHls.delMaestro(_dosIdiomas);
      expect(r.pistas.length, 2);
      expect(r.pistas[0].nombre, 'Español');
      expect(r.pistas[1].nombre, 'English');
      // Las variantes son `-a2`, o sea que lo que suena es el inglés, por más
      // que el maestro marque el español como DEFAULT.
      expect(r.pistas[r.sonando].nombre, 'English');
    });

    test('NO repite un idioma que el maestro declara varias veces', () {
      // Un maestro trae un EXT-X-MEDIA por GRUPO de audio, y los grupos se
      // repiten por calidad. El menú mostraba «Español» dos veces y las dos
      // hacían lo mismo.
      const conGrupos = '''
#EXTM3U
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud-hi",NAME="Español",LANGUAGE="es",URI="index-a1.m3u8"
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud-lo",NAME="Español",LANGUAGE="es",URI="index-a1.m3u8"
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud-hi",NAME="English",LANGUAGE="en",URI="index-a2.m3u8"
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud-lo",NAME="English",LANGUAGE="en",URI="index-a2.m3u8"
#EXT-X-STREAM-INF:BANDWIDTH=1500000,AUDIO="aud-hi"
index-v1-a1.m3u8
''';
      final r = AudioHls.delMaestro(conGrupos);
      expect(r.pistas.length, 2,
          reason: 'cuatro declaraciones, dos idiomas: ${r.pistas.map((p) => p.nombre)}');
      expect(r.pistas.map((p) => p.numero), [1, 2]);
    });

    test('con un solo idioma no hay nada que elegir', () {
      const uno = '''
#EXTM3U
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="Latino",LANGUAGE="es",URI="index-a1.m3u8"
#EXT-X-STREAM-INF:BANDWIDTH=1500000,AUDIO="audio"
index-v1-a1.m3u8
''';
      expect(AudioHls.delMaestro(uno).pistas, isEmpty);
    });

    test('sin idiomas declarados devuelve vacío y no revienta', () {
      expect(AudioHls.delMaestro('#EXTM3U\nindex-v1.m3u8\n').pistas, isEmpty);
      expect(AudioHls.delMaestro('').pistas, isEmpty);
    });

    test('la lista se puede modificar — nunca una constante', () {
      // Asignar una lista constante a un RxList deja el contenido inmodificable
      // y el clear() del servidor siguiente revienta. Se llevó puesta a JKAnime.
      final vacia = AudioHls.delMaestro('').pistas;
      expect(() => vacia.add(const PistaDeAudio(1, 'x', 'es')), returnsNormally);
    });

    test('si no hay NAME usa el idioma', () {
      const sinNombre = '''
#EXTM3U
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="a",LANGUAGE="es",URI="index-a1.m3u8"
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="a",LANGUAGE="en",URI="index-a2.m3u8"
#EXT-X-STREAM-INF:BANDWIDTH=1,AUDIO="a"
index-v1-a1.m3u8
''';
      expect(AudioHls.delMaestro(sinNombre).pistas.map((p) => p.nombre),
          ['es', 'en']);
    });
  });

  group('con cuál se arranca', () {
    test('el español, aunque el servidor pegue el inglés al vídeo', () {
      final r = AudioHls.delMaestro(_dosIdiomas);
      expect(AudioHls.preferido(r.pistas, r.sonando).nombre, 'Español');
    });

    test('si NO hay español, el que venga pegado — nunca queda mudo', () {
      const sinEspanol = '''
#EXTM3U
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="a",NAME="English",LANGUAGE="en",URI="index-a1.m3u8"
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="a",NAME="日本語",LANGUAGE="ja",URI="index-a2.m3u8"
#EXT-X-STREAM-INF:BANDWIDTH=1,AUDIO="a"
index-v1-a2.m3u8
''';
      final r = AudioHls.delMaestro(sinEspanol);
      expect(AudioHls.preferido(r.pistas, r.sonando).nombre, '日本語',
          reason: 'el vídeo trae -a2, que es el japonés');
    });

    test('reconoce el español lo escriban como lo escriban', () {
      for (final p in [
        const PistaDeAudio(1, 'Español', 'es'),
        const PistaDeAudio(1, 'Latino', null),
        const PistaDeAudio(1, 'Castellano', null),
        const PistaDeAudio(1, 'Spanish', null),
        const PistaDeAudio(1, 'Audio 1', 'spa'),
        const PistaDeAudio(1, 'Audio 1', 'es-419'),
      ]) {
        expect(AudioHls.esEspanol(p), isTrue, reason: '${p.nombre}/${p.idioma}');
      }
      for (final p in [
        const PistaDeAudio(1, 'English', 'en'),
        const PistaDeAudio(1, 'Português', 'pt'),
        const PistaDeAudio(1, 'Audio 1', null),
      ]) {
        expect(AudioHls.esEspanol(p), isFalse, reason: '${p.nombre}/${p.idioma}');
      }
    });
  });

  group('cambiar el idioma de la dirección', () {
    test('cambia el número y respeta el resto, incluido el vale', () {
      expect(
        AudioHls.conAudio('https://x.com/hls/index-v1-a2.m3u8?t=abc&s=123', 1),
        'https://x.com/hls/index-v1-a1.m3u8?t=abc&s=123',
      );
    });

    test('DEVUELVE LA MISMA si la dirección no lleva -aN', () {
      // El fallo de Goodstream: acá no hay nada que cambiar, y quien llama
      // tiene que darse cuenta en vez de marcar «Español» igual.
      const sinNumero = 'https://x.com/hls/master.m3u8?t=abc';
      expect(AudioHls.conAudio(sinNumero, 1), sinNumero);
    });

    test('no toca un -aN que no sea de un .m3u8', () {
      const url = 'https://x.com/pelicula-a2.mp4';
      expect(AudioHls.conAudio(url, 1), url);
    });
  });
}
