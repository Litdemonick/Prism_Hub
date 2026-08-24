// Prueba en aislamiento del sistema de foco para TV (FocusableCard), antes
// de usarlo en cualquier pantalla real. Confirma que D-pad (flechas +
// select/enter), mouse (hover + click) y toque producen la misma señal
// visual y el mismo onTap — y que la navegación direccional entre tarjetas
// funciona con lo que ya trae Flutter, sin FocusTraversalGroup a mano.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prismhub/views/widgets/tv/focusable_card.dart';

Widget _tarjeta(String label) => Container(
      width: 100,
      height: 100,
      color: Colors.blueGrey,
      alignment: Alignment.center,
      child: Text(label),
    );

/// Si el marco de "esto está seleccionado" se está viendo.
///
/// El marco vive en su propia capa encima de la tarjeta (ver FocusableCard:
/// puesto alrededor achicaba al hijo y temblaba), así que lo que cambia al
/// enfocar es su OPACIDAD, no el color del borde.
bool _marcoVisible(WidgetTester tester) {
  final capa = tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
  return capa.opacity > 0;
}

void main() {
  testWidgets('el tap dispara onTap y le pide el foco a la tarjeta',
      (tester) async {
    var toques = 0;
    final nodo = FocusNode(debugLabel: 'A');
    addTearDown(nodo.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FocusableCard(
          focusNode: nodo,
          onTap: () => toques++,
          child: _tarjeta('A'),
        ),
      ),
    ));

    expect(nodo.hasFocus, isFalse);
    await tester.tap(find.text('A'));
    await tester.pump();

    expect(toques, 1);
    expect(nodo.hasFocus, isTrue);
  });

  testWidgets('mouse (hover) y D-pad (foco) encienden la misma señal visual',
      (tester) async {
    final nodo = FocusNode(debugLabel: 'A');
    addTearDown(nodo.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FocusableCard(
          focusNode: nodo,
          onTap: () {},
          child: _tarjeta('A'),
        ),
      ),
    ));

    expect(_marcoVisible(tester), isFalse);

    // D-pad/teclado: FocusTraversalGroup termina pidiendo el foco así.
    nodo.requestFocus();
    await tester.pumpAndSettle();
    expect(_marcoVisible(tester), isTrue);

    nodo.unfocus();
    await tester.pumpAndSettle();
    expect(_marcoVisible(tester), isFalse);

    // Mouse: hover sin foco de teclado enciende la MISMA señal.
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(location: Offset.zero);
    await tester.pump();
    await gesture.moveTo(tester.getCenter(find.text('A')));
    await tester.pumpAndSettle();
    expect(_marcoVisible(tester), isTrue);
  });

  testWidgets('select/enter del mando confirma igual que un tap',
      (tester) async {
    var toques = 0;
    final nodo = FocusNode(debugLabel: 'A');
    addTearDown(nodo.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FocusableCard(
          focusNode: nodo,
          autofocus: true,
          onTap: () => toques++,
          child: _tarjeta('A'),
        ),
      ),
    ));
    await tester.pump();
    expect(nodo.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(toques, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(toques, 2);
  });

  testWidgets('las flechas del D-pad mueven el foco entre tarjetas de una fila',
      (tester) async {
    final nodoA = FocusNode(debugLabel: 'A');
    final nodoB = FocusNode(debugLabel: 'B');
    addTearDown(() {
      nodoA.dispose();
      nodoB.dispose();
    });
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FocusableCard(
              focusNode: nodoA,
              autofocus: true,
              onTap: () {},
              child: _tarjeta('A'),
            ),
            FocusableCard(
              focusNode: nodoB,
              onTap: () {},
              child: _tarjeta('B'),
            ),
          ],
        ),
      ),
    ));
    await tester.pump();
    expect(nodoA.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(nodoB.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(nodoA.hasFocus, isTrue);
  });
}
