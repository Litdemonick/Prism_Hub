import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:prismhub/views/widgets/watch/burbujas_continuar_leyendo.dart';
import 'package:prismhub/views/widgets/watch/control_panel_footer.dart';
import 'package:prismhub/views/widgets/watch/control_panel_header.dart';
import 'package:prismhub/controllers/watch/reader_controller.dart';

class ReaderView<T extends ReaderController> extends StatelessWidget {
  const ReaderView(
    this.tag, {
    super.key,
    required this.content,
    this.buildSettings,
    this.buildFooter,
  });
  final String tag;
  final Widget content;
  final Widget Function(BuildContext context)? buildSettings;
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
              if (event.position.dy > MediaQuery.sizeOf(context).height - 60) {
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
              // Leave the system scrollbar's hit strip free on desktop —
              // this overlay is translucent, so its tap recognizer competes
              // in the same gesture arena as the scrollbar's own drag
              // recognizer for any click/drag over it, causing the
              // scrollbar to jump erratically instead of dragging smoothly.
              // 24 y no 20: la barra del lector se ensanchó a 16px y su franja
              // de agarre es ancho+6 = 22 (ver _cascadeScrollbarWidth /
              // scrollbarStrip en comic_reader_content.dart). Con 20 los
              // últimos 2px de la franja volvían a quedar bajo esta capa.
              right: Platform.isAndroid ? 0 : 24,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  // On Android the left/right zones just toggle the panel;
                  // page navigation is handled by the comic's own controls.
                  if (Platform.isAndroid) {
                    c.isShowControlPanel.value = !c.isShowControlPanel.value;
                    return;
                  }
                  // Desktop: left third → prev, right third → next, center → panel.
                  // Using a separate callback instead of relying on the tap
                  // position from onTapDown to avoid frame-delay issues.
                },
                onTapUp: Platform.isAndroid
                    ? null
                    : (details) {
                        if (!c.clickPagingEnabled) {
                          c.isShowControlPanel.value =
                              !c.isShowControlPanel.value;
                          return;
                        }
                        // Franja angosta en cada borde, NO un tercio de la
                        // pantalla: la zona de paginado tiene que coincidir
                        // con las flechas que se ven (64px, ver _PageArrow en
                        // comic_reader_content.dart). Con tercios, un clic
                        // sobre el manga mismo cambiaba de página sin querer
                        // — a pedido explícito, solo pagina la zona de las
                        // flechas. Un poco más ancha que el ícono para que
                        // sea cómoda de acertar.
                        const edge = 80.0;
                        final xPos = details.globalPosition.dx;
                        final width = MediaQuery.sizeOf(context).width;
                        if (xPos < edge) {
                          c.previousPage();
                        } else if (xPos > width - edge) {
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
            //
            // Las burbujas van ARRIBA del footer, las dos dentro del MISMO
            // Positioned/Column — puestas cada una en su propio Positioned
            // pegado a bottom:0 se dibujan una ENCIMA de la otra, ya que
            // ninguna sabe cuánto mide la de al lado. En una Column, la
            // fila de burbujas (que puede no mostrar nada, ver
            // BurbujasContinuarLeyendo) empuja al footer hacia arriba solo
            // cuando de verdad ocupa espacio.
            //
            // `_MedidorDeAltura` mide el alto REAL que termina ocupando
            // toda esta franja y lo guarda en `c.alturaPanelInferior` — lo
            // usa `_PieDeCapituloCascada` (comic_reader_content.dart) para
            // no tapar sus propios botones con esto, sin depender de un
            // número adivinado a mano (ver el comentario largo en
            // ReaderController.alturaPanelInferior).
            Positioned(
              right: 0,
              left: 0,
              bottom: 0,
              child: _MedidorDeAltura(
                onAltura: (alto) => c.alturaPanelInferior.value = alto,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    BurbujasContinuarLeyendo(
                      packageActual: c.runtime.extension.package,
                      urlActual: c.detailUrl,
                      isNsfw: c.isNsfw,
                      colapsado: c.burbujasColapsadas.value,
                      onToggleColapsado: () => c.burbujasColapsadas.value =
                          !c.burbujasColapsadas.value,
                      onTocar: (h) => c.saltarABurbuja(context, h),
                      onPreview: (h) => c.burbujaExpandida.value = h,
                    ),
                    buildFooter != null
                        ? buildFooter!(context)
                        : ControlPanelFooter<T>(tag),
                  ],
                ),
              ),
            ),
          ],

          // La vista agrandada de una burbuja (mantener presionado) vive
          // FUERA del `if` de arriba a propósito: si el panel de controles
          // se auto-oculta a los 3s (ReaderController.showControlPanel)
          // mientras el usuario todavía está mirándola para decidir, no
          // tiene que desaparecer con él. Se centra contra este Stack
          // entero (el lector completo), no contra la franja de abajo —
          // pedido explícito, antes quedaba corrida "hacia un lado" porque
          // solo tenía la franja angosta para centrarse.
          if (c.burbujaExpandida.value != null)
            BurbujaExpandidaOverlay(
              historia: c.burbujaExpandida.value!,
              diametroFila: diametroDeBurbuja(Platform.isAndroid),
              onConfirmar: () =>
                  c.saltarABurbuja(context, c.burbujaExpandida.value!),
              onCancelar: () => c.burbujaExpandida.value = null,
            ),
        ],
      ),
    );
  }
}

/// Mide el alto real que termina ocupando [child] después de cada layout y
/// lo avisa por [onAltura] — solo cuando cambió de verdad, para no disparar
/// el callback en cada frame sin necesidad.
class _MedidorDeAltura extends StatefulWidget {
  const _MedidorDeAltura({required this.onAltura, required this.child});

  final ValueChanged<double> onAltura;
  final Widget child;

  @override
  State<_MedidorDeAltura> createState() => _MedidorDeAlturaState();
}

class _MedidorDeAlturaState extends State<_MedidorDeAltura> {
  double? _ultima;

  void _medir(Duration _) {
    if (!mounted) return;
    final caja = context.findRenderObject() as RenderBox?;
    if (caja == null || !caja.hasSize) return;
    final alto = caja.size.height;
    if (_ultima != null && (alto - _ultima!).abs() < 0.5) return;
    _ultima = alto;
    widget.onAltura(alto);
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback(_medir);
    return widget.child;
  }
}
