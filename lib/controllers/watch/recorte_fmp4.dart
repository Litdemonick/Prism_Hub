import 'dart:async';
import 'dart:io';

import 'package:prismhub/utils/log.dart';

/// Adelantar en listas HLS de tipo fMP4, sin pedirle a mpv que salte.
///
/// ── El problema ─────────────────────────────────────────────────────────────
///
/// En una lista de pedacitos fMP4, pedirle a mpv que vaya al minuto 20 lo deja
/// clavado: la posición se queda quieta y el vídeo no vuelve nunca. Es un bug
/// de ffmpeg, no de la app —`mpv-player/mpv#15184`, etiquetado
/// `down-upstream:ffmpeg` y **cerrado como "not planned"**—; los mantenedores
/// contestaron que pasa igual con ffplay, y Jellyfin desactivó fMP4 por defecto
/// en sus clientes por lo mismo.
///
/// Van doce intentos revertidos peleándolo de frente: declararla lista, el
/// relay, colchón corto y colchón grande, `reconnect_streamed`,
/// `reconnect_at_eof`, `multiple_requests`, cabeceras completas, el mismo
/// camino que las listas que sí adelantan, `seek_streams_individually=0`,
/// servir el episodio como UN archivo, y cambiar el servidor por defecto.
/// Ninguno funcionó porque todos intentaban que ffmpeg saltara bien.
///
/// ── Lo que hace esto ────────────────────────────────────────────────────────
///
/// No le pide que salte: le da una lista que **empieza** en el minuto 20. Para
/// ffmpeg eso es un vídeo normal que arranca en cero y no tiene nada que
/// calcular. El desfase se le suma a la barra, así que el usuario ve el minuto
/// que pidió.
///
/// El `#EXTINF:` de cada pedacito trae su duración exacta, así que sumar dice
/// con aritmética simple en cuál cae cualquier segundo — que es justo lo que
/// ffmpeg calcula mal.
///
/// ── Medido antes de escribir una línea de esto (2026-08-10) ─────────────────
///
/// Contra el mismo `libmpv-2.dll` que se compila en la app —no un mpv bajado
/// aparte, que habría dado un falso positivo si su versión ya tuviera el
/// arreglo—, sobre un episodio de 111:07 con 666 pedacitos, saltando al 20:00:
///
///     recorte (lista desde el 20:00)   posición 0,0 → 18,8 s en 20 s   ✔
///     salto   (lista entera + seek)    posición clavada en 1192,7 s    ✗
///
/// El control salió como tenía que salir: en ese mismo episodio el salto SÍ
/// falla, así que la comparación vale. Banco: `temp/recorte.mjs` en prism-plus
/// y `temp/prueba_recorte.dart` acá.
///
/// ── Por qué está atado a animeav1 ───────────────────────────────────────────
///
/// **AnimeAV1 es la única extensión del repo con HLS fMP4.** Las demás sirven
/// `.ts` o MP4 directo, donde adelantar ya funciona sin tocar nada. Meter esto
/// en el camino común de HLS —que comparten casi todas— sería cambiar lo que
/// hoy anda en 60+ servidores para arreglar uno. Así que se enciende con dos
/// llaves y las dos tienen que estar: la extensión Y que la lista traiga de
/// verdad un `#EXT-X-MAP`.
///
/// Si algo sale mal en cualquier paso, [preparar] devuelve null y el
/// reproductor sigue exactamente como antes.
class RecorteFmp4 {
  RecorteFmp4._({
    required this.listaUrl,
    required this.cabeceras,
    required this.mapa,
    required this.encabezado,
    required List<_Pedacito> pedacitos,
    required HttpServer servidor,
  })  : _pedacitos = pedacitos,
        _servidor = servidor;

  /// La única extensión que sirve fMP4 hoy. La segunda llave es [mapa].
  static const String paqueteHabilitado = 'io.prismhub.animeav1';

  /// La lista de pedacitos de la que salió todo (ya bajada de un escalón si lo
  /// que vino era una lista maestra).
  final String listaUrl;

  final Map<String, String> cabeceras;

  /// El `#EXT-X-MAP` con la URI en absoluto. En fMP4 es el pedacito de
  /// inicialización: sin él no se decodifica un solo cuadro, así que un recorte
  /// que lo pierda se vería negro y parecería que falla la idea.
  final String mapa;

