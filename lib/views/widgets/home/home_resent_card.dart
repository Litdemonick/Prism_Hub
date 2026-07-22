import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:get/get.dart';
import 'package:prismhub/models/extension.dart';
import 'package:prismhub/models/history.dart';
import 'package:prismhub/controllers/home_controller.dart';
import 'package:prismhub/router/router.dart';
import 'package:prismhub/utils/color.dart';
import 'package:prismhub/data/services/database_service.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/resume_history.dart';
import 'package:prismhub/views/widgets/cache_network_image.dart';
import 'package:prismhub/views/widgets/platform_widget.dart';

// Deliberately simple/synchronous: this card used to also check each item
// for a new chapter (checkUpdate — a real network fetch + JS eval that's
// blocking on this platform, see comic/video controller history) and tint
// the cover with a PaletteGenerator-derived color. Both ran async after the
// first frame, which meant the cover would render once, then visibly change
// (tint popping in) or show a broken "{}" badge (an empty-object JSON
// response treated as "there's an update" text because it wasn't empty as a
// *string*). None of that added enough value to justify the jank/bugs, so
// this card now only ever shows the cover, title, and "watched chapter X" —
// nothing here does any async work, so there's nothing to pop in late.
class HomeRecentCard extends StatefulWidget {
  const HomeRecentCard({
    super.key,
    required this.history,
  });
  final History history;

  @override
  State<HomeRecentCard> createState() => _HomeRecentCardState();
}

class _HomeRecentCardState extends State<HomeRecentCard> {
  final contextController = fluent.FlyoutController();
  final contextAttachKey = GlobalKey();
  late bool noCover = widget.history.cover == null;

  _delete() async {
    await DatabaseService.deleteHistoryByPackageAndUrl(
      widget.history.package,
      widget.history.url,
    );
    Get.find<HomePageController>().refreshHistory();
  }

  _delectAll() async {
    await DatabaseService.deleteAllHistory();
    Get.find<HomePageController>().refreshHistory();
  }

  Widget _titleBar() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        height: 60,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.black.withValues(alpha: 0.8),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                widget.history.title,
                style: const TextStyle(color: Colors.white),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                FlutterI18n.translate(
                  context,
                  "home.watched",
                  translationParams: {
                    "ep": widget.history.episodeTitle,
                  },
                ),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                ),
                maxLines: 1,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bangumiCard() {
    return Container(
      width: 350,
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Image.file(
            File(widget.history.cover!),
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
          ),
          _titleBar(),
        ],
      ),
    );
  }

  Widget _coverCard() {
    return Container(
      width: 350,
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(Radius.circular(8)),
        color: noCover ? ColorUtils.getColorByText(widget.history.title) : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          if (!noCover)
            CacheNetWorkImagePic(
              widget.history.cover!,
              width: double.infinity,
              height: double.infinity,
              fit: BoxFit.cover,
            ),
          _titleBar(),
        ],
      ),
    );
  }

  Widget _buildWidget() {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => resumeHistoryItem(context, widget.history),
          child: widget.history.type == ExtensionType.bangumi
              ? _bangumiCard()
              : _coverCard(),
        ),
      ),
    );
  }

  Widget _buildAndroid(BuildContext context) {
    return GestureDetector(
      onLongPress: () {
        showModalBottomSheet(
          context: context,
          builder: (context) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text('common.delete'.i18n),
                  onTap: () {
                    _delete();
                    Get.back();
                  },
                ),
                ListTile(
                  title: Text('common.delete-all'.i18n),
                  onTap: () {
                    _delectAll();
                    Get.back();
                  },
                ),
              ],
            );
          },
        );
      },
      child: _buildWidget(),
    );
  }

  Widget _buildDesktop(BuildContext context) {
    return GestureDetector(
      onSecondaryTapUp: (d) {
        final targetContext = contextAttachKey.currentContext;
        if (targetContext == null) return;
        final box = targetContext.findRenderObject() as RenderBox;
        final position = box.localToGlobal(
          d.localPosition,
          ancestor: Navigator.of(context).context.findRenderObject(),
        );
        contextController.showFlyout(
          barrierColor: Colors.black.withValues(alpha: 0.1),
          position: position,
          builder: (context) {
            return fluent.FlyoutContent(
              child: SizedBox(
                width: 200,
                child: fluent.CommandBar(
                  primaryItems: [
                    fluent.CommandBarButton(
                      label: Text('common.delete'.i18n),
                      onPressed: () {
                        _delete();
                        router.pop();
                      },
                    ),
                    fluent.CommandBarButton(
                      label: Text('common.delete-all'.i18n),
                      onPressed: () {
                        _delectAll();
                        router.pop();
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
      child: fluent.FlyoutTarget(
        key: contextAttachKey,
        controller: contextController,
        child: _buildWidget(),
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
