import 'dart:convert';

/// Los idiomas de audio de una lista HLS: leerlos, elegir cuál va y cambiarlo.
///
/// Vive aparte del controlador **para poder probarlo**. Son funciones puras —
/// entra texto, sale una decisión— pero estaban metidas en un archivo de miles
/// de líneas lleno de estado, donde no había forma de escribirles una prueba. Y
/// ya dieron dos fallos que vio el usuario:
///
///  - el menú decía «Español» y se escuchaba inglés, porque se daba por hecho
///    que la dirección se había podido cambiar;
///  - el mismo idioma salía repetido dos y tres veces en el menú.
///
/// Los dos eran de mirar una cadena de texto. Acá se prueban.
///
/// ── Cómo funciona esto en estos servidores ──────────────────────────────────
///
/// El maestro declara los idiomas con `#EXT-X-MEDIA:TYPE=AUDIO`, y cada uno
/// apunta a un archivo que termina en `-aN.m3u8`. Las variantes de vídeo traen
/// ESE número pegado: `index-v1-a2.m3u8` es el vídeo 1 con el audio 2 ya
/// mezclado. Por eso cambiar de idioma no es elegir una pista dentro del mismo
/// flujo: es pedir la misma variante con otro número.
class AudioHls {
  AudioHls._();

  /// Lee los idiomas del maestro y cuál viene pegado al vídeo.
  ///
  /// `sonando` es el índice del que se escucha sin tocar nada: sale de mirar el
  /// `-aN` de la primera variante, **no** del `DEFAULT=YES` del maestro. Se
  /// midió que no coinciden — el maestro puede marcar el español como preferido
  /// y las variantes traer el inglés pegado, que es el que suena.
  ///
  /// Con menos de dos idiomas devuelve la lista vacía: no hay nada que elegir.
  static ({List<PistaDeAudio> pistas, int sonando}) delMaestro(String maestro) {
    final pistas = <PistaDeAudio>[];
    for (final linea in const LineSplitter().convert(maestro)) {
      if (!linea.startsWith('#EXT-X-MEDIA:')) continue;
      if (!linea.contains('TYPE=AUDIO')) continue;
      final uri = RegExp(r'URI="([^"]+)"').firstMatch(linea)?.group(1);
      if (uri == null) continue;
      final num = RegExp(r'-a(\d+)\.m3u8').firstMatch(uri)?.group(1);
      if (num == null) continue;
      final numero = int.parse(num);
      // **Una vez cada idioma, aunque el maestro lo declare varias veces.**
      //
      // Un maestro suele traer un `#EXT-X-MEDIA` por GRUPO de audio, y los
      // grupos se repiten por calidad. El mismo español aparecía dos o tres
      // veces en el menú, y elegir uno u otro hacía exactamente lo mismo: la
      // pista es la misma y lo único que cambiaba era el grupo. Se compara por
      // el número, que es lo que de verdad la identifica y lo único que se usa
      // para cambiarla.
      if (pistas.any((p) => p.numero == numero)) continue;
      final nombre = RegExp(r'NAME="([^"]*)"').firstMatch(linea)?.group(1);
      final idioma = RegExp(r'LANGUAGE="([^"]*)"').firstMatch(linea)?.group(1);
      pistas.add(PistaDeAudio(
        numero,
        (nombre != null && nombre.trim().isNotEmpty)
            ? nombre
            : (idioma ?? 'Pista $num'),
        idioma,
      ));
    }
    if (pistas.length < 2) {
      // Lista NUEVA y modificable, nunca `const []`.
      //
      // Lo que se le asigna a `audiosHls` es un RxList, y una lista constante
      // deja el contenido inmodificable: el `clear()` del servidor siguiente
      // reventaba con "Cannot change the length of an unmodifiable list" y se
      // llevaba puesta la reproducción entera. Le pasó a JKAnime, que hasta ese
      // momento andaba en casi todos sus servidores.
      return (pistas: <PistaDeAudio>[], sonando: -1);
    }
    // Cuál viene pegado al vídeo. Se mira la primera variante de verdad.
    var enElVideo = -1;
    for (final linea in const LineSplitter().convert(maestro)) {
      if (linea.startsWith('#') || linea.trim().isEmpty) continue;
      final m = RegExp(r'-a(\d+)\.m3u8').firstMatch(linea);
      if (m != null) {
        enElVideo = int.parse(m.group(1)!);
        break;
      }
    }
    final i = pistas.indexWhere((p) => p.numero == enElVideo);
    return (pistas: pistas, sonando: i >= 0 ? i : 0);
  }

  /// Con qué idioma conviene arrancar.
  ///
  /// **El español, si está.** Estos sitios son de contenido en español y quien
  /// los usa quiere el latino; que empiece en inglés porque el servidor pegó
  /// ese al vídeo sería empezar mal.
  ///
  /// **Si no hay español, el que venga pegado** — no se inventa nada ni se
  /// deja mudo: suena lo que el servidor traiga, y el menú dice cuál es.
  static PistaDeAudio preferido(List<PistaDeAudio> pistas, int pegado) {
    for (final p in pistas) {
      if (esEspanol(p)) return p;
    }
    return pistas[pegado.clamp(0, pistas.length - 1)];
  }

  /// Si esta pista es española, mirándolo por los dos lados.
  ///
  /// Los sitios escriben el idioma como se les ocurre: unos ponen `LANGUAGE`
  /// (`es`, `spa`, `es-419`) y otros solo el nombre visible («Latino»,
  /// «Castellano», «Español»). Mirando uno solo se escapaban la mitad.
  static bool esEspanol(PistaDeAudio p) {
    final codigo = (p.idioma ?? '').toLowerCase();
    if (codigo.startsWith('es') || codigo.startsWith('spa')) return true;
    return RegExp(r'espa|latin|castell|spanish', caseSensitive: false)
        .hasMatch(p.nombre);
  }

  /// La misma dirección, con otro número de audio.
  ///
  /// `…/index-v1-a2.m3u8?t=…` → `…/index-v1-a1.m3u8?t=…`. El vale sirve igual
  /// para las dos: comprobado pidiendo la variante en español con el token de
  /// la inglesa, responde 200 y baja vídeo.
  ///
  /// **Devuelve la MISMA dirección si no hay nada que cambiar**, y quien llama
  /// tiene que mirarlo. De no hacerlo salía el fallo de Goodstream: el menú
  /// marcaba «Español» y se escuchaba inglés, porque la dirección de ese
  /// servidor no lleva `-aN` y el reemplazo no hacía nada.
  static String conAudio(String url, int numero) =>
      url.replaceAll(RegExp(r'-a\d+(?=\.m3u8)'), '-a$numero');
}

class PistaDeAudio {
  const PistaDeAudio(this.numero, this.nombre, this.idioma);

  /// El número con el que el servidor la nombra en los archivos: la variante
  /// `index-v1-a2.m3u8` es el vídeo 1 con ESTE audio pegado. Cambiar de idioma
  /// es pedir la misma variante con otro número.
  final int numero;
  final String nombre;
  final String? idioma;
}
