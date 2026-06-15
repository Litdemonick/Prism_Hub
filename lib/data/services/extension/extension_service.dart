import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_js/flutter_js.dart';
import 'package:logging/logging.dart';

import '../../../data/models/extension_model.dart';

/// Un resultado tipado de la API de extensión.
typedef ExtResult = Map<String, dynamic>;

// ---------------------------------------------------------------------------
// Polyfill inyectado en QuickJS antes de evaluar cada bundle de extensión.
//
// QuickJS no incluye fetch, console ni btoa/atob. Aquí los proveemos:
//   • console.log/warn/error  →  puente a Logger de Dart (prismLog)
//   • fetch(url, init)        →  puente HTTP a dio de Dart (prismFetch)
//   • btoa / atob             →  implementación pura en JS (son síncronas)
// ---------------------------------------------------------------------------
const _kPolyfill = r'''
// ── console ─────────────────────────────────────────────────────────────────
(function() {
  function _send(level, args) {
    try { sendMessage('prismLog', level + Array.prototype.join.call(args, ' ')); }
    catch(_) {}
  }
  globalThis.console = {
    log:   function() { _send('[LOG] ',   arguments); },
    warn:  function() { _send('[WARN] ',  arguments); },
    error: function() { _send('[ERROR] ', arguments); },
    debug: function() { _send('[DEBUG] ', arguments); },
    info:  function() { _send('[INFO] ',  arguments); },
  };
})();

// ── btoa / atob (pure JS, síncronas) ────────────────────────────────────────
(function() {
  var B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  globalThis.btoa = function(s) {
    s = String(s);
    var o = '', i = 0, b;
    for (; i < s.length;) {
      var c1 = s.charCodeAt(i++), c2 = s.charCodeAt(i++), c3 = s.charCodeAt(i++);
      b = (c1 << 16) | (isNaN(c2) ? 0 : c2 << 8) | (isNaN(c3) ? 0 : c3);
      o += B64[(b >> 18) & 63] + B64[(b >> 12) & 63] +
           (isNaN(c2) ? '=' : B64[(b >> 6) & 63]) +
           (isNaN(c3) ? '=' : B64[b & 63]);
    }
    return o;
  };
  globalThis.atob = function(s) {
    s = String(s).replace(/[^A-Za-z0-9+/]/g, '');
    var o = '', i = 0, b;
    while (i < s.length) {
      b = (B64.indexOf(s[i++]) << 18) | (B64.indexOf(s[i++]) << 12) |
          (B64.indexOf(s[i++]) << 6)  |  B64.indexOf(s[i++]);
      if ((b >> 16) & 255) o += String.fromCharCode((b >> 16) & 255);
      if ((b >>  8) & 255) o += String.fromCharCode((b >>  8) & 255);
      if  (b        & 255) o += String.fromCharCode( b        & 255);
    }
    return o;
  };
})();

// ── fetch polyfill ───────────────────────────────────────────────────────────
globalThis.fetch = function(input, init) {
  var url = (typeof input === 'string') ? input : input.url;
  var opt = init || {};
  var req = JSON.stringify({
    url:     url,
    method:  opt.method  || 'GET',
    headers: opt.headers || {},
    body:    opt.body    || null,
  });
  return sendMessage('prismFetch', req).then(function(raw) {
    var d = (typeof raw === 'string') ? JSON.parse(raw) : raw;
    var body = d.body || '';
    var hdrs = d.headers || {};
    return {
      ok:         d.status >= 200 && d.status < 300,
      status:     d.status,
      statusText: d.statusText || '',
      url:        url,
      headers: {
        get: function(n) { return hdrs[n.toLowerCase()] || null; },
        has: function(n) { return n.toLowerCase() in hdrs; },
      },
      text: function()  { return Promise.resolve(body); },
      json: function()  { return Promise.resolve(JSON.parse(body)); },
    };
  });
};
''';

/// Motor de extensiones TypeScript/JS.
///
/// Cada extensión instanciada tiene su propio [JavascriptRuntime] aislado.
/// Antes de evaluar el bundle, se inyecta [_kPolyfill] que provee:
///   - console  → Logger de Dart
///   - fetch    → HTTP a través de dio
///   - btoa/atob → implementación pura JS
class ExtensionRuntime {
  ExtensionRuntime._(this.extension, this._rt, this._dio);

  final ExtensionModel extension;
  final JavascriptRuntime _rt;
  final Dio _dio;

  static final _log = Logger('ExtensionRuntime');

