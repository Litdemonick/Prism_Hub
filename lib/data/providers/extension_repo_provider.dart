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

  Future<RepoIndex> fetchIndex(String repoUrl) async {
    try {
      // Pedir como String para no depender del Content-Type del servidor
      // (raw.githubusercontent.com devuelve text/plain, no application/json)
      final response = await _dio.get<String>(
        repoUrl,
        options: Options(responseType: ResponseType.plain),
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
