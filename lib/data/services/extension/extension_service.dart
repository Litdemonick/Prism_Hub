import 'package:flutter_js/flutter_js.dart';
import 'package:logging/logging.dart';

import '../../../data/models/extension_model.dart';

/// Resultado de llamar a una función JS de la extensión.
typedef ExtResult = Map<String, dynamic>;

/// Motor que ejecuta extensiones JavaScript (formato Miru-compatible).
///
/// Cada extensión expone:
///   latest(page)                 → List<item>
///   search(keyword, page, filter) → List<item>
///   detail(url)                  → Map (título, episodios, etc.)
///   watch(url)                   → Map (streams, subtítulos)
class ExtensionService {
  ExtensionService._();

  static final _log = Logger('ExtensionService');
  static late JavascriptRuntime _runtime;

  // Caché: package → script JS cargado
  static final Map<String, bool> _loaded = {};

  static void init() {
    _runtime = getJavascriptRuntime();
    _log.info('JS runtime initialized');
  }

  static void loadExtension(ExtensionModel ext, String script) {
    if (_loaded[ext.package] == true) return;
    try {
      _runtime.evaluate(script);
      _loaded[ext.package] = true;
      _log.info('Extension loaded: ${ext.package}');
    } catch (e, st) {
      _log.severe('Failed to load extension ${ext.package}', e, st);
      rethrow;
    }
  }

  static Future<List<ExtResult>> latest(String fnPrefix, int page) =>
      _callList('${fnPrefix}_latest', [page]);

  static Future<List<ExtResult>> search(
          String fnPrefix, String keyword, int page,
          [Map<String, dynamic>? filter]) =>
      _callList('${fnPrefix}_search', [keyword, page, filter ?? {}]);

  static Future<ExtResult> detail(String fnPrefix, String url) =>
      _callMap('${fnPrefix}_detail', [url]);

  static Future<ExtResult> watch(String fnPrefix, String url) =>
      _callMap('${fnPrefix}_watch', [url]);

  static Future<List<ExtResult>> _callList(
      String fn, List<dynamic> args) async {
    final result = await _runtime.evaluateAsync(
        '$fn(${args.map(_toJs).join(',')})');
    if (result.isError) {
      _log.warning('JS error in $fn: ${result.stringResult}');
      return [];
    }
    final list = result.rawResult as List? ?? [];
    return list.cast<ExtResult>();
  }

  static Future<ExtResult> _callMap(String fn, List<dynamic> args) async {
    final result = await _runtime.evaluateAsync(
        '$fn(${args.map(_toJs).join(',')})');
    if (result.isError) {
      _log.warning('JS error in $fn: ${result.stringResult}');
      return {};
    }
    return (result.rawResult as Map?)?.cast<String, dynamic>() ?? {};
  }

  static String _toJs(dynamic value) {
    if (value == null) return 'null';
    if (value is String) return '"${value.replaceAll('"', '\\"')}"';
    if (value is num || value is bool) return value.toString();
    if (value is Map || value is List) return value.toString();
    return '"$value"';
  }
}