  /// Lo de arriba de la lista que hay que conservar tal cual.
  final List<String> encabezado;

  final List<_Pedacito> _pedacitos;

  /// Cuántos pedacitos tiene el episodio. Solo para el registro.
  int get cantidadDePedacitos => _pedacitos.length;

  /// Quien le sirve la lista a mpv, en 127.0.0.1.
  ///
  /// ── Por qué un servidor y no un archivo ─────────────────────────────────
  ///
  /// La primera versión escribía la lista en la carpeta temporal y le pasaba la
  /// ruta a mpv. **No abre**: da «Failed to recognize file format», y el
  /// episodio termina cayendo al navegador.
  ///
  /// La causa, medida: `_comoAbrir` deja en `demuxer-lavf-o` opciones del
  /// PROTOCOLO HTTP (`reconnect`, `multiple_requests`, `seg_max_retry`). Con
  /// una entrada `file:` ffmpeg no las reconoce y aborta la apertura. Y esa
  /// propiedad **no se puede limpiar en caliente**: se probó con `''`, con las
  /// comas escapadas de tres formas distintas y con `change-list clr`, y en
  /// todas quedó el valor viejo (`temp/prueba_whitelist.dart`).
  ///
  /// Sirviendo la lista por HTTP local la entrada vuelve a ser `http://` y esas
  /// mismas opciones son válidas otra vez: no hay nada que limpiar. Medido con
  /// `demuxer-lavf-o` intacto, tal como lo deja la app: 19 s de reproducción en
  /// 20 s de reloj (`temp/prueba_servidor.dart`).
  final HttpServer _servidor;

  /// La lista que se le está sirviendo ahora mismo.
  String _listaActual = '';

  /// Cuánto hay que sumarle a lo que informa mpv para saber el minuto real.
  ///
  /// ── Por qué hay dos y no uno ────────────────────────────────────────────
  ///
  /// El desfase NO puede cambiar cuando se arma la lista, sino cuando mpv ya
  /// la abrió. Entre una cosa y otra pasan cientos de milisegundos en los que
  /// mpv sigue informando la posición del tramo ANTERIOR: sumarle el desfase
  /// nuevo a esa posición vieja da un número disparatado, y eso es lo que se
  /// veía como el contador saltando a cero o a cualquier lado al usar las
  /// teclas.
  ///
  /// Así que [listaDesde] deja el nuevo en [_desfasePendiente] y recién
  /// [confirmar] —que llama el controller justo después de `open()`— lo pone
  /// en juego.
  Duration get desfase => _desfase;
  Duration _desfase = Duration.zero;
  Duration _desfasePendiente = Duration.zero;

  /// Dónde va a empezar de verdad la última lista armada.
  ///
  /// Se sabe apenas se arma —es una cuenta local, sin red— y sirve para que la
  /// barra muestre YA el minuto definitivo. Sin esto mostraba el minuto pedido
  /// y lo corregía al abrir: se pedía el 13, aparecía 13, y al cargar saltaba a
  /// 15. Ese brinco es lo que se ve como que el reproductor «se corrige solo».
  Duration get desfaseQueViene => _desfasePendiente;

  /// Pone en juego el desfase de la última lista servida. Se llama cuando mpv
  /// ya abrió esa lista, no antes.
  void confirmar() => _desfase = _desfasePendiente;

  /// La duración del episodio ENTERO, que es la que va en la barra. mpv solo
  /// conoce la del recorte.
  Duration get duracionTotal => Duration(
      milliseconds:
          (_pedacitos.fold<double>(0, (a, p) => a + p.duracion) * 1000).round());

  int _generacion = 0;

  // ── Preparación ───────────────────────────────────────────────────────────

