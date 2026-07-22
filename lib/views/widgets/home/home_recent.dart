import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:prismhub/models/history.dart';
import 'package:prismhub/router/router.dart';
import 'package:prismhub/views/pages/history_page.dart';
import 'package:prismhub/views/widgets/home/home_resent_card.dart';
import 'package:prismhub/views/widgets/horizontal_list.dart';
import 'package:prismhub/views/widgets/horizontal_scroll_fade.dart';
import 'package:prismhub/utils/i18n.dart';

class HomeRecent extends StatelessWidget {
  const HomeRecent({
    super.key,
    required this.data,
  });
  final List<History> data;

  void _openHistoryPage() {
    if (Platform.isAndroid) {
      Get.to(const HistoryPage());
      return;
    }
    router.push('/history');
  }

  @override
  Widget build(BuildContext context) {
    return HorizontalList(
      title: "home.continue-watching".i18n,
      onClickMore: _openHistoryPage,
      // contentBuilder (not itemBuilder) — itemBuilder wraps each item in a
      // fixed 110/170px-wide box, but HomeRecentCard renders itself at a
      // hardcoded 350px; this keeps the original unconstrained ListView.
      contentBuilder: (controller) {
        final list = ListView.builder(
          scrollDirection: Axis.horizontal,
          controller: controller,
          itemCount: data.length,
          itemBuilder: (context, index) => HomeRecentCard(history: data[index]),
        );
        // El indicador animado es solo para celular — en desktop ya están
        // las flechas de navegación junto al título, no hace falta duplicar.
        return SizedBox(
          height: 200,
          child: Platform.isAndroid
              ? HorizontalScrollFade(controller: controller, child: list)
              : list,
        );
      },
    );
  }
}
