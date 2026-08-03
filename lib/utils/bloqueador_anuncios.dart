import 'dart:convert';

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
///   Windows  → se corta la navegación a dominios bloqueados y se limpia la
///   y Linux    página desde adentro (marcos y scripts de anuncios, y las
///              ventanas emergentes)
///
/// El de Android es mejor —ataja el pedido antes de salir— pero el otro es real
/// y es lo que se puede hacer donde el motor no ofrece la otra vía.
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
  static int get cuantosDominios => _dominios.length;

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
    logger.info('[bloqueador] instalada "$nombre" con ${dominios.length} dominios');
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
    logger.info('[bloqueador] ${_dominios.length} dominios en ${listas().where((l) => l.activa).length} lista(s) activa(s)');
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
      if (linea.startsWith('#') || linea.startsWith('!') || linea.startsWith(';')) {
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
    if (!activo || _dominios.isEmpty) return const [];
    final alternativas = _dominios
        .map((d) => RegExp.escape(d))
        .join('|');
    return [
      ContentBlocker(
        trigger: ContentBlockerTrigger(
          urlFilter: '.*://([^/]*\\.)?($alternativas)([/:?].*)?\$',
        ),
        action: ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
      ),
    ];
  }

  /// Lo que se inyecta en Windows y Linux, donde no hay bloqueo nativo.
  ///
  /// Hace tres cosas, todas del lado de la página:
  ///   1. tapa `window.open`, que es como se abren las ventanas emergentes
  ///   2. saca los marcos y scripts que apunten a dominios bloqueados
  ///   3. vigila la página, porque los anuncios se insertan después de cargar
  ///
  /// No es tan bueno como atajar el pedido —algo llega a pedirse antes de que
  /// se lo saque— pero evita que se vea y que se pueda hacer clic, que es lo
  /// que importa para no terminar en una página que no se buscó.
  static String guionParaInyectar() {
    if (!activo || _dominios.isEmpty) return '';
    final lista = jsonEncode(_dominios.toList());
    return '''
(function () {
  if (window.__prismBloqueador) return;
  window.__prismBloqueador = true;
  var dominios = $lista;
  function bloqueado(u) {
    if (!u) return false;
    try {
      var h = new URL(u, location.href).hostname.toLowerCase().replace(/^www\\./, '');
      for (var i = 0; i < dominios.length; i++) {
        if (h === dominios[i] || h.endsWith('.' + dominios[i])) return true;
      }
    } catch (e) {}
    return false;
  }
  // Las ventanas emergentes son el estorbo mas comun de estos sitios.
  window.open = function () { return null; };
  function limpiar(raiz) {
    var nodos = (raiz || document).querySelectorAll('iframe[src],script[src],embed[src]');
    for (var i = 0; i < nodos.length; i++) {
      if (bloqueado(nodos[i].getAttribute('src'))) nodos[i].remove();
    }
  }
  limpiar(document);
  // Los anuncios se agregan despues de que la pagina cargo, asi que hay que
  // seguir mirando y no limpiar una sola vez.
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
        actualizada:
            DateTime.tryParse('${m['actualizada']}') ?? DateTime.fromMillisecondsSinceEpoch(0),
      );
}