  /// Devuelve un recorte listo para usar, o null si acá no aplica.
  ///
  /// Null es la respuesta normal en la mayoría de los casos y **no** es un
  /// error: significa "esto se abre como siempre".
  static Future<RecorteFmp4?> preparar({
    required String url,
    required String paquete,
    Map<String, String>? cabeceras,
  }) async {
    // ── Apagado en Android, a propósito (2026-08-11) ───────────────────────
    //
    // En el teléfono el recorte funciona a medias y deja el reproductor PEOR
    // que sin él: el vídeo arranca en un minuto que nadie pidió —19, 28, 35,
    // distinto en cada episodio— y desde ahí no hay forma de volver al
    // principio.
    //
    // Medido: no es la lista (se verificó servida, con VOD, MEDIA-SEQUENCE 0 y
    // EXT-X-MAP), no es la app (un detector de saltos mostró que ningún código
    // propio lo pide), no es mpv recordando posiciones (`resume-playback=no`
    // puesto), y no lo arregla `EXT-X-START:TIME-OFFSET=0`. Es un salto
    // instantáneo —0,27 s después de informar 0— así que viene de dentro del
    // fMP4: la marca de tiempo base de los fragmentos, que la versión de
    // ffmpeg de Android aplica y la de Windows no.
    //
    // Sin recorte, Android queda como estaba: no se puede adelantar en fMP4,
    // que es una limitación conocida, pero el vídeo abre donde tiene que abrir.
    // Peor es lo otro.
    //
    // Para volver a probarlo, sacar estas dos líneas.
    if (Platform.isAndroid) return null;

    // Primera llave: la extensión.
    if (paquete != paqueteHabilitado) return null;
    // Sin esto, cualquier MP4 directo entraría a bajarse una lista que no
    // existe y se comería la espera de red en cada apertura.
    if (!url.contains('.m3u8') && !url.contains('/m3u8/')) return null;

    try {
      final cab = Map<String, String>.of(cabeceras ?? const {});
      var listaUrl = url;
      var texto = await _bajar(listaUrl, cab);
      if (texto == null) return null;

      // Lista maestra: hay que bajar un escalón hasta la de pedacitos. Se toma
      // la primera variante, que es con la que arranca mpv.
      if (texto.contains('#EXT-X-STREAM-INF')) {
        final linea = texto
            .split('\n')
            .map((l) => l.trim())
            .firstWhere((l) => l.isNotEmpty && !l.startsWith('#'),
                orElse: () => '');
        if (linea.isEmpty) return null;
        listaUrl = _absoluta(linea, listaUrl);
        texto = await _bajar(listaUrl, cab);
        if (texto == null) return null;
      }

      final encabezado = <String>[];
      final pedacitos = <_Pedacito>[];
      String? mapa;
      var duracion = 0.0;
      var extras = <String>[];
      var enCuerpo = false;

      for (final cruda in texto.split('\n')) {
        final l = cruda.trim();
        if (l.isEmpty) continue;

        if (l.startsWith('#EXT-X-MAP')) {
          mapa = l.replaceAllMapped(
            RegExp(r'URI="([^"]+)"'),
            (m) => 'URI="${_absoluta(m.group(1)!, listaUrl)}"',
          );
          continue;
        }
        if (l.startsWith('#EXTINF:')) {
          duracion = double.tryParse(
                  l.substring(8).split(',').first.trim()) ??
              0;
          extras.add(l);
          enCuerpo = true;
          continue;
        }
        if (l.startsWith('#')) {
          // Lo que va pegado a un pedacito viaja con él; el resto es encabezado.
          if (enCuerpo &&
              (l.startsWith('#EXT-X-BYTERANGE') ||
                  l.startsWith('#EXT-X-DISCONTINUITY'))) {
            extras.add(l);
          } else if (l == '#EXT-X-ENDLIST') {
            continue;
          } else if (!enCuerpo && l != '#EXTM3U') {
            encabezado.add(l);
          }
          continue;
        }
        pedacitos.add(_Pedacito(
          duracion: duracion,
          url: _absoluta(l, listaUrl),
          extras: extras,
        ));
        extras = <String>[];
        duracion = 0;
      }

      // Segunda llave: sin EXT-X-MAP no es fMP4, así que el salto ya funciona y
      // acá no hay nada que arreglar.
      if (mapa == null) {
        logger.info('recorte fMP4: la lista no trae EXT-X-MAP, se abre normal');
        return null;
      }
      if (pedacitos.length < 2) return null;

      // Solo en el bucle local y con el puerto que dé el sistema: nada de esto
      // sale de la máquina.
      final servidor =
          await HttpServer.bind(InternetAddress.loopbackIPv4, 0, shared: false);

      final r = RecorteFmp4._(
        listaUrl: listaUrl,
        cabeceras: cab,
        mapa: mapa,
        encabezado: encabezado,
        pedacitos: pedacitos,
        servidor: servidor,
      );
      r._atender();
      logger.info('recorte fMP4 listo: ${pedacitos.length} pedacitos, '
          '${r.duracionTotal.inMinutes} min');
      return r;
    } catch (e) {
      // Cualquier tropiezo acá se traga a propósito: el reproductor tiene que
      // seguir abriendo como siempre, no fallar por una mejora.
      logger.warning('recorte fMP4: no se pudo preparar, se abre normal', e);
      return null;
    }
  }

