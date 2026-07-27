import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:prismhub/controllers/extension/extension_controller.dart';
import 'package:prismhub/views/widgets/extension/extension_tile.dart';
import 'package:prismhub/views/pages/extension/extension_repo_page.dart';
import 'package:prismhub/views/widgets/home/animated_background_glow.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/router/router.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/router.dart';
import 'package:prismhub/views/widgets/button.dart';
import 'package:prismhub/views/widgets/messenger.dart';
import 'package:prismhub/views/widgets/platform_widget.dart';

class ExtensionPage extends StatefulWidget {
  const ExtensionPage({super.key});

  @override
  State<ExtensionPage> createState() => _ExtensionPageState();
}

class _ExtensionPageState extends State<ExtensionPage> {
  late ExtensionPageController c;

  @override
  void initState() {
    c = Get.put(ExtensionPageController());
    c.isPageOpen = true;
    if (c.needRefresh) {
      c.onRefresh();
    }
    super.initState();
  }

  @override
  void dispose() {
    c.isPageOpen = false;
    super.dispose();
  }

  // 加载错误对话框
  _loadErrorDialog() {
    showPlatformDialog(
      context: context,
      title: 'extension.error-dialog'.i18n,
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 输出key 和 value
            for (final e in c.errors.entries)
              PlatformWidget(
                androidWidget: Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      "${e.key}: ${e.value}",
                    ),
                  ),
                ),
                desktopWidget: fluent.Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    "${e.key}: ${e.value}",
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        PlatformButton(
          onPressed: () {
            RouterUtils.pop();
          },
          child: Text('common.confirm'.i18n),
        ),
      ],
    );
  }

  Widget _buildAndroid(BuildContext context) {
    return Obx(() {
      return Scaffold(
        backgroundColor: HomeTheme.bg,
        appBar: AppBar(
          title: Text('common.extension-installed'.i18n),
          actions: [
            if (c.errors.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.error),
                onPressed: () => _loadErrorDialog(),
              ),
            IconButton(
              onPressed: () {
                Get.to(
                  () => const ExtensionRepoPage(),
                );
              },
              icon: const Icon(Icons.download),
            )
          ],
        ),
        body: Stack(
          children: [
            const Positioned.fill(child: AnimatedBackgroundGlow()),
            // Deslizar para actualizar: re-lee las extensiones instaladas y
            // vuelve a consultar qué versiones hay en el repo. Sin esto, una
            // extensión recién actualizada seguía marcada como "actualización
            // requerida" hasta cerrar y reabrir la app (reportado en vivo con
            // Olympus).
            RefreshIndicator(
              onRefresh: () async {
                ExtensionUtils.clearRemoteVersionsCache();
                await c.onRefresh();
              },
              color: HomeTheme.accentPink,
              backgroundColor: HomeTheme.cardSurface,
              child: ListView(
                // Sin esto, con pocas extensiones el contenido entra entero
                // en pantalla y no se puede hacer el gesto de arrastrar.
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  if (c.runtimes.isEmpty)
                    SizedBox(
                      height: 300,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('common.no-extension'.i18n),
                        ],
                      ),
                    ),
                  for (final ext in c.runtimes.values)
                    ExtensionTile(ext.extension),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _buildDesktop(BuildContext context) {
    return Container(
      color: HomeTheme.bg,
      child: Stack(
        children: [
          const Positioned.fill(child: AnimatedBackgroundGlow()),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Obx(
              () => Column(
                children: [
                  // Ancho máximo + centrado: en un monitor ancho la lista de
                  // filas horizontales quedaba estirada de punta a punta,
                  // dificil de leer — con el header y la lista adentro del
                  // mismo bloque centrado, todo queda alineado entre sí en
                  // vez de que el header quede suelto a lo ancho de toda la
                  // ventana.
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 900),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'common.extension-installed'.i18n,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const Spacer(),
                                // Refrescar: no había forma de recargar en
                                // desktop sin gesto de arrastrar (eso solo
                                // existe en Android) — vuelve a leer las
                                // extensiones instaladas Y limpia la caché de
                                // versiones remotas, igual que el gesto de
                                // Android.
                                fluent.IconButton(
                                  icon: const Icon(fluent.FluentIcons.refresh),
                                  onPressed: () {
                                    ExtensionUtils.clearRemoteVersionsCache();
                                    c.onRefresh();
                                  },
                                ),
                                const SizedBox(width: 4),
                                // 错误按钮
                                if (c.errors.isNotEmpty)
                                  fluent.IconButton(
                                    icon: const Icon(fluent.FluentIcons.error),
                                    onPressed: () {
                                      _loadErrorDialog();
                                    },
                                  ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            if (c.runtimes.isEmpty)
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text('common.no-extension'.i18n),
                                    const SizedBox(height: 8),
                                    fluent.FilledButton(
                                      child: Text(
                                        'common.extension-repo'.i18n,
                                      ),
                                      onPressed: () {
                                        router.push('/extension_repo');
                                      },
                                    )
                                  ],
                                ),
                              )
                            else
                              Expanded(
                                // padding derecha: mismo motivo que el
                                // repositorio — el scrollbar de desktop se
                                // dibuja pegado al borde del Scrollable y
                                // quedaba encima de las filas sin este margen.
                                child: ListView(
                                  padding: const EdgeInsets.only(
                                    right: 12,
                                    bottom: 24,
                                  ),
                                  children: [
                                    for (final ext in c.runtimes.values)
                                      Container(
                                        margin: const EdgeInsets.only(
                                          bottom: 8,
                                        ),
                                        child: ExtensionTile(ext.extension),
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PlatformBuildWidget(
      androidBuilder: _buildAndroid,
      desktopBuilder: _buildDesktop,
    );
  }
}
