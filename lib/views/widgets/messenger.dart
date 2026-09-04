import 'dart:async';
import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart' as material;
import 'package:flutter/widgets.dart';
import 'package:prismhub/utils/platform_tv.dart';
import 'package:window_manager/window_manager.dart' show DragToMoveArea;

showPlatformSnackbar({
  required BuildContext context,
  required String content,
  String title = '',
  dynamic action,
  fluent.InfoBarSeverity severity = fluent.InfoBarSeverity.info,
}) {
  if (Platform.isAndroid) {
    // ── Blindado: si no hay ScaffoldMessenger, no se pierde el aviso ──────
    //
    // `ScaffoldMessenger.of(context)` exige un ancestro en el árbol —
    // normalmente lo pone GetMaterialApp/MaterialApp, pero una pantalla
    // montada por su cuenta (una ruta empujada con su propio Navigator, un
    // diálogo con un contexto particular) puede quedar sin uno. Sin este
    // try/catch, esa excepción no llegaba a verse en una build de release:
    // el botón que la disparaba quedaba "mudo" — se apretaba y no pasaba
    // nada, sin ningún error visible que explicara por qué. Reportado en
    // vivo: «al darle ya actualicé no hace nada».
    //
    // El aviso de escritorio (`_avisoDeEscritorio`, más abajo) sirve de red:
    // solo necesita un `Overlay`, que existe desde que hay CUALQUIER
    // Navigator montado — muchísimo más difícil de no tener que un
    // ScaffoldMessenger.
    try {
      final messenger = material.ScaffoldMessenger.of(context);
      // Los SnackBar de Material se ENCOLAN: cada uno espera a que termine
      // el anterior. Instalar o actualizar varias extensiones disparaba un
      // mensaje por cada una y había que esperar la cola completa —cuatro
      // segundos por mensaje— viendo avisos de algo que ya había pasado. Se
      // descarta lo que esté en pantalla para que siempre se vea el
      // ÚLTIMO, que es el que importa.
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
    } catch (e) {
      return _avisoDeEscritorio(
        context: context,
        title: title,
        content: content,
        action: action,
        severity: severity,
      );
    }
  }
  return _avisoDeEscritorio(
    context: context,
    title: title,
    content: content,
    action: action,
    severity: severity,
  );
}

/// El aviso de escritorio que está en pantalla ahora, si hay alguno.
///
/// ── Por qué no se usa `displayInfoBar` ──────────────────────────────────────
///
/// Porque **no sabe que ya hay uno puesto**: cada llamada crea su propia capa
/// en la misma posición, así que dos avisos seguidos se dibujan UNO ENCIMA DEL
/// OTRO y no se lee ninguno de los dos. Se ve al activar o desactivar varias
/// extensiones, que es justo cuando más avisos salen (reportado en vivo).
///
/// Con la capa propia se puede sacar el anterior antes de poner el nuevo, que
/// es exactamente la misma regla que ya seguía Android con
/// `removeCurrentSnackBar`: **siempre se ve el ÚLTIMO**, que es el que importa.
OverlayEntry? _avisoActual;
Timer? _relojDelAviso;

void _sacarAviso() {
  _relojDelAviso?.cancel();
  _relojDelAviso = null;
  _avisoActual?.remove();
  _avisoActual = null;
}

Future<void> _avisoDeEscritorio({
  required BuildContext context,
  required String title,
  required String content,
  dynamic action,
  required fluent.InfoBarSeverity severity,
}) async {
  final capa = Overlay.maybeOf(context, rootOverlay: true);
  // Sin capa no hay dónde dibujarlo. Pasa en pantallas que todavía se están
  // montando; callarse es mejor que tumbar la pantalla por un aviso.
  if (capa == null) return;

  _sacarAviso();

  // Arriba y no abajo: abajo viven los controles, y en Extensiones instaladas
  // el aviso tapaba la paginación —«1/4 ‹ ›»— y no dejaba cambiar de página.
  final entrada = OverlayEntry(
    builder: (context) => Positioned(
      top: 16,
      left: 0,
      right: 0,
      child: Align(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: fluent.InfoBar(
            title: Text(title),
            content: Text(content),
            action: action,
            severity: severity,
            onClose: _sacarAviso,
          ),
        ),
      ),
    ),
  );

  _avisoActual = entrada;
  capa.insert(entrada);
  _relojDelAviso = Timer(const Duration(seconds: 3), () {
    // Solo si sigue siendo ESTE: si mientras tanto entró otro, el reloj viejo
    // no puede sacarle el suyo al nuevo.
    if (_avisoActual == entrada) _sacarAviso();
  });
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
        // En TV nada tiene foco al abrir un diálogo — no hay dedo que toque
        // el botón, así que sin esto el control remoto no mueve nada: el
        // diálogo queda ahí, sin forma de aceptarlo ni de cerrarlo.
        //
        // No hace falta elegir un botón a mano: se le pide al propio
        // recorrido de foco de Flutter que encuentre el primer widget
        // enfocable de VERDAD (los botones de `actions` ya lo son, son
        // FilledButton/TextButton) y lo enfoque — así el mando ya tiene
        // dónde empezar a moverse.
        //
        // Se pide SIEMPRE, no solo "si nadie lo tiene": la pantalla de
        // atrás sigue viva y puede pedirlo ella al reconstruirse (el
        // sidebar de la Home de TV lo hacía), y entonces el diálogo queda
        // adelante mientras las flechas mueven el fondo.
        if (PlatformTv.esTelevisionSync) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) return;
            final alcance = FocusScope.of(context);
            FocusTraversalGroup.of(context)
                .findFirstFocus(alcance, ignoreCurrentFocus: true)
                ?.requestFocus();
          });
        }
        return material.AlertDialog(
          scrollable: scrollable,
          title: Text(title),
          content: content,
          actions: actions,
          // A la izquierda en TV: a la derecha (lo de siempre) el foco
          // inicial cae lejos del título y del contenido, que se leen de
          // izquierda a derecha — obliga a cruzar toda la pantalla con el
          // mando antes de llegar al primer botón. Pegados al mismo borde
          // que el resto, el recorrido es corto y predecible.
          actionsAlignment: PlatformTv.esTelevisionSync
              ? material.MainAxisAlignment.start
              : null,
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