  // ── Uso ───────────────────────────────────────────────────────────────────

  /// Escribe una lista que arranca en [desde] y devuelve su ruta local.
  ///
  /// El corte cae siempre al PRINCIPIO de un pedacito, no en el segundo exacto:
  /// cada uno empieza con un fotograma clave y cortar por el medio dejaría al
  /// decodificador sin referencia. El desfase real queda en [desfase], que es
  /// lo que hay que sumarle a la barra.
  ///
  /// ── [sinQuedarAtrasDe]: por qué un salto adelante RETROCEDÍA ────────────
  ///
  /// Como el corte cae al principio del pedacito, un salto corto hacia adelante
  /// podía terminar ANTES de donde estaba el vídeo. Con pedacitos de 10 s:
  ///
  ///     estoy en 308 (pedacito que empieza en 300) y pido +5 → 313
  ///     313 cae en el pedacito que empieza en 310 → avanzo 2 s, no 5
  ///     estoy en 308 y pido +1 → 309, que cae en el MISMO pedacito
  ///     → el vídeo vuelve a 300: **retrocedí 8 segundos**
  ///
  /// Por eso los saltos por intervalo se sentían al revés y el ajuste de
  /// «saltar intervalo» parecía no respetarse.
  ///
  /// Pasando dónde está el vídeo ahora, el corte nunca elige un pedacito que
  /// empiece antes de ahí: si el destino cae en el pedacito actual, se toma el
  /// siguiente. Un salto adelante avanza siempre, aunque sea menos de lo pedido
  /// —eso es la granularidad del formato y no se puede evitar sin volver a
  /// pedirle a ffmpeg que salte, que es justo lo que no funciona—.
  Future<String?> listaDesde(Duration desde, {Duration? sinQuedarAtrasDe}) async {
    try {
      final objetivo = desde.inMilliseconds / 1000.0;
      var acumulado = 0.0;
      var corte = 0;
      for (var i = 0; i < _pedacitos.length; i++) {
        if (acumulado + _pedacitos[i].duracion > objetivo) {
          corte = i;
          break;
        }
        acumulado += _pedacitos[i].duracion;
      }

      // Un salto hacia adelante no puede terminar detrás de donde ya estaba el
      // vídeo. Ver el comentario de arriba: sin esto, pedir +5 s desde la mitad
      // de un pedacito devolvía el principio de ese mismo pedacito.
      final piso = sinQuedarAtrasDe;
      if (piso != null &&
          desde > piso &&
          acumulado <= piso.inMilliseconds / 1000.0 &&
          corte + 1 < _pedacitos.length) {
        acumulado += _pedacitos[corte].duracion;
        corte++;
      }

      final out = StringBuffer('#EXTM3U\n');
      for (final e in encabezado) {
        out.writeln(e);
      }
      if (!encabezado.any((e) => e.startsWith('#EXT-X-VERSION'))) {
        out.writeln('#EXT-X-VERSION:7');
      }
      if (!encabezado.any((e) => e.startsWith('#EXT-X-PLAYLIST-TYPE'))) {
        out.writeln('#EXT-X-PLAYLIST-TYPE:VOD');
      }
      // ── Que empiece en el PRINCIPIO de la lista, y no donde se le ocurra ──
      //
      // En Android el vídeo arrancaba 19 segundos adentro, siempre, en
      // cualquier episodio — aunque la lista empiece en el primer pedacito y
      // aunque nadie pidiera ningún salto. En Windows no pasa, con la misma
      // lista servida igual: lo que cambia es la versión de ffmpeg que trae
      // libmpv en cada plataforma, y cómo interpreta la marca de tiempo base
      // que el fMP4 lleva dentro.
      //
      // `EXT-X-START` es la forma estándar de decirlo en la propia lista, así
      // que no depende de la versión ni de opciones del reproductor:
      // TIME-OFFSET=0 es «desde el principio» y PRECISE=YES pide que no
      // redondee al pedacito.
      //
      // Descartado antes de esto, para no repetirlo: `resume-playback=no` (no
      // era mpv recordando posiciones) y el detector de saltos (probó que
      // ningún código de la app lo movía).
      out.writeln('#EXT-X-START:TIME-OFFSET=0,PRECISE=YES');
      // Antes del primer pedacito, siempre. Es lo único que no se puede perder.
      out.writeln(mapa);
      for (var i = corte; i < _pedacitos.length; i++) {
        for (final e in _pedacitos[i].extras) {
          out.writeln(e);
        }
        out.writeln(_pedacitos[i].url);
      }
      out.writeln('#EXT-X-ENDLIST');

      _listaActual = out.toString();
      // Pendiente, no en juego: lo pone [confirmar] cuando mpv ya abrió.
      _desfasePendiente = Duration(milliseconds: (acumulado * 1000).round());
      // Un nombre nuevo por salto: con el mismo, mpv puede quedarse con la
      // lista anterior y el salto no se nota.
      _generacion++;
      final url = 'http://127.0.0.1:${_servidor.port}/lista_$_generacion.m3u8';
      logger.info('recorte fMP4: se pidió ${desde.inSeconds}s'
          '${sinQuedarAtrasDe != null ? " (estaba en ${sinQuedarAtrasDe.inSeconds}s)" : ""}'
          ' → pedacito $corte, que empieza en ${_desfasePendiente.inSeconds}s');
      return url;
    } catch (e) {
      logger.warning('recorte fMP4: no se pudo armar la lista', e);
      return null;
    }
  }

