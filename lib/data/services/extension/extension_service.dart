import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_js/flutter_js.dart';
import 'package:logging/logging.dart';

import '../../../data/models/extension_model.dart';

typedef ExtResult = Map<String, dynamic>;

// ---------------------------------------------------------------------------
// flutter_js 0.8.x / QuickJS — limitaciones críticas del bridge:
//
//   • evaluateAsync(code) = Future.value(evaluate(code)) — NO espera Promises
//   • onMessage handlers se llaman SÍNCRONAMENTE; si devuelven un Future,
//     QuickJS recibe el objeto Future como valor opaco ("Instance of Future")
//
// Solución: bridge completamente síncrono.
//
//   • sendMessage('prismFetch', req) → devuelve reqId (int) inmediatamente
//   • Dart inicia HTTP async en background
//   • Cuando termina, inyecta resultado con rt.evaluate('__prismDone(id,…)')
//   • JS Promise del fetch se resuelve dentro de esa evaluate() call
//   • Dart hace polling con await Future.delayed hasta que __prismR = true
// ---------------------------------------------------------------------------

// ── Polyfill inyectado en QuickJS ─────────────────────────────────────────────
const _kPolyfill = r'''
// ── console ──────────────────────────────────────────────────────────────────
(function() {
  function _s(lvl, a) {
    try { sendMessage('prismLog', lvl + Array.prototype.join.call(a, ' ')); } catch(_) {}
  }
  globalThis.console = {
    log:   function() { _s('[LOG] ',   arguments); },
    warn:  function() { _s('[WARN] ',  arguments); },
    error: function() { _s('[ERROR] ', arguments); },
    debug: function() { _s('[DEBUG] ', arguments); },
    info:  function() { _s('[INFO] ',  arguments); },
  };
})();

// ── btoa / atob ───────────────────────────────────────────────────────────────
(function() {
  var B = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  globalThis.btoa = function(s) {
    s = String(s); var o = '', i = 0, b;
    for (; i < s.length;) {
      var c1 = s.charCodeAt(i++), c2 = s.charCodeAt(i++), c3 = s.charCodeAt(i++);
      b = (c1 << 16) | (isNaN(c2) ? 0 : c2 << 8) | (isNaN(c3) ? 0 : c3);
      o += B[(b>>18)&63]+B[(b>>12)&63]+(isNaN(c2)?'=':B[(b>>6)&63])+(isNaN(c3)?'=':B[b&63]);
    }
    return o;
  };
  globalThis.atob = function(s) {
    s = String(s).replace(/[^A-Za-z0-9+/]/g, ''); var o = '', i = 0, b;
    while (i < s.length) {
      b = (B.indexOf(s[i++])<<18)|(B.indexOf(s[i++])<<12)|(B.indexOf(s[i++])<<6)|B.indexOf(s[i++]);
      if ((b>>16)&255) o += String.fromCharCode((b>>16)&255);
      if ((b>>8)&255)  o += String.fromCharCode((b>>8)&255);
      if (b&255)       o += String.fromCharCode(b&255);
    }
    return o;
  };
})();

// ── AbortController / AbortSignal (stub) ─────────────────────────────────────
(function() {
  function AbortSignal() { this.aborted = false; this._l = []; }
  AbortSignal.prototype.addEventListener = function(t, fn) {
    if (t === 'abort') this._l.push(fn);
  };
  AbortSignal.prototype.removeEventListener = function(t, fn) {
    var i = this._l.indexOf(fn); if (i !== -1) this._l.splice(i, 1);
  };
  AbortSignal.prototype._abort = function() {
    this.aborted = true;
    for (var i = 0; i < this._l.length; i++) try { this._l[i]({type:'abort'}); } catch(_) {}
  };
  function AbortController() { this.signal = new AbortSignal(); }
  AbortController.prototype.abort = function() { this.signal._abort(); };
  globalThis.AbortController = AbortController;
  globalThis.AbortSignal     = AbortSignal;
})();

// ── Fetch — bridge SÍNCRONO ───────────────────────────────────────────────────
// sendMessage('prismFetch', json) devuelve reqId (int) SÍNCRONAMENTE.
// Dart inyecta el resultado con __prismDone(id, responseJson) o __prismErr(id, msg).
var __prismCbs = {};
globalThis.fetch = function(input, init) {
  var url = (typeof input === 'string') ? input : (input && input.url ? input.url : '');
  var opt = init || {};
  var reqId = sendMessage('prismFetch', JSON.stringify({
    url:     url,
    method:  (opt.method  || 'GET').toUpperCase(),
    headers: opt.headers || {},
    body:    opt.body    || null,
  }));
  return new Promise(function(resolve, reject) {
    __prismCbs[reqId] = { ok: resolve, err: reject };
  });
};
globalThis.__prismDone = function(id, json) {
  var cb = __prismCbs[id]; if (!cb) return;
  delete __prismCbs[id];
  var d = JSON.parse(json), body = d.body || '', hdrs = d.headers || {};
  cb.ok({
    ok:         d.status >= 200 && d.status < 300,
    status:     d.status    || 0,
    statusText: d.statusText || '',
    url:        d.url       || '',
    headers: {
      get: function(n) { return hdrs[n.toLowerCase()] || null; },
      has: function(n) { return n.toLowerCase() in hdrs; },
    },
    text: function() { return Promise.resolve(body); },
    json: function() { return Promise.resolve(JSON.parse(body)); },
  });
};
globalThis.__prismErr = function(id, msg) {
  var cb = __prismCbs[id]; if (!cb) return;
  delete __prismCbs[id];
  cb.err(new Error(msg));
};

// ── Tracker de resultado de Promise ──────────────────────────────────────────
// Dart hace polling sobre estas variables.
globalThis.__prismR  = false;  // resolved
globalThis.__prismE  = false;  // rejected
globalThis.__prismV  = null;   // JSON.stringify del valor
globalThis.__prismER = null;   // mensaje de error
globalThis.__trackPrism = function(p) {
  __prismR = false; __prismE = false; __prismV = null; __prismER = null;
  Promise.resolve(p)
    .then(function(v)  { __prismV  = JSON.stringify(v); __prismR = true; })
    .catch(function(e) { __prismER = e ? (e.message || String(e)) : 'error'; __prismE = true; });
};
''';

