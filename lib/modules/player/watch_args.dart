import '../../data/models/extension_model.dart';

/// Argumentos de navegación hacia PlayerPage o ReaderPage.
class WatchArgs {
  const WatchArgs({
    required this.episodeUrl,
    required this.package,
    required this.title,
    required this.type,
  });

  final String episodeUrl;
  final String package;
  final String title;
  final ExtensionType type;
}
