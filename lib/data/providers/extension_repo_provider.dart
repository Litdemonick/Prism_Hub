import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:logging/logging.dart';

import '../models/extension_dto.dart';

class ExtensionRepoProvider {
  ExtensionRepoProvider()
    : _dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
        ),
      );

  final Dio _dio;
  static final _log = Logger('ExtensionRepoProvider');

  /// Agrega un parámetro único para saltar el caché de la CDN.
  static String _bust(String url) {
    final sep = url.contains('?') ? '&' : '?';
    return '$url${sep}_=${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<RepoIndex> fetchIndex(String repoUrl) async {
    try {
      // Pedir como String para no depender del Content-Type del servidor
      // (raw.githubusercontent.com devuelve text/plain, no application/json).
      // Cache-buster + headers no-cache: la CDN de GitHub (Fastly) cachea el
      // mismo URL ~5 min; sin esto el catálogo de versiones llega desactualizado
      // y las extensiones nuevas nunca se instalan.
      final response = await _dio.get<String>(
        _bust(repoUrl),
        options: Options(
          responseType: ResponseType.plain,
          headers: const {'Cache-Control': 'no-cache', 'Pragma': 'no-cache'},
        ),
      );

      final body = response.data;
      if (body == null || body.trim().isEmpty) {
        throw Exception('Respuesta vacía de $repoUrl');
      }

      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw Exception('Formato inválido en $repoUrl');
      }

      return RepoIndex.fromJson(decoded, repoUrl);
    } on DioException catch (e, st) {
      _log.warning('Error al obtener repo $repoUrl: ${e.message}', e, st);
      rethrow;
    }
  }
}
