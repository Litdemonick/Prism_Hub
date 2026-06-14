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
  final error = Rxn<String>();
  final watchData = Rxn<WatchData>();
  final selectedStream = Rxn<WatchStream>();

  @override
  void onInit() {
    super.onInit();
    _player = Player();
    videoController = VideoController(_player);
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
        error.value = 'Sin streams disponibles';
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
    selectedStream.value = stream;
    await _player.open(Media(stream.url, httpHeaders: stream.headers ?? {}));
  }

  @override
  void onClose() {
    _player.dispose();
    super.onClose();
  }
}
