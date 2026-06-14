import 'dart:convert';
import 'package:flutter_js/flutter_js.dart';
import 'package:logging/logging.dart';

import '../../../data/models/extension_model.dart';

/// Un resultado tipado de la API de extensión.
typedef ExtResult = Map<String, dynamic>;

/// Motor de extensiones TypeScript/JS.
///
/// Las extensiones se escriben en TypeScript y se compilan a bundles IIFE
/// con esbuild. El bundle expone cuatro funciones globales:
///
///   `latest(page)`                       → `Promise<PrismItem[]>`
///   `search(keyword, page, filter?)`    → `Promise<PrismItem[]>`
///   `detail(url)`                       → `Promise<PrismDetail>`
///   `watch(url)`                        → `Promise<PrismWatch>`
///
/// Cada extensión instanciada tiene su propio [JavascriptRuntime] aislado
/// para evitar colisiones de nombres globales entre extensiones.
class ExtensionRuntime {
  ExtensionRuntime._(this.extension, this._rt);

  final ExtensionModel extension;
  final JavascriptRuntime _rt;

  static final _log = Logger('ExtensionRuntime');

  /// Crea e inicializa un runtime para [ext] con el [script] compilado.
  static ExtensionRuntime load(ExtensionModel ext, String script) {
    final rt = getJavascriptRuntime();
    try {
      rt.evaluate(script);
    } catch (e, st) {
      rt.dispose();
      _log.severe('Error cargando extensión ${ext.package}', e, st);
      rethrow;
    }
    _log.info('Extensión cargada: ${ext.package} v${ext.version}');
    return ExtensionRuntime._(ext, rt);
  }

  Future<List<ExtResult>> latest(int page) =>
      _callList('latest', [page]);

  Future<List<ExtResult>> search(
    String keyword,
    int page, [
    Map<String, dynamic>? filter,
  ]) =>
      _callList('search', [keyword, page, filter ?? {}]);

  Future<ExtResult> detail(String url) =>
      _callMap('detail', [url]);

  Future<ExtResult> watch(String url) =>
      _callMap('watch', [url]);

  void dispose() => _rt.dispose();

  // ---------------------------------------------------------------------------

  Future<List<ExtResult>> _callList(String fn, List<dynamic> args) async {
    final js = '$fn(${_encodeArgs(args)})';
    final res = await _rt.evaluateAsync(js);
    if (res.isError) {
      _log.warning('[${extension.package}] $fn error: ${res.stringResult}');
      return [];
    }
    final raw = res.rawResult;
    if (raw is List) return raw.whereType<Map>().map(_castMap).toList();
    if (raw is String) {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded.whereType<Map>().map(_castMap).toList();
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
      final decoded = jsonDecode(raw);
      if (decoded is Map) return _castMap(decoded);
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

  static void disposeAll() {
    for (final rt in _runtimes.values) {
      rt.dispose();
    }
    _runtimes.clear();
  }
}
