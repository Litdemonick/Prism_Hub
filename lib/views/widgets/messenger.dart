import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart' as material;
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart' show DragToMoveArea;

showPlatformSnackbar({
  required BuildContext context,
  required String content,
  String title = '',
  dynamic action,
  fluent.InfoBarSeverity severity = fluent.InfoBarSeverity.info,
}) {
  if (Platform.isAndroid) {
    final messenger = material.ScaffoldMessenger.of(context);
    // Los SnackBar de Material se ENCOLAN: cada uno espera a que termine el
    // anterior. Instalar o actualizar varias extensiones disparaba un mensaje
    // por cada una y había que esperar la cola completa —cuatro segundos por
    // mensaje— viendo avisos de algo que ya había pasado. Se descarta lo que
    // esté en pantalla para que siempre se vea el ÚLTIMO, que es el que
    // importa.
    messenger.removeCurrentSnackBar();
    return messenger.showSnackBar(
      material.SnackBar(
        content: Text("$title $content".trim()),
        action: action,
        // 4s por mensaje era mucho para un aviso de "listo".
        duration: const Duration(milliseconds: 2200),
        behavior: material.SnackBarBehavior.floating,
      ),
    );
  }
  // ── El aviso va ARRIBA, no abajo ────────────────────────────────────────
  //
  // `displayInfoBar` sale abajo al centro por defecto, y ahí es justo donde
  // viven los controles: en Extensiones instaladas tapaba la paginación
  // —«1/4 ‹ ›»— y no se podía cambiar de página mientras el aviso estuviera en
  // pantalla (reportado en vivo). Y como cada instalación dispara uno, se
  // encadenaban y el problema duraba.
  //
  // Arriba no tapa nada: esa franja es del título de la pantalla, que no se
  // toca.
  return fluent.displayInfoBar(
    context,
    alignment: fluent.Alignment.topCenter,
    builder: (context, close) {
      return fluent.InfoBar(
        title: Text(title),
        content: Text(content),
        action: action,
        severity: severity,
      );
    },
  );
}

showPlatformDialog({
  required BuildContext context,
  required String title,
  required Widget? content,
  required List<Widget>? actions,
  double? maxWidth,
  bool barrierDismissible = true,
  // Poner en false cuando el CONTENIDO ya trae su propia área desplazable (las
  // notas de versión, por ejemplo). Dos scrolls anidados se pelean el gesto: el
  // de adentro se lo queda y el de afuera no puede pasar de largo, así que el
  // final del contenido queda cortado.
  bool scrollable = true,
}) {
  if (Platform.isAndroid) {
    return material.showDialog(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (context) {
        return material.AlertDialog(
          scrollable: scrollable,
          title: Text(title),
          content: content,
          actions: actions,
        );
      },
    );
  }
  return fluent.showDialog(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (context) => fluent.ContentDialog(
      constraints: BoxConstraints(maxWidth: maxWidth ?? 368),
      // El título hace de barra de ventana.
      //
      // En escritorio la barra de título nativa está oculta
      // (TitleBarStyle.hidden en main.dart), así que la app se mueve
      // arrastrando sus propias zonas. Un diálogo modal tapa todas esas zonas:
      // mientras estaba abierto — el aviso de beta al arrancar es el caso
      // claro, que además no se puede cerrar tocando afuera — la ventana
      // quedaba clavada en su lugar y no había forma de correrla.
      //
      // Arrastrar por el título es lo que hace cualquier diálogo del sistema,
      // así que no hay nada nuevo que aprender.
      //
      // Ancho completo a propósito: envolviendo solo el Text, la zona
      // arrastrable terminaba donde terminan las letras, así que en un título
      // corto quedaba una franja de pocos píxeles.
      title: SizedBox(
        width: double.infinity,
        child: DragToMoveArea(child: Text(title)),
      ),
      content: content,
      actions: actions,
    ),
  );
}
