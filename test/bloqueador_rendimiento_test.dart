import 'package:flutter_test/flutter_test.dart';
import 'package:prismhub/utils/bloqueador_anuncios.dart';

/// Guardias contra el fallo que dejó Android inservible el 2026-08-06.
///
/// El bloqueador tenía DOS caminos que crecían con la cantidad de dominios, y
/// con las listas de fábrica puestas (326.685) los dos se volvían impagables en
/// el teléfono. En la computadora no se notaba, así que desde afuera parecía que
/// fallaban las extensiones.
///
/// No se prueba "que sea rápido" con un reloj —eso da falsos fallos en una
/// máquina cargada—, sino **que no vuelva a aparecer la forma que era lenta**.

void main() {
  group('el bloqueo nativo del WebView tiene que quedar apagado', () {
    test('no se construye ninguna regla, en ninguna plataforma', () {
      // Era la única pieza que existía solo en Android, y esa asimetría rompía
      // Mega en el teléfono: aislado por el usuario el 2026-08-06, con el
      // bloqueador apagado Mega anda y con él encendido no, mientras en Windows
      // —donde esto nunca se construyó— anda con todo puesto.
      //
      // Si alguien lo reactiva, esta prueba lo agarra. El camino para volver a
      // bloquear en el motor es shouldInterceptRequest consultando bloquea(),
      // no esto. Ver reglasNativas en bloqueador_anuncios.dart.
      expect(BloqueadorAnuncios.reglasNativas(), isEmpty);
    });
  });

  group('el guion inyectado no puede recorrer la lista entera', () {
    test('usa un conjunto y pregunta por los dominios padre', () {
      final guion = BloqueadorAnuncios.guionPara(['anuncios.com', 'rastreo.net']);
      expect(guion, isNotEmpty);

      expect(guion, contains('new Set('),
          reason: 'los dominios van en un conjunto: recorrerlos uno por uno '
              'costaba 6,79 ms por pedido con la mitad de las listas puestas');
      expect(guion, contains('dominios.has('),
          reason: 'la consulta tiene que ser al conjunto');

      // La forma vieja, la que dejaba el teléfono muerto. Que no vuelva.
      expect(guion.contains("h.endsWith('.' + dominios["), isFalse,
          reason: 'ese era el barrido lineal sobre la lista entera');
      expect(guion.contains('dominios.length'), isFalse,
          reason: 'un conjunto no tiene length: si esto aparece, volvió a ser '
              'una lista');
    });

    test('sin dominios no se inyecta nada', () {
      expect(BloqueadorAnuncios.guionPara(const []), isEmpty);
    });

    test('los dominios viajan tal cual al guion', () {
      final guion = BloqueadorAnuncios.guionPara(['anuncios.com', 'rastreo.net']);
      expect(guion, contains('"anuncios.com"'));
      expect(guion, contains('"rastreo.net"'));
    });
  });
}
