import 'dart:async';

import 'package:get/get.dart';
import 'package:logging/logging.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../data/models/watch_data.dart';
import '../../data/services/extension/extension_service.dart';
import '../../data/services/player/hls_proxy_service.dart';

class PlayerController extends GetxController {
  static final _log = Logger('PlayerController');

  late final Player _player;
  late final VideoController videoController;

  final isLoading = true.obs;
  final isBuffering = false.obs;
  final error = Rxn<String>();
  final watchData = Rxn<WatchData>();
  final selectedStream = Rxn<WatchStream>();
  final selectedSubtitleIdx = (-1).obs;
  final speed = 1.0.obs;

  // Mensaje transitorio de cambio automático de servidor ("X falló, probando Y").
  final switchMessage = RxnString();

  StreamSubscription<String>? _errorSub;
  StreamSubscription<bool>? _bufferingSub;
  StreamSubscription<bool>? _playingSub;

  // true en cuanto el player llega a buffering o playing para el stream actual.
  // Si stream.error llega ANTES de este flag, la URL es irreproduble (embed, formato
  // desconocido, etc.). Si llega DESPUÉS, es un error no-fatal (red, pista de sub).
  bool _streamAccepted = false;

  // URLs de servidores que ya fallaron en este episodio → no se reintentan en
  // el auto-fallback. Se limpia en cada load()/retryAll().
  final Set<String> _failedStreams = {};
  // Evita reentradas mientras se cambia de servidor automáticamente.
  bool _advancing = false;

  @override
  void onInit() {
    super.onInit();
    _player = Player();
    videoController = VideoController(_player);

    _bufferingSub = _player.stream.buffering.listen((b) {
      isBuffering.value = b;
      if (b) {
        _streamAccepted = true;
        switchMessage.value = null; // el servidor respondió → ocultar aviso
      }
    });

    _playingSub = _player.stream.playing.listen((playing) {
      if (playing) {
        _streamAccepted = true;
        switchMessage.value = null;
      }
    });

    _errorSub = _player.stream.error.listen((err) {
      if (err.isEmpty || error.value != null) return;
      _log.warning('media_kit: $err');
      // Errores que indican URL irreproduble son siempre fatales (embed pages,
      // formato desconocido, etc.), aunque buffering haya disparado brevemente.
      final isFatalUrl =
          err.contains('Failed to open') ||
          err.contains('Failed to recognize file format') ||
          err.contains('No suitable demuxer found');
      if (isFatalUrl || (!isLoading.value && !_streamAccepted)) {
        _onStreamFailed();
      }
    });
  }

  /// El servidor actual falló: marca como fallido y salta automáticamente al
  /// siguiente servidor no probado. Solo cuando se agotan todos muestra error.
  void _onStreamFailed() {
    if (_advancing) return;
    final streams = watchData.value?.streams ?? const [];
    final current = selectedStream.value;
    if (current != null) _failedStreams.add(current.url);

    WatchStream? next;
    for (final s in streams) {
      if (!_failedStreams.contains(s.url)) {
        next = s;
        break;
      }
    }

    if (next != null) {
      _advancing = true;
      final from = current?.displayLabel ?? 'servidor';
      switchMessage.value =
          'Servidor "$from" falló — probando "${next.displayLabel}"…';
      _log.info('Auto-fallback: $from → ${next.displayLabel}');
      _openStream(next).whenComplete(() => _advancing = false);
    } else {
      switchMessage.value = null;
      error.value = 'Ningún servidor pudo reproducir este episodio';
    }
  }

  /// Reintenta desde el primer servidor (botón "Reintentar" de la pantalla de error).
  Future<void> retryAll() async {
    final streams = watchData.value?.streams ?? const [];
    if (streams.isEmpty) return;
    _failedStreams.clear();
    error.value = null;
    isLoading.value = true;
    await _openStream(streams.first);
    isLoading.value = false;
  }

  Future<void> load(String episodeUrl, String package) async {
    isLoading.value = true;
    error.value = null;
    switchMessage.value = null;
    _failedStreams.clear();

    final rt = ExtensionService.get(package);
    if (rt == null) {
      error.value = 'Extensión no disponible';
      isLoading.value = false;
      return;
    }

    try {
      final raw = await rt.watch(episodeUrl);
      final data = WatchData.fromMap(raw);
      watchData.value = data;

      // Diagnóstico: qué devolvió watch() (resuelto vs embed crudo).
      for (final s in data.streams) {
        final kind = s.url.contains('.m3u8')
            ? 'HLS'
            : (s.url.contains('.mp4') || s.url.contains('get_video'))
            ? 'MP4'
            : 'CRUDO';
        _log.info('stream [${s.quality}] $kind: ${s.url}');
      }

      if (data.streams.isEmpty) {
        error.value = data.reason != null
            ? '__reason__'
            : 'Sin streams disponibles';
        isLoading.value = false;
        return;
      }

      await _openStream(data.streams.first);
    } catch (e, st) {
      _log.severe('Error cargando watch', e, st);
      error.value = 'Error al cargar el video';
    } finally {
      isLoading.value = false;
    }
  }

  /// Cambio manual de servidor desde el selector. El usuario lo eligió a
  /// propósito, así que se limpia el error y se re-habilita ese servidor.
  Future<void> switchStream(WatchStream stream) async {
    final pos = _player.state.position;
    _failedStreams.remove(stream.url);
    error.value = null;
    switchMessage.value = null;
    await _openStream(stream);
    await _player.seek(pos);
  }

  Future<void> _openStream(WatchStream stream) async {
    _streamAccepted = false; // resetear para cada URL nueva
    selectedStream.value = stream;

    // Para HLS con cabeceras, enrutar por el proxy local: garantiza que el
    // Referer/Cookie/Origin lleguen a cada segmento (evita los 403 que dejan el
    // vídeo en buffering infinito). Para mp4 directo devuelve la URL original.
    final playUrl = await HlsProxyService.resolve(stream.url, stream.headers);
    final useProxy = playUrl != stream.url;

    await _player.open(
      Media(playUrl, httpHeaders: useProxy ? const {} : (stream.headers ?? {})),
    );
  }

  Future<void> setSubtitle(int index) async {
    selectedSubtitleIdx.value = index;
    final subs = watchData.value?.subtitles ?? [];
    if (index < 0 || index >= subs.length) {
      await _player.setSubtitleTrack(SubtitleTrack.no());
    } else {
      final sub = subs[index];
      await _player.setSubtitleTrack(
        SubtitleTrack.uri(sub.url, title: sub.label, language: sub.lang ?? ''),
      );
    }
  }

  Future<void> setSpeed(double s) async {
    speed.value = s;
    await _player.setRate(s);
  }

  @override
  void onClose() {
    _errorSub?.cancel();
    _bufferingSub?.cancel();
    _playingSub?.cancel();
    _player.dispose();
    super.onClose();
  }
}
