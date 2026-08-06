import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:prismhub/utils/log.dart';
import 'package:prismhub/utils/prismhub_directory.dart';
import 'package:prismhub/utils/prismhub_storage.dart';
import 'package:prismhub/utils/request.dart' show dio;

/// Bloqueo de anuncios para el NAVEGADOR INTERNO.
///
/// Solo aplica al WebView. El reproductor nativo no carga páginas: recibe una
/// dirección de vídeo y la reproduce, así que ahí no hay anuncios que bloquear
/// ni nada que interceptar.
///
/// El usuario arma su propia protección con "listas": cada lista es un archivo
/// de dominios que se instala desde una dirección, y se puede activar,
/// desactivar o quitar sin tocar las demás. Eso permite cambiar de lista si una
/// se abandona o rompe un sitio, en vez de depender de una sola metida a mano
/// en el código.
///
/// ── Por qué hay DOS formas de bloquear ──────────────────────────────────────
///
/// Medido en el propio paquete del WebView: `contentBlockers` está soportado en
/// Android, iOS y macOS, pero NO en Windows. Como todo tiene que andar también
/// en Windows y Linux, hay dos caminos que salen de las MISMAS reglas:
///
///   Android  → bloqueo nativo: el pedido no se hace, ni siquiera sale a la red
///   Windows  → se corta la navegación a dominios bloqueados y, desde adentro
///   y Linux    de la página, se niegan los pedidos ANTES de que salgan (ver
///              guionParaInyectar)
///
/// El de Android sigue siendo mejor porque lo ataja el motor, pero en el otro
/// el pedido tampoco llega a hacerse.
///
/// ── Los anuncios de vídeo ───────────────────────────────────────────────────
///
/// Aparte de las listas del usuario se bloquean siempre unos pocos dominios: los
/// base de fábrica que va siempre (ver _listaBase). Son los que
/// meten el anuncio antes de la película, adentro del propio reproductor, y las
/// listas corrientes no suelen traerlos porque también los usan reproductores
/// legítimos. Sin ellos, el bloqueador quitaba banners y ventanas emergentes
/// pero el anuncio que de verdad molesta pasaba entero.
class BloqueadorAnuncios {
  BloqueadorAnuncios._();

  static const _claveListas = 'bloqueador_listas';
  static const _claveActivo = 'bloqueador_activo';

  // La clave 'bloqueador_sin_reproductor' se dejó de usar el 2026-08-06 (ver
  // más abajo). Lo que haya quedado guardado de antes se ignora, así que un
  // servidor marcado en su momento vuelve a abrir solo.

  /// Qué listas de fábrica ya se intentaron instalar, para no reintentarlas
  /// eternamente ni volver a ponerlas si el usuario las quitó a propósito.
  ///
  /// **La clave cambió de nombre a propósito.** La versión anterior lanzaba la
  /// descarga antes de que existiera el cliente de red, así que los tres
  /// intentos de cada lista se gastaban con "Field 'dio' has not been
  /// initialized" sin haber salido a la red ni una vez. Con el nombre viejo,
  /// esos usuarios se quedaban sin las listas para siempre; con uno nuevo, el
  /// contador arranca de cero y se bajan como corresponde.
  static const _claveFabricaHechas = 'bloqueador_fabrica_hechas_v2';

  // ─── Servidores que no muestran un reproductor ────────────────────────────
  //
  // **Acá había una lista de servidores marcados, y se sacó el 2026-08-06.**
  //
  // Funcionaba así: un servidor que abría sin traer reproductor quedaba anotado
  // por host, y a partir de ahí no se le dejaba abrir el navegador nunca más.
  // La idea era ahorrarle al usuario una pantalla inútil. Salió mucho más caro:
  //
  //  - Se anotaba para siempre y en todas las extensiones. Un título roto
  //    suelto, o un servidor caído un rato, lo dejaba muerto.
  //  - No había forma de deshacerlo. El comentario decía que se limpiaba desde
  //    la pantalla del bloqueador, y esa pantalla nunca existió.
  //  - Y se marcaba por motivos que no eran del servidor: en Android, con la
  //    regex gigante que este mismo archivo le pasaba al WebView, las páginas
  //    iban tan lentas que Mega no alcanzaba a mostrar su reproductor dentro
  //    del plazo. Quedó marcado y muerto, abriendo perfecto en la computadora.
  //
  // Ahora se comprueba SIEMPRE y no se recuerda nada: si no hay reproductor se
  // cierra con un aviso, y la próxima vez se vuelve a intentar. Un servidor que
  // se recupera vuelve a andar solo. Ver `_vigilarQueHayaReproductor` y
  // `openWebViewPlayer` en webview_player_page.dart.

  // ─── Catálogo ─────────────────────────────────────────────────────────────

  /// Las listas que la app ofrece instalar de un toque.
  ///
  /// **Todas medidas el 2026-08-06**, con el mismo analizador que usa la app:
  /// se bajaron, se contaron los dominios que sobreviven y se anotó el número.
  /// Las que no se pudieron bajar quedaron afuera en vez de figurar rotas —
  /// HaGeZi (Pro y TIF) devuelve 404 en las rutas conocidas y el servidor de
  /// DigitalSide no resuelve.
  ///
  /// Las cuatro marcadas `deFabrica` se instalan solas la primera vez: cubren
  /// anuncios, rastreo, malware y suplantación, que es el mínimo para que el
  /// navegador interno no sea un problema de seguridad. Se eligieron mirando
  /// también el peso —entre las cuatro son ~470.000 dominios— porque cada una
  /// se queda en memoria mientras la app corre.
  static const catalogo = <ListaConocida>[
    // ── Lo que viene puesto ──
    ListaConocida(
      nombre: 'StevenBlack',
      para: 'Anuncios, rastreo y sitios de malware, todo junto. La más '
          'usada para empezar.',
      url: 'https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts',
      grupo: 'Todo en uno',
      cuantos: 67118,
      deFabrica: true,
    ),
    ListaConocida(
      nombre: 'Prigent-Malware',
      para: 'Servidores que reparten virus y programas dañinos.',
      url: 'https://v.firebog.net/hosts/Prigent-Malware.txt',
      grupo: 'Virus y estafas',
      cuantos: 249936,
      deFabrica: true,
    ),
    ListaConocida(
      nombre: 'Phishing Army',
      para: 'Páginas que se hacen pasar por otras para robarte la cuenta o '
          'los datos de la tarjeta.',
      url: 'https://phishing.army/download/phishing_army_blocklist_extended.txt',
      grupo: 'Virus y estafas',
      cuantos: 152115,
      deFabrica: true,
    ),
    ListaConocida(
      nombre: 'URLhaus',
      para: 'Direcciones que están repartiendo malware ahora mismo. Se '
          'renueva a diario.',
      url: 'https://urlhaus.abuse.ch/downloads/hostfile/',
      grupo: 'Virus y estafas',
      cuantos: 381,
      deFabrica: true,
    ),

    // ── Virus y estafas ──
    ListaConocida(
      nombre: 'Spam404',
      para: 'Sitios de estafa y fraude denunciados.',
      url: 'https://raw.githubusercontent.com/Spam404/lists/master/main-blacklist.txt',
      grupo: 'Virus y estafas',
      cuantos: 8140,
    ),
    ListaConocida(
      nombre: 'NoCoin',
      para: 'Páginas que usan tu equipo para minar criptomonedas sin '
          'avisarte. Se nota en que todo va lento.',
      url: 'https://raw.githubusercontent.com/hoshsadiq/adblock-nocoin-list/master/hosts.txt',
      grupo: 'Virus y estafas',
      cuantos: 307,
    ),
    ListaConocida(
      nombre: 'Prigent-Crypto',
      para: 'La versión grande de lo anterior: minado y secuestro de equipos.',
      url: 'https://v.firebog.net/hosts/Prigent-Crypto.txt',
      grupo: 'Virus y estafas',
      cuantos: 11491,
    ),

    // ── Anuncios y rastreo ──
    ListaConocida(
      nombre: 'EasyList',
      para: 'La de toda la vida contra publicidad. Es la base de casi todos '
          'los bloqueadores.',
      url: 'https://easylist.to/easylist/easylist.txt',
      grupo: 'Anuncios y rastreo',
      cuantos: 61110,
    ),
    ListaConocida(
      nombre: 'EasyPrivacy',
      para: 'La hermana de la anterior, pero contra el rastreo: quién sos, '
          'qué mirás y desde dónde.',
      url: 'https://easylist.to/easylist/easyprivacy.txt',
      grupo: 'Anuncios y rastreo',
      cuantos: 50183,
    ),
    ListaConocida(
      nombre: 'AdGuard DNS',
      para: 'La lista de AdGuard. Grande y muy al día.',
      url: 'https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt',
      grupo: 'Anuncios y rastreo',
      cuantos: 162398,
    ),
    ListaConocida(
      nombre: "Peter Lowe's",
      para: 'Chiquita y muy afilada: solo servidores de anuncios y rastreo, '
          'sin romper nada.',
      url: 'https://pgl.yoyo.org/adservers/serverlist.php'
          '?hostformat=hosts&showintro=0&mimetype=plaintext',
      grupo: 'Anuncios y rastreo',
      cuantos: 3517,
    ),
    ListaConocida(
      nombre: 'Dan Pollock',
      para: 'Otra clásica de anuncios, mantenida a mano desde hace años.',
      url: 'https://someonewhocares.org/hosts/zero/hosts',
      grupo: 'Anuncios y rastreo',
      cuantos: 12376,
    ),

    // ── Todo en uno ──
    ListaConocida(
      nombre: 'OISD Big',
      para: 'La más completa que hay: anuncios, rastreo, estafas y malware. '
          'Son 434.000 dominios, así que pesa.',
      url: 'https://big.oisd.nl/',
      grupo: 'Todo en uno',
      cuantos: 434121,
    ),
  ];

