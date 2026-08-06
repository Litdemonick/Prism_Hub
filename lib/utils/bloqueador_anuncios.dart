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

  /// Qué listas de fábrica ya se intentaron instalar, para no reintentarlas
  /// eternamente ni volver a ponerlas si el usuario las quitó a propósito.
  static const _claveFabricaHechas = 'bloqueador_fabrica_hechas';

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
  /// Incluye los cargadores de anuncios de vídeo, que van siempre. Antes
  /// contaba solo las listas del usuario, así que sin ninguna instalada la
  /// pantalla decía "0 dominios bloqueados" mientras el bloqueador sí estaba
  /// cortando cosas — parecía que no hacía nada.
  static int get cuantosDominios =>
      activo ? <String>{...dominiosEnUso}.length : 0;

  /// Cuántos trae la base de fábrica. Se muestra para que quede claro que el
  /// bloqueador protege sin instalar nada — antes parecía que sin listas no
  /// hacía nada, y de hecho ASÍ ERA (ver `bloquea`).
  static int get cuantosDeFabrica => _listaBase.length;

  /// Cuántos suman las listas que instaló el usuario, sin contar los que ya
  /// están en la base.
  static int get cuantosDeListas =>
      _dominios.difference(<String>{..._listaBase}).length;

  // ─── Listas ───────────────────────────────────────────────────────────────

  /// Las listas instaladas, en el orden en que se agregaron.
  static List<ListaDeBloqueo> listas() {
    final crudo = PrismHubStorage.getSetting(_claveListas);
    if (crudo is! String || crudo.isEmpty) return const [];
    try {
      final datos = jsonDecode(crudo) as List<dynamic>;
      return datos
          .map((e) => ListaDeBloqueo.desdeMapa(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      // Un ajuste corrupto no puede dejar sin navegador al usuario: se degrada
      // a "ninguna lista" y se sigue.
      logger.warning('[bloqueador] no se pudieron leer las listas: $e');
      return const [];
    }
  }

  static Future<void> _guardar(List<ListaDeBloqueo> listas) async {
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

  /// El salto de linea con el que se separan los dominios en el archivo.
  static final String _salto = String.fromCharCode(10);

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
  /// Se intenta una sola vez por lista, y se anota el intento aunque falle: si
  /// el usuario la quita después, no vuelve a aparecer sola. Y si no hay red,
  /// se anota igual el resto y se sigue — esto no puede demorar el arranque.
  ///
  /// Va en segundo plano a propósito: son varios megas y la app tiene que estar
  /// usable mientras tanto. Mientras no terminen, la base de fábrica del código
  /// ya está protegiendo.
  static Future<void> asegurarDeFabrica() async {
    final hechasCrudo = PrismHubStorage.getSetting(_claveFabricaHechas);
    final hechas = <String>{
      if (hechasCrudo is String && hechasCrudo.isNotEmpty)
        ...hechasCrudo.split(''),
    };
    final yaInstaladas = listas().map((l) => l.url).toSet();

    for (final c in catalogo) {
      if (!c.deFabrica) continue;
      if (hechas.contains(c.url) || yaInstaladas.contains(c.url)) continue;
      try {
        final n = await instalar(c.nombre, c.url);
        logger.info('[bloqueador] de fábrica: ${c.nombre} ($n dominios)');
      } catch (e) {
        logger.warning('[bloqueador] no se pudo poner ${c.nombre}: $e');
      }
      // Se anota igual haya salido bien o mal: reintentar en cada arranque
      // sería castigar a quien no tiene red con una demora en cada apertura.
      hechas.add(c.url);
      await PrismHubStorage.setSetting(
          _claveFabricaHechas, hechas.join(''));
    }
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
      final suyos = _leerDominios(l.url);
      juntos.addAll(suyos);
      // Aparte se junta lo que es PELIGROSO, no solo molesto: un dominio de
      // EasyList es un servidor de anuncios y no hay nada que avisar, pero uno
      // de Prigent-Malware o Phishing Army sí.
      if (_esDeSeguridad(l.url)) malos.addAll(suyos);
    }
    _peligrosos = malos;
    _dominios = juntos;
    _olvidarLoArmado();
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
      _enUso ??= <String>{..._listaBase, ..._dominios};

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
  static List<String> quienLoMarca(String url) {
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
      final suyos = _leerDominios(l.url);
      if (niveles.any(suyos.contains)) fuera.add(l.nombre);
    }
    return fuera;
  }

  /// Reglas para el bloqueo nativo (Android, iOS y macOS).
  ///
  /// Va TODO en una sola regla con los dominios alternados en vez de una regla
  /// por dominio: con listas de miles de entradas, una regla cada una hace que
  /// el WebView tarde una eternidad en arrancar.
  static List<ContentBlocker> reglasNativas() {
    // Fuera de Android/iOS/macOS ni siquiera se CONSTRUYEN.
    //
    // No es por prolijidad: en Windows, el valor nativo de la acción "bloquear"
    // resuelve a null y el paquete lo guarda en un campo que no admite null, así
    // que crear una sola regla tumba la pantalla entera con "type 'Null' is not
    // a subtype of type 'String'". Comprobado en el código del paquete
    // (content_blocker_action_type.g.dart: solo android, iOS y macOS devuelven
    // valor; el resto cae en null).
    //
    // Antes esto no se notaba de pura casualidad: sin ninguna lista instalada la
    // función salía por el atajo de "no hay dominios" y nunca llegaba a
    // construir nada.
    if (!(Platform.isAndroid || Platform.isIOS || Platform.isMacOS)) {
      return const [];
    }
    if (!activo) return const [];
    // Los cargadores de anuncios de vídeo van SIEMPRE, junto con las listas del
    // usuario: son los que meten el anuncio adentro del reproductor y las
    // listas corrientes no suelen traerlos (ver _listaBase).
    final todos = dominiosEnUso;
    if (todos.isEmpty) return const [];
    final alternativas = todos.map((d) => RegExp.escape(d)).join('|');
    return [
      ContentBlocker(
        trigger: ContentBlockerTrigger(
          urlFilter: '.*://([^/]*\\.)?($alternativas)([/:?].*)?\$',
        ),
        action: ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
      ),
    ];
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

  /// Lo que se inyecta en Windows y Linux, donde no hay bloqueo nativo.
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
  /// Sigue sin ser tan bueno como el bloqueo nativo de Android, que ni deja
  /// salir el pedido a la red; pero acá el pedido tampoco llega a hacerse.
  static String guionParaInyectar() {
    if (!activo) return '';
    final todos = dominiosEnUso;
    if (todos.isEmpty) return '';
    final lista = jsonEncode(todos.toList());
    return '''
(function () {
  if (window.__prismBloqueador) return;
  window.__prismBloqueador = true;
  var dominios = $lista;
  // Se avisa lo que se corta para poder verlo en el registro de la app, en vez
  // de tener que adivinar si el bloqueador esta haciendo algo. Una vez por
  // dominio: si no, un sitio que insiste llena el archivo.
  // Queda a la vista de quien pregunte desde afuera: la app lo consulta al
  // terminar de cargar para saber si el guion llego a correr y que corto. Con
  // los mensajes de consola no alcanza, porque no todos los motores los
  // reportan y entonces "no aparece nada" no distingue entre las dos cosas.
  var avisados = window.__prismCortados = {};
  console.log('[bloqueador] activo con ' + dominios.length + ' dominios');
  function bloqueado(u) {
    if (!u) return false;
    try {
      if (typeof u !== 'string') u = String(u);
      if (u.indexOf('data:') === 0 || u.indexOf('blob:') === 0) return false;
      var h = new URL(u, location.href).hostname.toLowerCase().replace(/^www\\./, '');
      for (var i = 0; i < dominios.length; i++) {
        if (h === dominios[i] || h.endsWith('.' + dominios[i])) {
          if (!avisados[h]) { avisados[h] = 1; console.log('[bloqueador] cortado ' + h); }
          return true;
        }
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
