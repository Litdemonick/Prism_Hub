import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:get/get.dart';
import 'package:prismhub/controllers/home_controller.dart';
import 'package:prismhub/controllers/main_controller.dart';
import 'package:prismhub/router/router.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/resume_history.dart';
import 'package:prismhub/views/pages/detail_page.dart';
import 'package:prismhub/views/pages/history_page.dart';
import 'package:prismhub/views/widgets/home/home_category_chips.dart';
import 'package:prismhub/views/widgets/home/home_hero_banner.dart';
import 'package:prismhub/views/widgets/home/home_library_genre_chips.dart';
import 'package:prismhub/views/widgets/home/home_media_card.dart';
import 'package:prismhub/views/widgets/home/home_section.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/platform_widget.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late HomePageController c;

  static const _favoritesTabIndex = 4;

  @override
  void initState() {
    c = Get.put(HomePageController());
    super.initState();
  }

  void _openDetail(String url, String package) {
    if (Platform.isAndroid) {
      Get.to(DetailPage(url: url, package: package, tag: url));
      return;
    }
    router.push(
      Uri(
        path: '/detail',
        queryParameters: {'url': url, 'package': package},
      ).toString(),
    );
  }

  void _openHistoryTab(int tab) {
    if (Platform.isAndroid) {
      Get.to(HistoryPage(initialTab: tab));
      return;
    }
    router.push(
      Uri(path: '/history', queryParameters: {'tab': tab.toString()})
          .toString(),
    );
  }

  void _openSearch() {
    if (Platform.isAndroid) {
      Get.find<MainController>().changeTab(1);
      return;
    }
    router.go('/search');
  }

  Widget _buildContent() {
    return Obx(
      () {
        final somethingElse = c.resents.isNotEmpty ||
            c.favorites.isNotEmpty ||
            c.recommended.isNotEmpty;

        return Container(
          color: HomeTheme.bg,
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  HomeHeroBanner(background: c.heroBackground.value),
                  const SizedBox(height: 32),
                  if (!somethingElse) ...[
                    Center(
                      child: Column(
                        children: [
                          const Text(
                            "（＞人＜；）",
                            style: TextStyle(
                              fontSize: 50,
                              fontWeight: FontWeight.bold,
                              color: HomeTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            "home.no-record".i18n,
                            style: const TextStyle(color: HomeTheme.textMuted),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (c.resents.isNotEmpty) ...[
                    HomeSection(
                      title: 'home.continue-watching'.i18n,
                      onClickMore: () => _openHistoryTab(0),
                      itemCount: c.resents.length,
                      itemBuilder: (context, index) {
                        final h = c.resents[index];
                        return HomeMediaCard(
                          title: h.title,
                          subtitle: FlutterI18n.translate(
                            context,
                            'home.watched-episode',
                            translationParams: {'ep': (h.episodeId + 1).toString()},
                          ),
                          badge: ExtensionUtils.typeToString(h.type),
                          cover: h.cover,
                          // Sin barra de progreso — el texto de arriba ya
                          // dice el episodio, la tarjeta es solo para
                          // retomar donde quedaste.
                          onTap: () => resumeHistoryItem(context, h),
                        );
                      },
                    ),
                    const SizedBox(height: 32),
                  ],
                  if (c.favorites.isNotEmpty) ...[
                    HomeSection(
                      title: 'home.favorite'.i18n,
                      onClickMore: () => _openHistoryTab(_favoritesTabIndex),
                      itemCount: c.favorites.length,
                      itemBuilder: (context, index) {
                        final f = c.favorites[index];
                        return HomeMediaCard(
                          title: f.title,
                          subtitle: 'home.favorite'.i18n,
                          badge: ExtensionUtils.typeToString(f.type),
                          cover: f.cover,
                          onTap: () => _openDetail(f.url, f.package),
                        );
                      },
                    ),
                    const SizedBox(height: 32),
                  ],
                  if (c.recommended.isNotEmpty) ...[
                    HomeSection(
                      title: 'home.recommended'.i18n,
                      onClickMore: _openSearch,
                      itemCount: c.recommended.length,
                      itemBuilder: (context, index) {
                        final r = c.recommended[index];
                        return HomeMediaCard(
                          title: r.title,
                          badge: ExtensionUtils.typeToString(r.type),
                          cover: r.cover,
                          headers: r.headers,
                          onTap: () => _openDetail(r.url, r.package),
                        );
                      },
                    ),
                    const SizedBox(height: 32),
                  ],
                  HomeCategoryChips(controller: c),
                  const SizedBox(height: 24),
                  HomeLibraryGenreChips(controller: c),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAndroidHome(BuildContext context) {
    return Scaffold(
      backgroundColor: HomeTheme.bg,
      appBar: AppBar(
        backgroundColor: HomeTheme.bg,
        title: Text(
          "common.home".i18n,
          style: const TextStyle(color: HomeTheme.textPrimary),
        ),
      ),
      body: _buildContent(),
    );
  }

  Widget _buildDesktopHome(BuildContext context) {
    return _buildContent();
  }

  @override
  Widget build(BuildContext context) {
    return PlatformBuildWidget(
      androidBuilder: _buildAndroidHome,
      desktopBuilder: _buildDesktopHome,
    );
  }
}