  /// Dominios de todas las listas ACTIVAS, ya unidos y sin repetir.
  static Set<String> _dominios = <String>{};
  static bool _cargado = false;

  /// Si el bloqueador está encendido. **Viene encendido de fábrica.**
  ///
  /// Es un interruptor general, aparte del de cada lista: sirve para apagarlo
  /// entero un momento —por ejemplo si un sitio no carga— sin perder la
  /// configuración.
  ///
  /// Se compara contra `false` y no contra `true` a propósito: así, mientras el
  /// usuario no lo haya apagado a mano —o sea, cuando el ajuste ni existe—
  /// queda encendido. Antes era al revés y venía apagado, así que la protección
  /// no existía hasta que alguien fuera a buscarla a Ajustes. Nadie hace eso, y
  /// menos antes de que le salte la primera ventana de casino.
  static bool get activo => PrismHubStorage.getSetting(_claveActivo) != false;

  static Future<void> setActivo(bool v) async {
    await PrismHubStorage.setSetting(_claveActivo, v);
    logger.info('[bloqueador] ${v ? 'activado' : 'desactivado'}');
  }

  /// Cuántos dominios se están bloqueando ahora mismo.
  ///
  /// **Los tres contadores están guardados, no se calculan al pedirlos.**
  ///
  /// Se leen desde el `build` de la pantalla de ajustes, o sea muchas veces por
  /// segundo mientras se mueve algo. Antes cada lectura armaba un conjunto
  /// nuevo con TODOS los dominios —`{...dominiosEnUso}.length` copiaba 326.000
  /// entradas, y `cuantosDeListas` armaba otro más para restarle la base— así
  /// que abrir la pantalla o tocar un interruptor trababa la app un rato largo.
  /// Ahora se calculan una sola vez, cuando cambian las listas.
  static int _cuantosTotal = 0;
  static int _cuantosSoloDeListas = 0;

  static int get cuantosDominios => activo ? _cuantosTotal : 0;

  /// Cuántos trae la base de fábrica. Se muestra para que quede claro que el
  /// bloqueador protege sin instalar nada — antes parecía que sin listas no
  /// hacía nada, y de hecho ASÍ ERA (ver `bloquea`).
  static int get cuantosDeFabrica => _listaBase.length;

  /// Cuántos suman las listas que instaló el usuario, sin contar los que ya
  /// están en la base.
  static int get cuantosDeListas => _cuantosSoloDeListas;

  // ─── Listas ───────────────────────────────────────────────────────────────

  /// Las listas instaladas, en el orden en que se agregaron.
  /// Las fichas ya leídas. Se rehacen solo cuando algo cambia.
  ///
  /// `listas()` se llama desde el `build` de la pantalla y desde cada contador,
  /// y cada llamada volvía a pedirle el texto a Hive y a interpretarlo entero.
  /// Es barato una vez y caro sesenta veces por segundo.
  static List<ListaDeBloqueo>? _fichas;

