// Que la marca de selección siga a la opción, no a la posición.
//
// Reportado en vivo con foto en un televisor: tres botones de la columna
// encendidos al mismo tiempo. Con tres luces puestas no se sabe cuál se va a
// activar al pulsar, y el mando parece que «cuesta» aunque esté respondiendo
// perfectamente.
//
// Es la clase de fallo que no se ve leyendo el código —cada tarjeta por
// separado hace lo correcto— sino solo cuando se las mira juntas mientras la
// lista cambia debajo. Por eso se comprueba acá.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prismhub/views/widgets/tv/focusable_card.dart';

/// Una columna con una opción que aparece y desaparece en el medio.
///
/// Es exactamente la forma de la columna del televisor: «volver al final» solo
/// está cuando la vista se fue del fondo, y las acciones que le siguen se
/// corren un lugar cada vez que eso cambia.
class _Columna extends StatefulWidget {
  const _Columna();

  @override
  State<_Columna> createState() => _ColumnaState();
}

class _ColumnaState extends State<_Columna> {
  /// Si la opción del medio está puesta.
  bool conLaDelMedio = false;

  final focos = {
    for (final n in ['arriba', 'medio', 'abajo', 'ultima'])
      n: FocusNode(debugLabel: n),
  };

  @override
  void dispose() {
    for (final f in focos.values) {
      f.dispose();
    }
    super.dispose();
  }

  /// Con `builder` y no con `child`: así la prueba lee el MISMO estado que
  /// enciende el resplandor, por la vía pública del widget, en vez de hurgar
  /// en cómo está pintado por dentro.
  Widget _opcion(String nombre) => FocusableCard(
        key: ValueKey(nombre),
        focusNode: focos[nombre],
        onTap: () {},
        builder: (tieneFoco) => SizedBox(
          width: 120,
          height: 40,
          child: Text(tieneFoco ? '$nombre:marcada' : '$nombre:apagada'),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            _opcion('arriba'),
            if (conLaDelMedio) _opcion('medio'),
            _opcion('abajo'),
            _opcion('ultima'),
            TextButton(
              onPressed: () =>
                  setState(() => conLaDelMedio = !conLaDelMedio),
              child: const Text('cambiar'),
            ),
          ],
        ),
      ),
    );
  }
}

List<String> _marcadas(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .where((t) => t.endsWith(':marcada'))
    .map((t) => t.split(':').first)
    .toList();

void main() {
  testWidgets('solo una opción queda marcada cuando la lista cambia debajo',
      (tester) async {
    await tester.pumpWidget(const _Columna());
    final estado = tester.state<_ColumnaState>(find.byType(_Columna));

    // El foco está en la última, que es la que más se corre de lugar cuando
    // aparece una opción por encima.
    estado.focos['ultima']!.requestFocus();
    await tester.pumpAndSettle();
    expect(_marcadas(tester), ['ultima']);

    // Aparece la del medio: todo lo de abajo se corre un lugar.
    await tester.tap(find.text('cambiar'));
    await tester.pumpAndSettle();
    expect(
      _marcadas(tester),
      ['ultima'],
      reason: 'la marca se quedó en la posición en vez de seguir a la opción',
    );

    // Y desaparece otra vez.
    await tester.tap(find.text('cambiar'));
    await tester.pumpAndSettle();
    expect(_marcadas(tester), ['ultima']);
  });

  testWidgets('soltar el foco apaga la marca', (tester) async {
    await tester.pumpWidget(const _Columna());
    final estado = tester.state<_ColumnaState>(find.byType(_Columna));

    estado.focos['abajo']!.requestFocus();
    await tester.pumpAndSettle();
    expect(_marcadas(tester), ['abajo']);

    estado.focos['abajo']!.unfocus();
    await tester.pumpAndSettle();
    expect(_marcadas(tester), isEmpty);
  });
}