  /// Contesta lo que mpv pida con la lista que esté puesta.
  ///
  /// El nombre no se mira: cada salto cambia la URL solo para que mpv no
  /// reutilice la anterior, pero lo que se sirve es siempre [_listaActual].
  void _atender() {
    _servidor.listen((req) async {
      try {
        req.response.headers.contentType =
            ContentType('application', 'vnd.apple.mpegurl');
        req.response.write(_listaActual);
      } catch (_) {
        // Un pedido que se cae no puede tumbar el servidor: si no, el salto
        // siguiente se queda sin quien le conteste.
      } finally {
        try {
          await req.response.close();
        } catch (_) {}
      }
    }, onError: (Object e) {
      logger.warning('recorte fMP4: el servidor local falló', e);
    });
  }

  /// Cierra el servidor local. Se llama al cerrar el reproductor y al cambiar
  /// de fuente: uno por episodio quedaría escuchando para siempre.
  Future<void> limpiar() async {
    try {
      await _servidor.close(force: true);
    } catch (_) {}
  }

  // ── Auxiliares ────────────────────────────────────────────────────────────

  static String _absoluta(String ref, String base) {
    if (ref.startsWith('http')) return ref;
    try {
      return Uri.parse(base).resolve(ref).toString();
    } catch (_) {
      return ref;
    }
  }

  static Future<String?> _bajar(String url, Map<String, String> cabeceras) async {
    final cliente = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await cliente.getUrl(Uri.parse(url));
      cabeceras.forEach((k, v) {
        try {
          req.headers.set(k, v);
        } catch (_) {}
      });
      final res = await req.close().timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) {
        logger.warning('recorte fMP4: la lista contestó ${res.statusCode}');
        return null;
      }
      final buf = StringBuffer();
      await for (final trozo in res.transform(const SystemEncoding().decoder)) {
        buf.write(trozo);
      }
      return buf.toString();
    } catch (e) {
      logger.warning('recorte fMP4: no se pudo bajar la lista', e);
      return null;
    } finally {
      cliente.close(force: true);
    }
  }
}

class _Pedacito {
  const _Pedacito({
    required this.duracion,
    required this.url,
    required this.extras,
  });

  final double duracion;
  final String url;
  final List<String> extras;
}