  static List<ListaDeBloqueo> listas() {
    final guardadas = _fichas;
    if (guardadas != null) return guardadas;
    final crudo = PrismHubStorage.getSetting(_claveListas);
    if (crudo is! String || crudo.isEmpty) return _fichas = const [];
    try {
      final datos = jsonDecode(crudo) as List<dynamic>;
      return _fichas = datos
          .map((e) => ListaDeBloqueo.desdeMapa(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      // Un ajuste corrupto no puede dejar sin navegador al usuario: se degrada
      // a "ninguna lista" y se sigue.
      logger.warning('[bloqueador] no se pudieron leer las listas: $e');
      return _fichas = const [];
    }
  }

  static Future<void> _guardar(List<ListaDeBloqueo> listas) async {
    _fichas = null;
    await PrismHubStorage.setSetting(
      _claveListas,
      jsonEncode(listas.map((l) => l.aMapa()).toList()),
    );
    _cargado = false;
    await cargar();
  }

  // ─── Dónde se guardan los dominios ────────────────────────────────────────
  //
  // En archivos, uno por lista, y NO en los ajustes. Ver el comentario de
  // `ListaDeBloqueo`: los ajustes son una caja de Hive y meterle medio millón
  // de dominios que se reescriben a cada cambio la termina rompiendo.

  static Directory get _carpeta {
    final d = Directory(
        '${PrismHubDirectory.getDirectory}${Platform.pathSeparator}bloqueador');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  /// El archivo de una lista. El nombre sale de la dirección, no del nombre que
  /// puso el usuario: el nombre se puede repetir o traer caracteres que el
  /// sistema de archivos no acepta, y la dirección ya es la clave de la lista.
  static File _archivoDe(String url) {
    var clave = 0;
    for (final c in url.codeUnits) {
      clave = (clave * 31 + c) & 0x7fffffff;
    }
    return File('${_carpeta.path}${Platform.pathSeparator}$clave.txt');
  }

  static Future<void> _escribirDominios(String url, Set<String> d) async {
    try {
      await _archivoDe(url).writeAsString(d.join('\n'), flush: true);
    } catch (e) {
      logger.warning('[bloqueador] no se pudo guardar la lista: $e');
    }
  }

  static Set<String> _leerDominios(String url) {
    try {
      final f = _archivoDe(url);
      if (!f.existsSync()) return <String>{};
      return f
          .readAsStringSync()
          .split('\n')
          .where((l) => l.isNotEmpty)
          .toSet();
    } catch (e) {
      logger.warning('[bloqueador] no se pudo leer la lista: $e');
      return <String>{};
    }
  }

  /// Pasa las listas viejas —las que guardaban los dominios adentro de la
  /// ficha— a archivos, y las saca de los ajustes.
  ///
  /// Corre una sola vez: después de esto las fichas ya no traen `dominios` y no
  /// hay nada que mover. Sin esto, quien ya tenía listas instaladas las perdía
  /// al actualizar.
  static Future<void> _migrarAArchivos() async {
    final crudo = PrismHubStorage.getSetting(_claveListas);
    if (crudo is! String || crudo.isEmpty) return;
    if (!crudo.contains('"dominios"')) return;
    try {
      final datos = jsonDecode(crudo) as List<dynamic>;
      final salida = <ListaDeBloqueo>[];
      for (final e in datos) {
        final m = e as Map<String, dynamic>;
        final ficha = ListaDeBloqueo.desdeMapa(m);
        final viejos = ((m['dominios'] as List<dynamic>?) ?? const [])
            .map((x) => '$x')
            .toSet();
        if (viejos.isNotEmpty) await _escribirDominios(ficha.url, viejos);
        salida.add(ficha);
      }
      _fichas = null;
      await PrismHubStorage.setSetting(
        _claveListas,
        jsonEncode(salida.map((l) => l.aMapa()).toList()),
      );
      logger.info('[bloqueador] ${salida.length} lista(s) pasadas a archivo');
    } catch (e) {
      logger.warning('[bloqueador] no se pudieron migrar las listas: $e');
    }
  }

  // ─── Sanear lo que escribe el usuario ─────────────────────────────────────

  /// Deja pasar solo direcciones que se puedan bajar sin peligro.
  ///
  /// El campo de "instalar lista" acepta texto libre, y con texto libre se
  /// pueden pedir cosas que no son una lista: `file:///` para leer archivos del
  /// equipo, `data:` para meter contenido inventado, `javascript:` por si algo
  /// termina en un WebView. Se exige http o https y un host con forma de
  /// dominio, y se corta el largo para que una dirección enorme no quede
  /// guardada en los ajustes.
  ///
  /// El contenido en sí ya estaba a salvo: `analizar` solo acepta líneas que
  /// tengan forma de dominio y descarta todo lo demás, así que una lista que
  /// venga con código adentro no aporta ni una entrada.
  static String? direccionValida(String texto) {
    final t = texto.trim();
    if (t.isEmpty) return 'Falta la dirección';
    if (t.length > 2048) return 'La dirección es demasiado larga';
    final u = Uri.tryParse(t);
    if (u == null) return 'Esa dirección no se entiende';
    if (u.scheme != 'http' && u.scheme != 'https') {
      return 'Tiene que empezar con http:// o https://';
    }
    if (!RegExp(r'^[a-z0-9.-]+\.[a-z]{2,}$', caseSensitive: false)
        .hasMatch(u.host)) {
      return 'El sitio de esa dirección no es válido';
    }
    return null;
  }

  /// Limpia el nombre que escribió el usuario.
  ///
  /// Se quitan los caracteres de control y se corta el largo: el nombre se
  /// muestra en pantalla y se guarda en los ajustes, y no hay motivo para que
  /// tenga saltos de línea ni doscientos caracteres.
  static String nombreSaneado(String texto) {
    final limpio =
        texto.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ').trim();
    return limpio.length > 60 ? limpio.substring(0, 60) : limpio;
  }

  // ─── Las que vienen puestas ───────────────────────────────────────────────

  /// Instala las listas de fábrica la primera vez.
  ///
  /// Se intenta hasta tres arranques por lista: si el usuario no tenía red la
  /// primera vez, se vuelve a probar. Pasados los tres se deja de insistir, y
  /// si la quitó a propósito no vuelve a aparecer sola.
  ///
  /// Va en segundo plano a propósito: son varios megas y la app tiene que estar
  /// usable mientras tanto. Mientras no terminen, la base de fábrica del código
  /// ya está protegiendo.
  static Future<void> asegurarDeFabrica() async {
    // Cuántas veces se intentó cada una.
    //
    // **Antes esto estaba roto de dos maneras.** Se guardaba pegando todas las
    // direcciones en un solo texto y se leía partiéndolo CARÁCTER POR CARÁCTER:
    // el conjunto quedaba lleno de letras sueltas y la comprobación no acertaba
    // nunca. Y la idea de fondo tampoco servía: se anotaba "ya intentada"
    // aunque hubiera fallado, así que a quien abría la app sin red la lista le
    // quedaba fuera para siempre mientras la pantalla decía "viene puesta".
    final crudo = PrismHubStorage.getSetting(_claveFabricaHechas);
    final intentos = <String, int>{};
    if (crudo is String && crudo.isNotEmpty) {
      try {
        final d = jsonDecode(crudo);
        if (d is Map) {
          d.forEach((k, v) => intentos['$k'] = v is int ? v : 0);
        } else if (d is List) {
          for (final e in d) {
            intentos['$e'] = 1;
          }
        }
      } catch (_) {
        // Un ajuste ilegible no puede frenar el arranque: se toma como que no
        // se instaló ninguna y se vuelve a intentar.
      }
    }

    final yaInstaladas = listas().map((l) => l.url).toSet();
    var cambio = false;

    for (final c in catalogo) {
      if (!c.deFabrica) continue;
      if (yaInstaladas.contains(c.url)) continue;
      // Tres arranques de margen. Con menos, un rato sin red deja al usuario
      // sin las listas; con más, quien la quitó a propósito la ve volver
      // eternamente.
      final hechos = intentos[c.url] ?? 0;
      if (hechos >= 3) continue;
      intentos[c.url] = hechos + 1;
      cambio = true;
      try {
        final n = await instalar(c.nombre, c.url);
        logger.info('[bloqueador] de fábrica: ${c.nombre} ($n dominios)');
        intentos[c.url] = 99;
      } catch (e) {
        logger.warning('[bloqueador] no se pudo poner ${c.nombre} '
            '(intento ${hechos + 1} de 3): $e');
      }
      await PrismHubStorage.setSetting(
          _claveFabricaHechas, jsonEncode(intentos));
    }
    if (cambio) await cargar();
  }

  /// Las de fábrica que deberían estar puestas y no están.
  ///
  /// Se muestra en la pantalla: si una protección que la app promete no llegó a
  /// bajarse, el usuario tiene que poder verlo y ponerla, no darse cuenta solo.
  static List<ListaConocida> deFabricaQueFaltan() {
    final puestas = listas().map((l) => l.url).toSet();
    return catalogo
        .where((c) => c.deFabrica && !puestas.contains(c.url))
        .toList();
  }

  /// Vuelve a bajar TODAS las listas instaladas, una por una.
  ///
  /// Devuelve cuántas se pudieron poner al día. Las que fallen no cortan al
  /// resto: una lista caída no puede impedir que las otras se actualicen.
  static Future<int> actualizarTodas() async {
    var bien = 0;
    for (final l in listas()) {
      try {
        await actualizar(l.url);
        bien++;
      } catch (e) {
        logger.warning('[bloqueador] no se pudo actualizar ${l.nombre}: $e');
      }
    }
    return bien;
  }

  /// Instala una lista desde una dirección. Devuelve cuántos dominios trajo.
  ///
  /// Se descarga y se analiza ANTES de guardarla: una lista que no se puede
  /// leer o que viene vacía no se instala, así no queda en los ajustes algo
  /// que aparenta proteger y no protege.
  static Future<int> instalar(String nombre, String url) async {
    // Se valida ANTES de salir a la red: una direccion con `file://` o `data:`
    // no tiene que llegar siquiera a pedirse.
    final mal = direccionValida(url);
    if (mal != null) throw Exception(mal);
    final dominios = await _bajarYAnalizar(url);
    if (dominios.isEmpty) {
      throw Exception('La lista no trajo ningún dominio utilizable');
    }
    await _escribirDominios(url, dominios);
    final limpio = nombreSaneado(nombre);
    final actuales = listas().toList();
    actuales.removeWhere((l) => l.url == url);
    actuales.add(ListaDeBloqueo(
      nombre: limpio.isEmpty ? _nombreDesdeUrl(url) : limpio,
      url: url,
      activa: true,
      cuantos: dominios.length,
      actualizada: DateTime.now(),
    ));
    await _guardar(actuales);
    logger.info(
        '[bloqueador] instalada "$nombre" con ${dominios.length} dominios');
    return dominios.length;
  }

  /// Vuelve a bajar una lista ya instalada y reemplaza sus dominios.
  static Future<int> actualizar(String url) async {
    final actuales = listas().toList();
    final i = actuales.indexWhere((l) => l.url == url);
    if (i < 0) return 0;
    final dominios = await _bajarYAnalizar(url);
    if (dominios.isEmpty) {
      // Se conserva lo que ya había: una descarga fallida no puede dejar al
      // usuario con menos protección que antes de tocar "actualizar".
      throw Exception('La lista no trajo ningún dominio utilizable');
    }
    await _escribirDominios(url, dominios);
    actuales[i] = actuales[i].copiaCon(
      cuantos: dominios.length,
      actualizada: DateTime.now(),
    );
    await _guardar(actuales);
    return dominios.length;
  }

  static Future<void> activarLista(String url, bool activa) async {
    final actuales = listas().toList();
    final i = actuales.indexWhere((l) => l.url == url);
    if (i < 0) return;
    actuales[i] = actuales[i].copiaCon(activa: activa);
    await _guardar(actuales);
  }

  static Future<void> quitar(String url) async {
    final actuales = listas().toList()..removeWhere((l) => l.url == url);
    await _guardar(actuales);
    // El archivo se borra tambien: si no, quitar una lista grande dejaba diez
    // megas ocupados para siempre.
    try {
      final f = _archivoDe(url);
      if (f.existsSync()) await f.delete();
    } catch (e) {
      logger.warning('[bloqueador] no se pudo borrar el archivo: $e');
    }
  }

  /// Junta los dominios de las listas activas. Se llama al arrancar y cada vez
  /// que algo cambia.
  static Future<void> cargar() async {
    if (_cargado) return;
    await _migrarAArchivos();
    final juntos = <String>{};
    final malos = <String>{};
    for (final l in listas()) {
      if (!l.activa) continue;
      final suyos = await _leerDominios(l.url);
      juntos.addAll(suyos);
      // Aparte se junta lo que es PELIGROSO, no solo molesto: un dominio de
      // EasyList es un servidor de anuncios y no hay nada que avisar, pero uno
      // de Prigent-Malware o Phishing Army sí.
      if (_esDeSeguridad(l.url)) malos.addAll(suyos);
    }
    _peligrosos = malos;
    _dominios = juntos;
    _olvidarLoArmado();
    // Las cuentas se hacen ACÁ, una vez, y no cada vez que la pantalla las
    // pide. Ver el comentario de `cuantosDominios`.
    _cuantosTotal = dominiosEnUso.length;
    var propios = 0;
    for (final d in _dominios) {
      if (!_baseEnConjunto.contains(d)) propios++;
    }
    _cuantosSoloDeListas = propios;
    _cargado = true;
    logger.info(
        '[bloqueador] ${_dominios.length} dominios en ${listas().where((l) => l.activa).length} lista(s) activa(s)');
  }

  // ─── Descarga y análisis ──────────────────────────────────────────────────

  static Future<Set<String>> _bajarYAnalizar(String url) async {
    // Texto plano a propósito: estas listas son archivos de texto y sin esto
    // dio intenta interpretarlas según el tipo que declare el servidor.
    final res = await dio.get<String>(
      url,
      options: Options(responseType: ResponseType.plain),
    );
    return analizar(res.data ?? '');
  }

  /// Saca los dominios de una lista de texto.
  ///
  /// Se aceptan los tres formatos que se usan para esto, porque cada sitio
  /// publica el suyo y obligar a uno solo dejaría fuera la mitad:
  ///
  ///   `0.0.0.0 dominio.com`   (archivo de hosts)
  ///   `dominio.com`           (lista pelada)
  ///   `||dominio.com^`        (regla de bloqueo por dominio)
  ///
  /// Se ignoran los comentarios y cualquier regla que no sea un dominio
  /// entero: las reglas por selector o por ruta necesitan un motor completo, y
  /// prometer que se aplican cuando no es cierto sería peor que no leerlas.
  static Set<String> analizar(String texto) {
    final fuera = <String>{};
    for (final lineaCruda in const LineSplitter().convert(texto)) {
      var linea = lineaCruda.trim();
      if (linea.isEmpty) continue;
      if (linea.startsWith('#') ||
          linea.startsWith('!') ||
          linea.startsWith(';')) {
        continue;
      }
      // Comentario al final de la línea.
      final almohadilla = linea.indexOf('#');
      if (almohadilla > 0) linea = linea.substring(0, almohadilla).trim();

      String? dominio;
      if (linea.startsWith('||')) {
        final fin = linea.indexOf(RegExp(r'[\^/\$]'), 2);
        dominio = fin > 2 ? linea.substring(2, fin) : linea.substring(2);
      } else if (linea.contains(RegExp(r'^\d{1,3}(\.\d{1,3}){3}\s'))) {
        final partes = linea.split(RegExp(r'\s+'));
        if (partes.length >= 2) dominio = partes[1];
      } else if (!linea.contains(' ') && !linea.contains('/')) {
        dominio = linea;
      }

      if (dominio == null) continue;
      dominio = dominio.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
      // Un dominio de verdad: al menos un punto y solo caracteres válidos.
      if (!RegExp(r'^[a-z0-9.-]+\.[a-z]{2,}$').hasMatch(dominio)) continue;
      // 'localhost' y compañía aparecen en los archivos de hosts y no aportan.
      if (dominio == 'local' || dominio.endsWith('.local')) continue;
      fuera.add(dominio);
    }
    return fuera;
  }

  // ─── Aplicación en el WebView ─────────────────────────────────────────────

  /// ¿Hay que bloquear esta dirección?
  ///
  /// Compara por dominio y por subdominio: si la lista trae `anuncios.com`,
  /// también cae `cdn.anuncios.com`. Sin eso, cualquier lista se esquivaría
  /// publicando desde un subdominio nuevo.
  static bool bloquea(String url) {
    // **Ojo con lo que este atajo dejaba pasar.** Antes salía por
    // `_dominios.isEmpty`, y `_dominios` son SOLO las listas que instaló el
    // usuario. Como casi nadie instala una, `bloquea()` devolvía false siempre
    // — y con eso quedaba muerto el corte de navegación de
    // `shouldOverrideUrlLoading`, que es justo el que ataja las ventanas
    // emergentes. El bloqueador figuraba encendido y no cortaba una sola.
    //
    // Ahora la base de fábrica va siempre, haya o no listas instaladas.
    if (!activo) return false;
    final host = Uri.tryParse(url)?.host.toLowerCase();
    if (host == null || host.isEmpty) return false;
    // **Se pregunta por el host y por sus dominios padre, uno por uno.**
    //
    // Antes se recorria el conjunto entero comparando con `endsWith`, y por aca
    // pasa CADA pedido de CADA pagina. Con las listas de fabrica puestas eso son
    // cerca de 470.000 comparaciones de texto por pedido: la navegacion se
    // arrastraba. Un host tiene tres o cuatro niveles, asi que preguntarle al
    // conjunto por cada uno son tres o cuatro consultas instantaneas y da
    // exactamente el mismo resultado.
    var actual = host.replaceFirst(RegExp(r'^www\.'), '');
    final enUso = dominiosEnUso;
    while (true) {
      if (enUso.contains(actual)) return true;
      final punto = actual.indexOf('.');
      if (punto < 0) return false;
      actual = actual.substring(punto + 1);
      // Un dominio suelto sin punto ya es la terminacion (.com, .net): ahi no
      // hay nada mas que preguntar.
      if (!actual.contains('.')) return false;
    }
  }

  /// Todo lo que se bloquea: la base de fábrica más las listas del usuario.
  ///
  /// Se arma una sola vez y se guarda: por acá pasa CADA pedido de CADA página,
  /// así que rehacer el conjunto cada vez se paga caro.
  static Set<String>? _enUso;
  static Set<String> get dominiosEnUso =>
      _enUso ??= <String>{..._baseEnConjunto, ..._dominios};

  /// La base de fábrica como conjunto, armada una vez.
  ///
  /// `_listaBase` es una lista, y preguntarle `contains` es recorrerla entera.
  /// Se hacía por cada dominio de cada lista del usuario al contar, que son
  /// cientos de miles de recorridos de 47 elementos cada uno.
  static final Set<String> _baseEnConjunto = <String>{..._listaBase};

  /// Se olvida lo armado. Va cada vez que cambian las listas.
  static void _olvidarLoArmado() => _enUso = null;

  // ─── Avisar de un servidor peligroso ──────────────────────────────────────

  /// Los dominios de las listas de SEGURIDAD, aparte de los demás.
  ///
  /// Se guardan por separado porque sirven para otra cosa: no para cortar el
  /// pedido —eso ya lo hace `bloquea`— sino para avisarle al usuario, antes de
  /// abrir el navegador interno, que el servidor al que va está fichado.
  static Set<String> _peligrosos = <String>{};

  /// Si una lista instalada es de las que ficha virus y estafas.
  ///
  /// Se mira contra el catálogo: una lista puesta a mano no cuenta, porque no
  /// hay forma de saber qué contiene y marcar de peligroso lo que quizá sean
  /// anuncios sería avisar en falso todo el tiempo.
  static bool _esDeSeguridad(String url) {
    for (final c in catalogo) {
      if (c.url == url) return c.grupo == 'Virus y estafas';
    }
    return false;
  }

  /// ¿Este servidor está fichado como peligroso?
  ///
  /// Cuesta lo mismo que `bloquea`: tres o cuatro consultas a un conjunto. No
  /// sale a la red ni consulta a nadie, así que se puede preguntar justo antes
  /// de abrir sin que se note.
  static bool esPeligroso(String url) {
    if (_peligrosos.isEmpty) return false;
    final host = Uri.tryParse(url)?.host.toLowerCase();
    if (host == null || host.isEmpty) return false;
    var actual = host.replaceFirst(RegExp(r'^www\.'), '');
    while (true) {
      if (_peligrosos.contains(actual)) return true;
      final punto = actual.indexOf('.');
      if (punto < 0) return false;
      actual = actual.substring(punto + 1);
      if (!actual.contains('.')) return false;
    }
  }

  /// Qué listas lo marcaron, por nombre.
  ///
  /// Vuelve a abrir los archivos, que es caro, y por eso se llama SOLO cuando
  /// `esPeligroso` ya dijo que sí — o sea, casi nunca. Decir "está en una lista"
  /// sin decir en cuál no le sirve a nadie para decidir.
  static Future<List<String>> quienLoMarca(String url) async {
    final host = Uri.tryParse(url)?.host.toLowerCase();
    if (host == null || host.isEmpty) return const [];
    final base = host.replaceFirst(RegExp(r'^www\.'), '');
    final niveles = <String>[];
    var actual = base;
    while (true) {
      niveles.add(actual);
      final punto = actual.indexOf('.');
      if (punto < 0) break;
      final resto = actual.substring(punto + 1);
      if (!resto.contains('.')) break;
      actual = resto;
    }

    final fuera = <String>[];
    for (final l in listas()) {
      if (!l.activa || !_esDeSeguridad(l.url)) continue;
      final suyos = await _leerDominios(l.url);
      if (niveles.any(suyos.contains)) fuera.add(l.nombre);
    }
    return fuera;
  }

  /// Servidores que se abren SIN bloqueo nativo.
  ///
  /// **Lista corta y solo con lo medido.** Cada host que entre acá se queda sin
  /// el corte a nivel del motor, así que va únicamente el que se comprobó que
  /// no puede convivir con él.
  ///
  /// mega.nz, medido por el usuario el 2026-08-06 con el mismo episodio y la
  /// misma red:
  ///
  ///     Android · bloqueador apagado, con las listas puestas → Mega ANDA
  ///     Android · bloqueador encendido                       → Mega NO carga
  ///     Windows · todo encendido                             → Mega ANDA
  ///
  /// No es que las reglas coincidan con algo suyo: se comprobó dirección por
  /// dirección y ninguna cae —ni `mega.nz`, ni su API, ni `userstorage`, ni los
  /// `blob:`—. Es que **estar puestas** obliga al motor a pasar cada pedido por
  /// el interceptor del plugin, y ahí su reproductor se rompe. En Windows nunca
  /// se vio porque ahí el bloqueo nativo no existe.
  static const _sinBloqueoNativo = ['mega.nz', 'mega.co.nz'];

  /// Si a este servidor hay que abrirle el navegador sin bloqueo nativo.
  static bool sinBloqueoNativo(String url) {
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    if (host.isEmpty) return false;
    return _sinBloqueoNativo.any((h) => host == h || host.endsWith('.$h'));
  }

  /// Si en Windows hay que interceptar los pedidos del navegador interno.
  ///
  /// ── El agujero que tapa ─────────────────────────────────────────────────
  ///
  /// En Windows `contentBlockers` llega vacío: el valor nativo de la acción
  /// "bloquear" resuelve a null y construir una sola regla tumba la pantalla
  /// entera (ver reglasNativas). Así que el único bloqueo era el guion
  /// inyectado — y el guion **no puede** parar un `<script src="…ads…">` que ya
  /// venía escrito en el HTML: el navegador lo pide antes de que nada nuestro
  /// llegue a correr.
  ///
  /// Por ahí entra el anuncio de VÍDEO. Visto en vivo el 2026-08-06 en
  /// unlimplay: «el guion está en la página · no cortó nada» y aun así salió el
  /// anuncio de Google IMA con su «Anuncio 1 de 2». En Android eso ya lo tapa
  /// el bloqueo nativo; en Windows no lo tapaba nada.
  ///
  /// WebView2 sí deja cortarlos, por `WebResourceRequested`, que el plugin
  /// expone como `shouldInterceptRequest` (soportado oficialmente en Windows).
  ///
  /// ── Por qué acotado ─────────────────────────────────────────────────────
  ///
  /// Interceptar CADA pedido es exactamente lo que dejó a Mega sin cargar en
  /// Android: no era que las reglas coincidieran con algo suyo, era que estar
  /// puestas obliga al motor a pasar cada pedido por el interceptor y su
  /// reproductor se rompe. Por eso acá se respeta la MISMA excepción (ver
  /// [sinBloqueoNativo]) y solo se enciende con el bloqueador activo.
  ///
  /// La consulta en sí es barata: [bloquea] pregunta a un conjunto por el host
  /// y sus tres o cuatro dominios padre, no recorre ninguna lista.
  static bool interceptarEnWindows(String url) =>
      activo && interceptableEnWindows(url);

  /// La parte de la decisión que NO depende del interruptor.
  ///
  /// Separada para poder probarla: `activo` lee los ajustes, y en una prueba
  /// unitaria no hay almacenamiento que leer. Lo que importa fijar es la
  /// plataforma y la excepción, no que el interruptor apague.
  static bool interceptableEnWindows(String url) =>
      Platform.isWindows && !sinBloqueoNativo(url);

  /// Por qué NO vale la pena dejar abierta esta página, o null si sí vale.
  ///
  /// ── Por qué la regla vive acá y no en la pantalla del reproductor ────────
  ///
  /// Porque decidir qué no se abre es trabajo del bloqueador. El reproductor
  /// solo pregunta: el cable a los avisos del motor tiene que estar allá —es
  /// donde llegan los callbacks—, pero la decisión es una sola y está acá.
  ///
  /// ── Qué se cubre ─────────────────────────────────────────────────────────
  ///
  /// Visto en vivo el 2026-08-06 con Doodstream en Windows: **SmartScreen de
  /// Microsoft** corta `dsvplay.com` por sitio engañoso y deja su pantalla roja
  /// puesta. Eso NO lo puede ver el guion —es un muro del propio motor, ahí no
  /// corre nada nuestro— y tampoco lo ve el bloqueo nativo, porque el pedido ni
  /// llega a hacerse. Lo único que queda es el aviso de fallo de navegación.
  ///
  /// Antes no se miraba ninguno, así que la rueda giraba encima de esa pantalla
  /// hasta que saltaba la vigilancia de reproductor: 8 segundos en escritorio,
  /// 20 en Android.
  ///
  /// [esMarcoPrincipal] es la clave para no romper nada: un sub-recurso que
  /// falla es lo NORMAL con el bloqueador puesto —justamente, es un anuncio que
  /// no cargó— y no tiene por qué cerrar la pantalla de nadie.
  static String? motivoParaNoSeguir({
    required bool esMarcoPrincipal,
    int? httpStatus,
    String? errorDeCarga,
  }) {
    if (!esMarcoPrincipal) return null;
    if (httpStatus != null && httpStatus >= 400) {
      return 'la página respondió HTTP $httpStatus';
    }
    if (errorDeCarga != null && errorDeCarga.isNotEmpty) {
      return 'la página no cargó: $errorDeCarga';
    }
    return null;
  }

  /// El bloqueo nativo del WebView, para la dirección que se va a abrir.
  ///
  /// ── Para qué hace falta, si ya está el guion ────────────────────────────
  ///
  /// Porque hay un anuncio que el guion NO puede parar. El guion tapa
  /// `window.open`, `fetch`, `XHR` y el `src` que se pone por JavaScript, pero
  /// una etiqueta `<script src="…ads…">` que ya viene escrita en el HTML la pide
  /// el navegador antes de que nada nuestro pueda correr.
  ///
  /// Justo así entran los anuncios de vídeo. Visto en vivo el 2026-08-06 en
  /// unlimplay.com: el registro decía «el guion está en la página · no cortó
  /// nada» y aun así salió el anuncio de Google IMA, con su «Anuncio 1 de 2».
  /// `imasdk.googleapis.com` está en la lista base desde siempre — el nativo lo
  /// cortaba, el guion no llega.
  ///
  /// ── Solo la base de fábrica, NUNCA las listas del usuario ───────────────
  ///
  /// El plugin compila el filtro en un `Pattern` de Java y lo corre contra la
  /// dirección de CADA pedido, con un motor de retroceso y sin distinguir
  /// mayúsculas. Con los 326.685 dominios de las listas eso era **una sola
  /// expresión regular de 6,9 MB**: medido, 574 ms por pedido en la
  /// computadora, que es varias veces más rápida que un teléfono. Las páginas
  /// no terminaban de cargar nunca.
  ///
  /// La base son unas decenas de dominios y la regex queda en 886 caracteres.
  /// Y son justo los que conviene atajar en el motor: los que meten el anuncio
  /// adentro del reproductor. Las listas del usuario las sigue cortando el
  /// guion, que para eso mira un conjunto y no una expresión regular.
  ///
  /// ── Y hay servidores que no lo toleran ──────────────────────────────────
  ///
  /// Estar puesto obliga al motor a pasar cada pedido por el interceptor del
  /// plugin, y algún reproductor se rompe con eso aunque las reglas no lo
  /// mencionen. Le pasa a Mega: ver [_sinBloqueoNativo], donde está la medición
  /// y por qué se abre sin esto. Por eso hace falta la dirección acá — no se
  /// puede decidir sin saber a quién se va a abrir.
  ///
  /// Fuera de Android/iOS/macOS no se construye NADA: en Windows el valor
  /// nativo de la acción "bloquear" resuelve a null y crear una sola regla
  /// tumba la pantalla entera (ver content_blocker_action_type.g.dart en el
  /// paquete). Allá el bloqueo lo hacen el guion y el corte de navegación.
  static List<ContentBlocker> reglasNativas(String url) {
    if (!(Platform.isAndroid || Platform.isIOS || Platform.isMacOS)) {
      return const [];
    }
    if (!activo) return const [];
    if (sinBloqueoNativo(url)) return const [];
    final patron = patronPara(_baseEnConjunto);
    if (patron == null) return const [];
    return [
      ContentBlocker(
        trigger: ContentBlockerTrigger(urlFilter: patron),
        action: ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
      ),
    ];
  }

  /// La expresión regular que reconoce a estos dominios y a sus subdominios.
  ///
  /// Aparte de [reglasNativas] para poder probarla: ahí adentro no se puede,
  /// porque construir un `ContentBlocker` fuera de Android tumba la pantalla.
  /// Devuelve null si no hay nada que bloquear.
  static String? patronPara(Iterable<String> dominios) {
    final alternativas = dominios.map(RegExp.escape).join('|');
    if (alternativas.isEmpty) return null;
    return '.*://([^/]*\\.)?($alternativas)([/:?].*)?\$';
  }

  /// La base de fábrica: lo que se bloquea SIEMPRE, sin instalar ninguna lista.
  ///
  /// Antes acá solo estaban los cargadores de anuncios de vídeo, y todo lo
  /// demás dependía de que el usuario fuera a buscar una lista e instalarla.
  /// Casi nadie lo hace, así que el bloqueador venía encendido y sin nada que
  /// bloquear — y encima `bloquea()` salía por "no hay dominios" antes de
  /// mirar siquiera estos.
  ///
  /// Son tres grupos, y cada uno tapa un camino distinto:
  ///
  /// **1. Los que meten el anuncio ADENTRO del reproductor.** El vídeo de
  /// veinticinco segundos antes de la película. Las listas corrientes muchas
  /// veces NO los traen, porque son piezas que también usan reproductores
  /// legítimos. Medido en vivo: un anuncio de apuestas servido por el SDK de
  /// Google (`imasdk.googleapis.com`) pasaba entero con las listas activadas.
  ///
  /// **2. Las redes de ventanas emergentes.** Son las que hacen que tocar
  /// "reproducir" abra una pestaña de casino. Es lo que más molesta y lo que el
  /// usuario reporta.
  ///
  /// **3. Lo que se vio en los propios sitios que usa la app.** `a.adtng.com`
  /// está confirmado: aparece tanto en las páginas de unlimplay como en el
  /// servidor VIP de hentaila, en las dos como la dirección del VAST.
  ///
  /// **Esto no pretende reemplazar a una lista de verdad.** Una lista tipo
  /// EasyList trae decenas de miles de dominios y se actualiza sola; esto son
  /// las que aparecen en sitios de streaming, para que funcione sin que el
  /// usuario tenga que configurar nada. Instalar una lista sigue sumando: las
  /// dos se juntan en `dominiosEnUso`.
  static const _listaBase = <String>[
    // 1. Anuncios adentro del reproductor (VAST/VPAID).
    'imasdk.googleapis.com',
    'googleads.g.doubleclick.net',
    'pagead2.googlesyndication.com',
    'securepubads.g.doubleclick.net',
    'static.doubleclick.net',
    'ad.doubleclick.net',
    'doubleclick.net',
    'googlesyndication.com',
    'adservice.google.com',
    'video-ad-stats.googlesyndication.com',

    // 2. Redes de ventanas emergentes y de anuncios de streaming.
    'exoclick.com',
    'exosrv.com',
    'realsrv.com',
    'juicyads.com',
    'poweredby.jads.co',
    'propellerads.com',
    'propellerclick.com',
    'popads.net',
    'popcash.net',
    'popmyads.com',
    'hilltopads.net',
    'adsterra.com',
    'adskeeper.com',
    'mgid.com',
    'trafficjunky.com',
    'trafficjunky.net',
    'clickadu.com',
    'adcash.com',
    'adnxs.com',
    'zeusadvertisement.com',
    'onclickalgo.com',
    'onclicksuper.com',
    'onclickperformance.com',
    'monetizemore.com',
    'revcontent.com',
    'taboola.com',
    'outbrain.com',
    'bidgear.com',
    'admaven.com',
    'adprovider.net',

    // 3. Vistos en los propios sitios de la app.
    'a.adtng.com',
    'adtng.com',

    // Medición y rastreo. No molestan al usuario, pero son pedidos de más en
    // cada página y algunos son la puerta por la que entra lo de arriba.
    'google-analytics.com',
    'googletagmanager.com',
    'googletagservices.com',
    'scorecardresearch.com',
    'hotjar.com',
  ];

  /// Lo que se inyecta en la página. En Android es, además, lo que corta las
  /// listas grandes del usuario (ver [reglasNativas]).
  ///
  /// Ataja el pedido ANTES de que salga, en vez de borrar el elemento después.
  /// Antes hacía lo segundo y no servía para lo que importa: cuando un `script`
  /// ya está puesto en la página, el navegador YA lo bajó y lo ejecutó, así que
  /// sacarlo del documento no cancela nada. Con eso, un anuncio de vídeo antes
  /// de la película pasaba entero.
  ///
  /// Ahora se tapan los cuatro caminos por los que un anuncio entra:
  ///   1. `window.open` — las ventanas emergentes
  ///   2. la dirección de `script`, `iframe` y `embed`, al asignarse
  ///   3. `fetch` y `XMLHttpRequest` — por donde se piden los anuncios de vídeo
  ///   4. lo que aparezca después igual, que se saca al vuelo
  ///
  /// El pedido no llega a hacerse, así que corta igual que el bloqueo nativo.
  ///
  /// ── Los dominios van en un CONJUNTO, y no es un detalle ────────────────────
  ///
  /// Antes se recorría la lista entera comparando con `endsWith`, y por acá pasa
  /// CADA pedido de CADA página. Con las listas de fábrica puestas son 326.685
  /// comparaciones —con una concatenación de texto en cada vuelta— por pedido.
  ///
  /// Medido el 2026-08-06 con un corpus real de 164.407 dominios, o sea la
  /// MITAD de los que tenía el usuario:
  ///
  ///     recorriendo la lista    6,79 ms por pedido
  ///     preguntándole al conjunto  0,000 ms
  ///     armar el conjunto, una vez por página: 18 ms
  ///
  /// En la computadora eso se disimulaba; en el teléfono dejaba las páginas
  /// muertas — Mega no terminaba de cargar nunca. Es el MISMO arreglo que ya
  /// tenía [bloquea] del lado Dart y que a este guion no se le había hecho.
  ///
  /// Se comprobó que corta exactamente lo mismo: 23.516 host comparados uno por
  /// uno entre las dos versiones, incluidos los casos raros que una lista puede
  /// traer (un TLD suelto como `com` o `zip`, `co.uk`, punycode) y las
  /// casi-coincidencias tipo `dominiox`. Cero diferencias.
  static String guionParaInyectar() {
    if (!activo) return '';
    return guionPara(dominiosEnUso);
  }

  /// El guion para un conjunto de dominios dado.
  ///
  /// Aparte de [guionParaInyectar] para poder probarlo sin depender de los
  /// ajustes ni de las listas que tenga instaladas quien lo corra.
  static String guionPara(Iterable<String> dominios) {
    final todos = dominios.toList();
    if (todos.isEmpty) return '';
    final lista = jsonEncode(todos);
    return '''
(function () {
  if (window.__prismBloqueador) return;
  window.__prismBloqueador = true;
  // Un CONJUNTO, no una lista. Ver el porqué arriba, en guionParaInyectar.
  var dominios = new Set($lista);
  // Se avisa lo que se corta para poder verlo en el registro de la app, en vez
  // de tener que adivinar si el bloqueador esta haciendo algo. Una vez por
  // dominio: si no, un sitio que insiste llena el archivo.
  // Queda a la vista de quien pregunte desde afuera: la app lo consulta al
  // terminar de cargar para saber si el guion llego a correr y que corto. Con
  // los mensajes de consola no alcanza, porque no todos los motores los
  // reportan y entonces "no aparece nada" no distingue entre las dos cosas.
  var avisados = window.__prismCortados = {};
  console.log('[bloqueador] activo con ' + dominios.size + ' dominios');
  function bloqueado(u) {
    if (!u) return false;
    try {
      if (typeof u !== 'string') u = String(u);
      if (u.indexOf('data:') === 0 || u.indexOf('blob:') === 0) return false;
      var h = new URL(u, location.href).hostname.toLowerCase().replace(/^www\\./, '');
      // Se pregunta por el host y por sus dominios padre, uno por uno, igual que
      // hace bloquea() del lado Dart. Preguntarle a un conjunto por los tres o
      // cuatro niveles de un host da EXACTAMENTE lo mismo que recorrer la lista
      // entera con endsWith, y no depende de cuantos dominios haya.
      var actual = h;
      while (actual) {
        if (dominios.has(actual)) {
          if (!avisados[h]) { avisados[h] = 1; console.log('[bloqueador] cortado ' + h); }
          return true;
        }
        var punto = actual.indexOf('.');
        if (punto < 0) return false;
        actual = actual.substring(punto + 1);
      }
    } catch (e) {}
    return false;
  }

  // 1. Ventanas emergentes.
  window.open = function () { return null; };

  // 2. La direccion de los elementos que cargan cosas, tapada AL ASIGNARSE.
  //
  // Este es el punto: hay que negarla antes, no borrar el elemento despues.
  // Se deja el elemento en su lugar con la direccion vacia, asi la pagina no
  // se rompe si despues la consulta.
  function taparSrc(clase) {
    try {
      var d = Object.getOwnPropertyDescriptor(clase.prototype, 'src');
      if (!d || !d.set) return;
      Object.defineProperty(clase.prototype, 'src', {
        configurable: true,
        enumerable: d.enumerable,
        get: function () { return d.get ? d.get.call(this) : ''; },
        set: function (v) { if (!bloqueado(v)) d.set.call(this, v); }
      });
    } catch (e) {}
  }
  taparSrc(HTMLScriptElement);
  taparSrc(HTMLIFrameElement);
  if (window.HTMLEmbedElement) taparSrc(HTMLEmbedElement);

  // Algunas paginas usan setAttribute en vez de la propiedad.
  var ponerAtributo = Element.prototype.setAttribute;
  Element.prototype.setAttribute = function (nombre, valor) {
    var n = ('' + nombre).toLowerCase();
    if ((n === 'src' || n === 'data-src') && bloqueado(valor)) return;
    return ponerAtributo.apply(this, arguments);
  };

  // 3. Los pedidos sueltos: por aca es por donde se piden los anuncios de
  //    video (el reproductor pregunta que anuncio poner y lo recibe).
  //
  //    Se contesta vacio en vez de fallar: un error suelto hace que algunos
  //    reproductores se queden esperando para siempre en vez de arrancar la
  //    pelicula. Una respuesta vacia los deja seguir de largo.
  if (window.fetch) {
    var pedirOriginal = window.fetch;
    window.fetch = function (entrada, opciones) {
      var u = typeof entrada === 'string' ? entrada : (entrada && entrada.url);
      if (bloqueado(u)) {
        return Promise.resolve(new Response('', { status: 204, statusText: 'No Content' }));
      }
      return pedirOriginal.apply(this, arguments);
    };
  }
  if (window.XMLHttpRequest) {
    var abrir = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function (metodo, u) {
      this.__prismCortado = bloqueado(u);
      return abrir.apply(this, arguments);
    };
    var enviar = XMLHttpRequest.prototype.send;
    XMLHttpRequest.prototype.send = function () {
      // Nunca sale. Se avisa "termino sin nada" para que quien escuche no se
      // quede colgado esperando.
      if (this.__prismCortado) {
        var self = this;
        setTimeout(function () {
          try { self.dispatchEvent(new Event('error')); } catch (e) {}
        }, 0);
        return;
      }
      return enviar.apply(this, arguments);
    };
  }
  if (navigator.sendBeacon) {
    var baliza = navigator.sendBeacon.bind(navigator);
    navigator.sendBeacon = function (u) {
      // Se dice que si sin mandar nada: es solo telemetria y nadie la mira.
      return bloqueado(u) ? true : baliza.apply(this, arguments);
    };
  }

  // 4. Red de seguridad para lo que igual haya entrado (por ejemplo, marcado
  //    ya escrito en el HTML antes de que esto corriera).
  function limpiar(raiz) {
    var nodos = (raiz || document).querySelectorAll('iframe[src],script[src],embed[src]');
    for (var i = 0; i < nodos.length; i++) {
      if (bloqueado(nodos[i].getAttribute('src'))) nodos[i].remove();
    }
  }
  limpiar(document);
  new MutationObserver(function (cambios) {
    for (var i = 0; i < cambios.length; i++) {
      var agregados = cambios[i].addedNodes;
      for (var j = 0; j < agregados.length; j++) {
        var n = agregados[j];
        if (n.nodeType !== 1) continue;
        if (bloqueado(n.getAttribute && n.getAttribute('src'))) { n.remove(); continue; }
        limpiar(n);
      }
    }
  }).observe(document.documentElement, { childList: true, subtree: true });
})();
''';
  }

  static String _nombreDesdeUrl(String url) {
    final host = Uri.tryParse(url)?.host ?? '';
    return host.isEmpty ? 'Lista' : host;
  }
}

/// Una lista instalada. **Es la ficha, no el contenido.**
///
/// Los dominios NO viajan acá: viven en un archivo aparte y se leen cuando hace
/// falta. Antes iban adentro de la ficha y la ficha se guardaba en los ajustes,
/// que son una caja de Hive — un archivo que crece por agregado. Con listas de
/// verdad eso no aguanta: OISD trae 434.000 dominios y Prigent-Malware 250.000,
/// y cada vez que se prende o apaga una lista se reescribe TODO. La caja de
/// ajustes se iba a hinchar hasta hacerse inservible, y ya hay antecedente de
/// que un archivo de Hive dañado deja la app sin arrancar.
class ListaDeBloqueo {
  const ListaDeBloqueo({
    required this.nombre,
    required this.url,
    required this.activa,
    required this.cuantos,
    required this.actualizada,
  });

  final String nombre;
  final String url;
  final bool activa;

  /// Cuántos dominios tiene. Se guarda en la ficha para poder mostrarlo sin
  /// abrir el archivo.
  final int cuantos;
  final DateTime actualizada;

  ListaDeBloqueo copiaCon({
    bool? activa,
    int? cuantos,
    DateTime? actualizada,
  }) =>
      ListaDeBloqueo(
        nombre: nombre,
        url: url,
        activa: activa ?? this.activa,
        cuantos: cuantos ?? this.cuantos,
        actualizada: actualizada ?? this.actualizada,
      );

  Map<String, dynamic> aMapa() => {
        'nombre': nombre,
        'url': url,
        'activa': activa,
        'cuantos': cuantos,
        'actualizada': actualizada.toIso8601String(),
      };

  static ListaDeBloqueo desdeMapa(Map<String, dynamic> m) => ListaDeBloqueo(
        nombre: '${m['nombre'] ?? 'Lista'}',
        url: '${m['url'] ?? ''}',
        activa: m['activa'] == true,
        // `dominios` es de las fichas viejas, cuando el contenido venía adentro.
        // Se lee para no perder la cuenta mientras se migra al archivo.
        cuantos: m['cuantos'] is int
            ? m['cuantos'] as int
            : ((m['dominios'] as List<dynamic>?) ?? const []).length,
        actualizada: DateTime.tryParse('${m['actualizada']}') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}

/// Una lista del catálogo: de las que se ofrecen para instalar de un toque.
///
/// Están acá con la dirección exacta porque "pegá la dirección de la que
/// quieras usar" no le sirve a nadie que no sepa de antemano que estas cosas
/// existen. Todas se midieron el 2026-08-06 antes de entrar: bajan, se analizan
/// y traen la cantidad de dominios que dice cada una.
class ListaConocida {
  const ListaConocida({
    required this.nombre,
    required this.para,
    required this.url,
    required this.grupo,
    required this.cuantos,
    this.deFabrica = false,
  });

  final String nombre;

  /// Para qué sirve, en una línea que se entienda sin saber del tema.
  final String para;
  final String url;

  /// En qué apartado del catálogo aparece.
  final String grupo;

  /// Cuántos dominios trajo cuando se midió. Sirve para que el usuario sepa
  /// qué está por bajar antes de tocar.
  final int cuantos;

  /// Si se instala sola la primera vez que arranca la app.
  final bool deFabrica;
}
