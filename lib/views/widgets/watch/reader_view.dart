import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:prismhub/utils/layout.dart';
import 'package:prismhub/views/widgets/watch/control_panel_footer.dart';
import 'package:prismhub/views/widgets/watch/control_panel_header.dart';
import 'package:prismhub/controllers/watch/reader_controller.dart';

class ReaderView<T extends ReaderController> extends StatelessWidget {
  const ReaderView(
    this.tag, {
    super.key,
    required this.content,
    required this.buildSettings,
    this.buildFooter,
  });
  final String tag;
  final Widget content;
  final Widget Function(BuildContext context) buildSettings;
  final Widget Function(BuildContext context)? buildFooter;

  @override
  Widget build(BuildContext context) {
    final c = Get.find<T>(tag: tag);
    return Obx(
      () => Stack(
        children: [
          MouseRegion(
            onHover: (event) {
              if (event.position.dy < 60) {
                c.showControlPanel();
              }
              if (event.position.dy > LayoutUtils.height - 60) {
                c.showControlPanel();
              }
            },
            child: content,
          ),

          // Center tap zone: toggle control panel (or page nav on desktop).
          // Uses onTap (not onTapDown) so a scroll/drag gesture is NOT
          // misinterpreted as a tap — the GestureArena settles first and the
          // callback only fires on a genuine short-press with no movement.
          if (c.error.value.isEmpty)
            Positioned(
              top: 120,
              bottom: 120,
              left: 0,
              right: 0,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  // On Android the left/right zones just toggle the panel;
                  // page navigation is handled by the comic's own controls.
                  if (Platform.isAndroid) {
                    c.isShowControlPanel.value =
                        !c.isShowControlPanel.value;
                    return;
                  }
                  // Desktop: left third → prev, right third → next, center → panel.
                  // Using a separate callback instead of relying on the tap
                  // position from onTapDown to avoid frame-delay issues.
                },
                onTapUp: Platform.isAndroid
                    ? null
                    : (details) {
                        final xPos = details.globalPosition.dx;
                        final width = LayoutUtils.width;
                        final unitWidth = width / 3;
                        if (xPos < unitWidth) {
                          c.previousPage();
                        } else if (xPos > unitWidth * 2) {
                          c.nextPage();
                        } else {
                          c.isShowControlPanel.value =
                              !c.isShowControlPanel.value;
                        }
                      },
              ),
            ),

          if (c.isShowControlPanel.value) ...[
            // 顶部控制
            Positioned(
              child: ControlPanelHeader<T>(
                tag,
                buildSettings: buildSettings,
              ),
            ),
            // 底部控制
            Positioned(
              right: 0,
              left: 0,
              bottom: 0,
              child: buildFooter != null
                  ? buildFooter!(context)
                  : ControlPanelFooter<T>(tag),
            ),
          ]
        ],
      ),
    );
  }
}
