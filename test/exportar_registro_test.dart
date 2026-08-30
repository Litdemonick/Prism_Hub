// Que el archivo exportado se pueda identificar sin abrirlo.
//
// Salían todos con el mismo nombre, así que dos exportados en la misma
// carpeta ya eran «reporte» y «reporte(1)»: ni la zona ni la fecha. Quien lo
// recibe tampoco tenía cómo saber qué le mandaron.

import 'package:flutter_test/flutter_test.dart';
import 'package:prismhub/utils/exportar_registro.dart';

void main() {
  test('lleva la zona adelante', () {
    expect(ExportarRegistro.nombreDeArchivo('fallos'), startsWith('PrismHub-fallos-'));
    expect(
      ExportarRegistro.nombreDeArchivo('historial-todo'),
      startsWith('PrismHub-historial-todo-'),
    );
  });

  test('la fecha va del año al minuto, para que ordene por tiempo', () {
    // Ordenados por nombre tienen que quedar también en orden de tiempo, que
    // es como se los busca al recibir varios.
    final nombre = ExportarRegistro.nombreDeArchivo('todo');
    expect(
      nombre,
      matches(RegExp(r'^PrismHub-todo-\d{4}-\d{2}-\d{2}-\d{4}\.log$')),
    );
  });

  test('siempre termina en .log', () {
    for (final z in ['todo', 'fallos', 'extensiones', 'reproductor']) {
      expect(ExportarRegistro.nombreDeArchivo(z), endsWith('.log'));
    }
  });
}
