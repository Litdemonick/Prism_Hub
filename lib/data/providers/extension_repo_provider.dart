import 'package:dio/dio.dart';
import 'package:logging/logging.dart';

import '../models/extension_dto.dart';

class ExtensionRepoProvider {
  ExtensionRepoProvider()
    : _dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

  final Dio _dio;
  static final _log = Logger('ExtensionRepoProvider');

  Future<RepoIndex> fetchIndex(String repoUrl) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(repoUrl);
      final data = response.data;
      if (data == null) throw Exception('Respuesta vacía de $repoUrl');
      return RepoIndex.fromJson(data, repoUrl);
    } on DioException catch (e, st) {
      _log.warning('Error al obtener repo $repoUrl', e, st);
      rethrow;
    }
  }
}
