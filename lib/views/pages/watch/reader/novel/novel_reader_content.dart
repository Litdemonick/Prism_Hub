import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:prismhub/controllers/watch/novel_controller.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/router.dart';
import 'package:prismhub/views/widgets/watch/aviso_extension_caida.dart';
import 'package:prismhub/views/widgets/button.dart';
import 'package:prismhub/views/widgets/platform_widget.dart';
import 'package:prismhub/views/widgets/progress.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

class NovelReaderContent extends StatefulWidget {
  const NovelReaderContent(this.tag, {super.key});
  final String tag;

  @override
  State<NovelReaderContent> createState() => _NovelReaderContentState();
}

class _NovelReaderContentState extends State<NovelReaderContent> {
  late final _c = Get.find<NovelController>(tag: widget.tag);

  _buildContent() {
    return LayoutBuilder(
      builder: (context, constraints) => Obx(
        () {
          // // 宽度 大于 800 就是整体宽度的一半
          final maxWidth = constraints.maxWidth;
          // final width = maxWidth > 800 ? maxWidth / 2 : maxWidth;
          // final height = constraints.maxHeight;
          // Mismo criterio que en el lector de cómics: si la extensión se cayó
          // no hay con qué reintentar, así que se ofrece salir y no otra vuelta
          // contra algo que ya no está.
          final caida = _c.extensionCaida.value;
          if (caida != null) {
            return AvisoExtensionCaida(
              motivo: caida.i18n,
              onSalir: () => RouterUtils.closeReader(context),
            );
          }
          if (_c.error.value.isNotEmpty) {
            return SizedBox(
              width: double.infinity,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_c.error.value),
                  const SizedBox(height: 20),
                  PlatformButton(
                    child: Text('common.retry'.i18n),
                    onPressed: () {
                      _c.getContent();
                    },
                  )
                ],
              ),
            );
          }

          if (_c.watchData.value == null) {
            return const Center(child: ProgressRing());
          }

          final watchData = _c.watchData.value!;

          final listviewPadding =
              maxWidth > 800 ? ((maxWidth - 800) / 2) : 16.0;

          final fontSize = _c.fontSize.value;

          return Center(
            child: ScrollablePositionedList.builder(
              itemPositionsListener: _c.itemPositionsListener,
              // Acotado a este capítulo: si quedara apuntando a un párrafo que
              // no existe acá, el paquete ancla la lista al último ítem y el
              // capítulo abre al fondo (ver comic_reader_content).
              initialScrollIndex:
                  _c.positions.value.clamp(0, watchData.content.length + 1),
              padding: EdgeInsets.symmetric(
                horizontal: listviewPadding,
                vertical: 16,
              ),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Text(
                      _c.title + _c.playList[_c.playIndex].name,
                      style: const TextStyle(fontSize: 26),
                    ),
                  );
                }
                if (index == 1) {
                  return (watchData.subtitle != null)
                      ? Padding(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: Text(
                            watchData.subtitle!,
                            style: const TextStyle(fontSize: 20),
                          ),
                        )
                      : const SizedBox();
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: SelectableText.rich(
                    TextSpan(
                      children: [
                        const WidgetSpan(child: SizedBox(width: 40.0)),
                        TextSpan(
                          text: watchData.content[index - 2],
                          style: TextStyle(
                            fontSize: fontSize,
                            fontWeight: FontWeight.w400,
                            height: 2,
                            textBaseline: TextBaseline.ideographic,
                            fontFamily: 'Microsoft Yahei',
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
              itemCount: watchData.content.length + 2,
            ),
          );

          // const TextStyle textStyle = TextStyle(
          //   fontSize: 18,
          //   fontWeight: FontWeight.w400,
          //   height: 2,
          //   textBaseline: TextBaseline.ideographic,
          // );

          // // 获取每句子的高
          // final List<double> heightList = [];
          // for (final String sentence in content) {
          //   final TextPainter painter = TextPainter(
          //     text: TextSpan(
          //       text: sentence,
          //       style: textStyle,
          //     ),
          //     textDirection: TextDirection.ltr,
          //   )..layout(maxWidth: width - 140);
          //   heightList.add(painter.height);
          // }

          // // 通过高度判断每页能放多少句子
          // final List<int> pageSentenceCount = [];
          // double pageHeight = 0;
          // int sentenceCount = 0;
          // for (final double textHeight in heightList) {
          //   pageHeight += textHeight;
          //   sentenceCount++;
          //   if (pageHeight > height) {
          //     pageSentenceCount.add(sentenceCount);
          //     pageHeight = 0;
          //     sentenceCount = 0;
          //   }
          // }

          // final List<Widget> pageViewList = [];

          // int pageStartIndex = 0;
          // for (final int sentenceCount in pageSentenceCount) {
          //   final List<String> pageContent = content.sublist(
          //     pageStartIndex,
          //     pageStartIndex + sentenceCount,
          //   );
          //   pageStartIndex += sentenceCount;
          //   pageViewList.add(
          //     ListView.builder(
          //       shrinkWrap: true,
          //       physics: const NeverScrollableScrollPhysics(),
          //       itemBuilder: (context, index) {
          //         return Text(
          //           pageContent[index],
          //           style: textStyle,
          //         );
          //       },
          //       itemCount: pageContent.length,
          //     ),
          //   );
          // }

          // return PageView(
          //   children: [
          //     //  如果大于 800 就是整体宽度的一半
          //     for (var i = 0;
          //         i < pageViewList.length;
          //         maxWidth > 800 ? i += 2 : i++)
          //       Row(
          //         crossAxisAlignment: CrossAxisAlignment.start,
          //         children: [
          //           Expanded(
          //             child: Container(
          //               child: pageViewList[i],
          //             ),
          //           ),
          //           if (maxWidth > 800)
          //             i + 1 < pageViewList.length
          //                 ? Expanded(
          //                     child: Container(
          //                       child: pageViewList[i + 1],
          //                     ),
          //                   )
          //                 : const Expanded(child: SizedBox()),
          //         ],
          //       )
          //   ],
          // );
        },
      ),
    );
  }

  Widget _buildAndroid(BuildContext context) {
    // "Llenar pantalla" también saca el SafeArea de arriba y de abajo (ver el
    // worker en NovelController, que además esconde las barras del sistema),
    // para que el texto use todo el alto. La barra del lector es un widget
    // aparte flotando por encima y se queda con su propio SafeArea.
    return Scaffold(
      body: Obx(
        () => SafeArea(
          top: !_c.llenarPantalla.value,
          bottom: !_c.llenarPantalla.value,
          child: _buildContent(),
        ),
      ),
    );
  }

  Widget _buildDesktop(BuildContext context) {
    return Container(
      color: fluent.FluentTheme.of(context).micaBackgroundColor,
      child: _buildContent(),
    );
  }

  // Escape cierra el lector, igual que el botón de atrás y que en el lector de
  // manga. Esta pantalla no tenía NINGÚN manejo de teclado propio, así que
  // hace falta el FocusNode con autofocus para que los eventos lleguen; el
  // scroll con flechas/rueda lo sigue manejando el Scrollable por defecto de
  // Flutter, que acá anda bien (a diferencia del lector de manga, donde había
  // un salto por página que se encadenaba).
  final _keyboardFocusNode = FocusNode();

  @override
  void dispose() {
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  void _onKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      RouterUtils.closeReader(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: _onKeyEvent,
      child: PlatformBuildWidget(
        androidBuilder: _buildAndroid,
        desktopBuilder: _buildDesktop,
      ),
    );
  }
}
