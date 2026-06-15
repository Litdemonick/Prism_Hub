import 'dart:async';

import 'package:get/get.dart';
import 'package:logging/logging.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../data/models/watch_data.dart';
import '../../data/services/extension/extension_service.dart';

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

  StreamSubscription<String>? _errorSub;
  StreamSubscription<bool>? _bufferingSub;
  StreamSubscription<bool>? _playingSub;

  // true en cuanto el player llega a buffering o playing para el stream actual.
  // Si stream.error llega ANTES de este flag, la URL es irreproduble (embed, formato
  // desconocido, etc.). Si llega DESPUÉS, es un error no-fatal (red, pista de sub).
  bool _streamAccepted = false;

  @override
  void onInit() {
    super.onInit();
    _player = Player();
    videoController = VideoController(_player);

    _bufferingSub = _player.stream.buffering.listen((b) {
      isBuffering.value = b;
      if (b) _streamAccepted = true;
    });

    _playingSub = _player.stream.playing.listen((playing) {
      if (playing) _streamAccepted = true;
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
        error.value = 'No se pudo reproducir el video';
      }
    });
  }

  Future<void> load(String episodeUrl, String package) async {
    isLoading.value = true;
    error.value = null;

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

  Future<void> switchStream(WatchStream stream) async {
    final pos = _player.state.position;
    await _openStream(stream);
    await _player.seek(pos);
  }

  Future<void> _openStream(WatchStream stream) async {
    _streamAccepted = false; // resetear para cada URL nueva
    selectedStream.value = stream;
    await _player.open(Media(stream.url, httpHeaders: stream.headers ?? {}));
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