class ExtensionRuntime {
  ExtensionRuntime._(this.extension, this._rt, this._dio);

  final ExtensionModel extension;
  final JavascriptRuntime _rt;
  final Dio _dio;

  static final _log = Logger('ExtensionRuntime');

  // Contador de requests HTTP pendientes por runtime
  int _reqId = 0;

  static ExtensionRuntime load(ExtensionModel ext, String script) {
    final rt  = getJavascriptRuntime();
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 60),
        validateStatus: (_) => true,
      ),
    );

    final runtime = ExtensionRuntime._(ext, rt, dio);

    // ── Bridge: console → Logger ─────────────────────────────────────────────
    rt.onMessage('prismLog', (dynamic args) {
      _log.info('[${ext.package}] $args');
      return null;
    });

    // ── Bridge: fetch SÍNCRONO ───────────────────────────────────────────────
    // Devuelve reqId inmediatamente; Dart inyecta el resultado después.
    rt.onMessage('prismFetch', (dynamic args) {
      final reqId = ++runtime._reqId;
      final raw   = args is String ? args : jsonEncode(args);
      runtime._startFetch(reqId, raw); // fire-and-forget
      return reqId;
    });

    // ── Polyfill + bundle + wrapper IIFE ────────────────────────────────────
    rt.evaluate(_kPolyfill);

    try {
      rt.evaluate(script);

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
      _log.severe('Error cargando ${ext.package}', e, st);
      rethrow;
    }

    _log.info('Extensión cargada: ${ext.package} v${ext.version}');
    return runtime;
  }

  // ── HTTP async (fire-and-forget, inyecta resultado con rt.evaluate) ─────────
  void _startFetch(int reqId, String reqJson) async {
    try {
      final req     = jsonDecode(reqJson) as Map<String, dynamic>;
      final url     = req['url'] as String;
      final method  = (req['method'] as String? ?? 'GET').toUpperCase();
      final hdrsRaw = req['headers'];
      final headers = hdrsRaw is Map
          ? hdrsRaw.cast<String, dynamic>()
          : <String, dynamic>{};
      final body    = req['body'];

      final res = await _dio.request<String>(
        url,
        options: Options(
          method: method,
          headers: headers,
          responseType: ResponseType.plain,
          validateStatus: (_) => true,
        ),
        data: body,
      );

      final Map<String, String> flat = {};
      res.headers.forEach((k, v) => flat[k] = v.join(', '));

      final payload = jsonEncode({
        'status':     res.statusCode    ?? 0,
        'statusText': res.statusMessage ?? '',
        'headers':    flat,
        'body':       res.data?.toString() ?? '',
        'url':        url,
      });

      // Inyectar resultado en QuickJS y procesar jobs pendientes
      _rt.evaluate('__prismDone($reqId, ${jsonEncode(payload)})');
    } catch (e) {
      _log.warning('[${extension.package}] fetch[$reqId] error: $e');
      _rt.evaluate('__prismErr($reqId, ${jsonEncode(e.toString())})');
    }
  }

  // ── API pública ──────────────────────────────────────────────────────────────

  Future<List<ExtResult>> latest(int page) => _callList('latest', [page]);

  Future<List<ExtResult>> search(
    String keyword,
    int page, [
    Map<String, dynamic>? filter,
  ]) => _callList('search', [keyword, page, filter ?? {}]);

  Future<ExtResult> detail(String url) => _callMap('detail', [url]);

  Future<ExtResult> watch(String url)   => _callMap('watch',  [url]);

  void dispose() {
    _rt.dispose();
    _dio.close(force: true);
  }

  // ── Polling ──────────────────────────────────────────────────────────────────
  // Arranca la función JS y hace polling hasta que la Promise resuelva.
  // Entre iteraciones, Dart event-loop procesa los HTTP completados y los
  // inyecta en QuickJS vía _startFetch → _rt.evaluate('__prismDone(…)').

  Future<List<ExtResult>> _callList(String fn, List<dynamic> args) async {
    _rt.evaluate('__trackPrism($fn(${_encodeArgs(args)}))');
    return _parseList(await _poll(fn));
  }

  Future<ExtResult> _callMap(String fn, List<dynamic> args) async {
    _rt.evaluate('__trackPrism($fn(${_encodeArgs(args)}))');
    return _parseMap(await _poll(fn));
  }

  // Máximo 30 s de espera (300 × 100 ms). Entre cada tick cede el control
  // al event-loop de Dart para que los HTTP pendientes puedan completarse.
  Future<String?> _poll(String fn) async {
    for (int i = 0; i < 300; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));

      if (_rt.evaluate('__prismR').stringResult == 'true') {
        return _rt.evaluate('__prismV').stringResult;
      }
      if (_rt.evaluate('__prismE').stringResult == 'true') {
        final err = _rt.evaluate('__prismER').stringResult ?? 'unknown';
        _log.warning('[${extension.package}] $fn error: $err');
        return null;
      }
    }
    _log.warning('[${extension.package}] $fn timeout (30 s)');
    return null;
  }

  // ── Parsers ──────────────────────────────────────────────────────────────────

  static List<ExtResult> _parseList(String? raw) {
    if (raw == null || raw.isEmpty || raw == 'null') return [];
    try {
      final d = jsonDecode(raw);
      if (d is List) return d.whereType<Map>().map(_castMap).toList();
      if (d is Map) {
        final items = d['items'];
        if (items is List) return items.whereType<Map>().map(_castMap).toList();
      }
    } catch (e) {
      _log.warning('_parseList: $e  raw=${raw.length > 80 ? raw.substring(0,80) : raw}');
    }
    return [];
  }

  static ExtResult _parseMap(String? raw) {
    if (raw == null || raw.isEmpty || raw == 'null') return {};
    try {
      final d = jsonDecode(raw);
      if (d is Map) return _castMap(d);
    } catch (e) {
      _log.warning('_parseMap: $e');
    }
    return {};
  }

  static String _encodeArgs(List<dynamic> args) => args.map(jsonEncode).join(',');
  static ExtResult _castMap(Map m) => m.cast<String, dynamic>();
}

/// Registro central de runtimes activos.
class ExtensionService {
  ExtensionService._();

  static final _log = Logger('ExtensionService');
  static final Map<String, ExtensionRuntime> _runtimes = {};

  static void init() => _log.info('ExtensionService inicializado');

  static void load(ExtensionModel ext, String compiledScript) {
    _runtimes[ext.package]?.dispose();
    _runtimes[ext.package] = ExtensionRuntime.load(ext, compiledScript);
  }

  static void unload(String package) => _runtimes.remove(package)?.dispose();

  static ExtensionRuntime? get(String package) => _runtimes[package];

  static List<ExtensionRuntime> get allLoaded => _runtimes.values.toList();

  static bool get hasAny => _runtimes.isNotEmpty;

  static void disposeAll() {
    for (final rt in _runtimes.values) rt.dispose();
    _runtimes.clear();
  }
}
