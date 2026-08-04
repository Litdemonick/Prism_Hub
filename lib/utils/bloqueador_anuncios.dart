import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:prismhub/utils/log.dart';
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
/// cargadores de anuncios de VÍDEO (ver _cargadoresDeAnuncios). Son los que
/// meten el anuncio antes de la película, adentro del propio reproductor, y las
/// listas corrientes no suelen traerlos porque también los usan reproductores
/// legítimos. Sin ellos, el bloqueador quitaba banners y ventanas emergentes
/// pero el anuncio que de verdad molesta pasaba entero.
class BloqueadorAnuncios {
  BloqueadorAnuncios._();

  static const _claveListas = 'bloqueador_listas';
  static const _claveActivo = 'bloqueador_activo';

  /// Dominios de todas las listas ACTIVAS, ya unidos y sin repetir.
  static Set<String> _dominios = <String>{};
  static bool _cargado = false;

  /// ¿El bloqueador está encendido? Es un interruptor general, aparte del
  /// de cada lista: sirve para apagarlo entero un momento —por ejemplo si un
  /// sitio no carga— sin perder la configuración.
  static bool get activo => PrismHubStorage.getSetting(_claveActivo) == true;

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
      activo ? <String>{..._dominios, ..._cargadoresDeAnuncios}.length : 0;

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

  /// Instala una lista desde una dirección. Devuelve cuántos dominios trajo.
  ///
  /// Se descarga y se analiza ANTES de guardarla: una lista que no se puede
  /// leer o que viene vacía no se instala, así no queda en los ajustes algo
  /// que aparenta proteger y no protege.
  static Future<int> instalar(String nombre, String url) async {
    final dominios = await _bajarYAnalizar(url);
    if (dominios.isEmpty) {
      throw Exception('La lista no trajo ningún dominio utilizable');
    }
    final actuales = listas().toList();
    actuales.removeWhere((l) => l.url == url);
    actuales.add(ListaDeBloqueo(
      nombre: nombre.trim().isEmpty ? _nombreDesdeUrl(url) : nombre.trim(),
      url: url,
      activa: true,
      dominios: dominios,
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
    actuales[i] = actuales[i].copiaCon(
      dominios: dominios,
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
  }

  /// Junta los dominios de las listas activas. Se llama al arrancar y cada vez
  /// que algo cambia.
  static Future<void> cargar() async {
    if (_cargado) return;
    final juntos = <String>{};
    for (final l in listas()) {
      if (l.activa) juntos.addAll(l.dominios);
    }
    _dominios = juntos;
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
    if (!activo || _dominios.isEmpty) return false;
    final host = Uri.tryParse(url)?.host.toLowerCase();
    if (host == null || host.isEmpty) return false;
    final limpio = host.replaceFirst(RegExp(r'^www\.'), '');
    if (_dominios.contains(limpio)) return true;
    for (final d in _dominios) {
      if (limpio.endsWith('.$d')) return true;
    }
    return false;
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
    // listas corrientes no suelen traerlos (ver _cargadoresDeAnuncios).
    final todos = <String>{..._dominios, ..._cargadoresDeAnuncios};
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

  /// Cargadores de anuncios de VÍDEO, bloqueados siempre que el bloqueador
  /// esté encendido.
  ///
  /// Van aparte de las listas del usuario a propósito. Las listas corrientes
  /// apuntan a redes de banners y muchas NO incluyen estos, porque son piezas
  /// que también usan reproductores legítimos. Pero son justo los que meten el
  /// anuncio ANTES de la película, adentro del propio reproductor, que es el
  /// que no se puede saltear ni tapar.
  ///
  /// Medido en vivo: un anuncio de apuestas de 25 segundos antes de reproducir,
  /// servido por el SDK de anuncios de Google (`imasdk.googleapis.com`), con
  /// las listas activadas y sin que ninguna lo frenara.
  static const _cargadoresDeAnuncios = <String>[
    'imasdk.googleapis.com',
    'googleads.g.doubleclick.net',
    'pagead2.googlesyndication.com',
    'securepubads.g.doubleclick.net',
    'static.doubleclick.net',
    'ad.doubleclick.net',
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
    final todos = <String>{..._dominios, ..._cargadoresDeAnuncios};
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

/// Una lista instalada.
class ListaDeBloqueo {
  const ListaDeBloqueo({
    required this.nombre,
    required this.url,
    required this.activa,
    required this.dominios,
    required this.actualizada,
  });

  final String nombre;
  final String url;
  final bool activa;
  final Set<String> dominios;
  final DateTime actualizada;

  ListaDeBloqueo copiaCon({
    bool? activa,
    Set<String>? dominios,
    DateTime? actualizada,
  }) =>
      ListaDeBloqueo(
        nombre: nombre,
        url: url,
        activa: activa ?? this.activa,
        dominios: dominios ?? this.dominios,
        actualizada: actualizada ?? this.actualizada,
      );

  Map<String, dynamic> aMapa() => {
        'nombre': nombre,
        'url': url,
        'activa': activa,
        'dominios': dominios.toList(),
        'actualizada': actualizada.toIso8601String(),
      };

  static ListaDeBloqueo desdeMapa(Map<String, dynamic> m) => ListaDeBloqueo(
        nombre: '${m['nombre'] ?? 'Lista'}',
        url: '${m['url'] ?? ''}',
        activa: m['activa'] == true,
        dominios: ((m['dominios'] as List<dynamic>?) ?? const [])
            .map((e) => '$e')
            .toSet(),
        actualizada: DateTime.tryParse('${m['actualizada']}') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}