  static ExtensionRuntime load(ExtensionModel ext, String script) {
    final rt = getJavascriptRuntime();
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 60),
        // No lanzar excepción en 4xx/5xx — que la extensión decida qué hacer.
        validateStatus: (_) => true,
      ),
    );

    // ── Bridge: console.log → Logger ────────────────────────────────────────
    rt.onMessage('prismLog', (dynamic args) {
      _log.info('[${ext.package}] $args');
      return Future<void>.value();
    });

    // ── Bridge: fetch → dio ─────────────────────────────────────────────────
    rt.onMessage('prismFetch', (dynamic args) async {
      try {
        final raw = args is String ? args : jsonEncode(args);
        final req = jsonDecode(raw) as Map<String, dynamic>;

        final url = req['url'] as String;
        final method = (req['method'] as String? ?? 'GET').toUpperCase();
        final headersRaw = req['headers'];
        final headers = headersRaw is Map
            ? headersRaw.cast<String, dynamic>()
            : <String, dynamic>{};
        final body = req['body'];

        final response = await dio.request<String>(
          url,
          options: Options(
            method: method,
            headers: headers,
            responseType: ResponseType.plain,
            validateStatus: (_) => true,
          ),
          data: body,
        );

        // Aplanar headers List<String> → String (unir con ', ')
        final Map<String, String> flatHeaders = {};
        response.headers.forEach(
          (name, values) => flatHeaders[name] = values.join(', '),
        );

        return jsonEncode({
          'status': response.statusCode ?? 0,
          'statusText': response.statusMessage ?? '',
          'headers': flatHeaders,
          'body': response.data?.toString() ?? '',
        });
      } catch (e) {
        _log.warning('[${ext.package}] fetch error: $e');
        return jsonEncode({
          'status': 0,
          'statusText': e.toString(),
          'headers': <String, String>{},
          'body': '',
        });
      }
    });

    // ── Inyectar polyfill → luego evaluar el bundle ──────────────────────────
    rt.evaluate(_kPolyfill);

    try {
      rt.evaluate(script);

      // Los bundles de Prism+ usan el patrón IIFE:
      //   var io_prismhub_xxx = (() => { ... return exports; })();
      // Las funciones quedan en esa variable, NO en global scope.
      // Exponemos latest/search/detail/watch como globals para que
      // _callList pueda invocarlos directamente.
      final varName = ext.package.replaceAll('.', '_');
      rt.evaluate('''
(function() {
  var _m = (typeof $varName !== 'undefined') ? $varName : null;
  if (_m && typeof _m === 'object') {
    if (typeof _m.latest === 'function')
      globalThis.latest = function() { return _m.latest.apply(_m, arguments); };
    if (typeof _m.search === 'function')
      globalThis.search = function() { return _m.search.apply(_m, arguments); };
    if (typeof _m.detail === 'function')
      globalThis.detail = function() { return _m.detail.apply(_m, arguments); };
    if (typeof _m.watch === 'function')
      globalThis.watch  = function() { return _m.watch.apply(_m, arguments); };
  }
})();
''');
    } catch (e, st) {
      rt.dispose();
      dio.close();
      _log.severe('Error cargando extensión ${ext.package}', e, st);
      rethrow;
    }

    _log.info('Extensión cargada: ${ext.package} v${ext.version}');
    return ExtensionRuntime._(ext, rt, dio);
  }

  // ── API pública ─────────────────────────────────────────────────────────────

  Future<List<ExtResult>> latest(int page) => _callList('latest', [page]);

  Future<List<ExtResult>> search(
    String keyword,
    int page, [
    Map<String, dynamic>? filter,
  ]) => _callList('search', [keyword, page, filter ?? {}]);

  Future<ExtResult> detail(String url) => _callMap('detail', [url]);

  Future<ExtResult> watch(String url) => _callMap('watch', [url]);

  void dispose() {
    _rt.dispose();
    _dio.close(force: true);
  }

  // ── Helpers internos ────────────────────────────────────────────────────────

  Future<List<ExtResult>> _callList(String fn, List<dynamic> args) async {
    final js = '$fn(${_encodeArgs(args)})';
    final res = await _rt.evaluateAsync(js);
    if (res.isError) {
      _log.warning('[${extension.package}] $fn error: ${res.stringResult}');
      return [];
    }
    return _extractList(res.rawResult);
  }

  static List<ExtResult> _extractList(dynamic raw) {
    if (raw is List) return raw.whereType<Map>().map(_castMap).toList();
    if (raw is Map) {
      // PrismPage<T> — { items: [...], hasMore: bool, total?: number }
      final items = raw['items'];
      if (items is List) return items.whereType<Map>().map(_castMap).toList();
    }
    if (raw is String) {
      try {
        final decoded = jsonDecode(raw);
        return _extractList(decoded);
      } catch (_) {}
    }
    return [];
  }

  Future<ExtResult> _callMap(String fn, List<dynamic> args) async {
    final js = '$fn(${_encodeArgs(args)})';
    final res = await _rt.evaluateAsync(js);
    if (res.isError) {
      _log.warning('[${extension.package}] $fn error: ${res.stringResult}');
      return {};
    }
    final raw = res.rawResult;
    if (raw is Map) return _castMap(raw);
    if (raw is String) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return _castMap(decoded);
      } catch (_) {}
    }
    return {};
  }

  static String _encodeArgs(List<dynamic> args) =>
      args.map(jsonEncode).join(',');

  static ExtResult _castMap(Map m) => m.cast<String, dynamic>();
}

/// Registro central de runtimes activos (extensiones instaladas).
class ExtensionService {
  ExtensionService._();

  static final _log = Logger('ExtensionService');
  static final Map<String, ExtensionRuntime> _runtimes = {};

  static void init() {
    _log.info('ExtensionService inicializado');
  }

  static void load(ExtensionModel ext, String compiledScript) {
    _runtimes[ext.package]?.dispose();
    _runtimes[ext.package] = ExtensionRuntime.load(ext, compiledScript);
  }

  static void unload(String package) {
    _runtimes.remove(package)?.dispose();
  }

  static ExtensionRuntime? get(String package) => _runtimes[package];

  static List<ExtensionRuntime> get allLoaded => _runtimes.values.toList();

  static bool get hasAny => _runtimes.isNotEmpty;

  static void disposeAll() {
    for (final rt in _runtimes.values) {
      rt.dispose();
    }
    _runtimes.clear();
  }
}
