abstract final class AppConfig {
  static const String appName = 'PrismHub';
  static const String version = '1.0.0';
  static const String packageName = 'com.prismhub.app';

  /// URL del índice oficial de Prism+ — motor de extensiones de PrismHub.
  static const String prismPlusRepoUrl =
      'https://raw.githubusercontent.com/Litdemonick/prism-plus/main/dist/index.json';

  /// Repositorios integrados: siempre presentes, no se pueden eliminar.
  static const List<String> builtInRepos = [prismPlusRepoUrl];
}
