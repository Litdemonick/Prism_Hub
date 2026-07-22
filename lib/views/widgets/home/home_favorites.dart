import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:prismhub/models/index.dart';
import 'package:prismhub/views/pages/history_page.dart';
import 'package:prismhub/router/router.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/views/widgets/extension_item_card.dart';
import 'package:prismhub/views/widgets/horizontal_list.dart';

// One combined "Favoritos" row on Home mixing every type together — matches
// how "Continuar" already mixes video/manga/novel, and how the History
// page's own Favoritos tab already shows them combined.
class HomeFavorites extends StatelessWidget {
  const HomeFavorites({
    super.key,
    required this.data,
  });
  final List<Favorite> data;

  // History page's Favoritos tab is index 4 — land straight there instead of
  // the generic "all" tab.
  static const _favoritesTabIndex = 4;

  void _openHistoryPage() {
    if (Platform.isAndroid) {
      Get.to(const HistoryPage(initialTab: _favoritesTabIndex));
      return;
    }
    router.push(
      Uri(
        path: '/history',
        queryParameters: {'tab': _favoritesTabIndex.toString()},
      ).toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const SizedBox.shrink();
    }
    return HorizontalList(
      title: 'home.favorite'.i18n,
      onClickMore: _openHistoryPage,
      itemCount: data.length,
      itemBuilder: (context, index) {
        return ExtensionItemCard(
          key: ValueKey(data[index].cover),
          title: data[index].title,
          url: data[index].url,
          package: data[index].package,
          cover: data[index].cover,
          type: data[index].type,
        );
      },
    );
  }
}
