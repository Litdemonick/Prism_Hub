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
  group('el bloqueo nativo del WebView', () {
    test('fuera de Android no se construye ninguna regla', () {
      // En Windows el valor nativo de la acción "bloquear" resuelve a null y
      // construir una sola regla tumba la pantalla entera. Esta prueba corre en
      // el escritorio, así que comprueba justo eso.
      expect(BloqueadorAnuncios.reglasNativas('https://unlimplay.com/f/1'),
          isEmpty);
    });

    test('Mega queda marcado para abrirse SIN bloqueo nativo', () {
      // Medido por el usuario el 2026-08-06: con el bloqueador encendido Mega
      // no carga en Android, y apagado sí. No es que las reglas coincidan con
      // algo suyo —se comprobó dirección por dirección— sino que estar puestas
      // obliga al motor a interceptar cada pedido.
      expect(BloqueadorAnuncios.sinBloqueoNativo('https://mega.nz/embed/abc'),
          isTrue);
      expect(
          BloqueadorAnuncios.sinBloqueoNativo('https://g.api.mega.co.nz/cs'),
          isTrue);
    });

    test('los demás servidores SÍ llevan bloqueo nativo', () {
      // El anuncio de vídeo entra por un `<script src>` ya escrito en el HTML,
      // y ahí el guion no llega: solo lo corta el motor. Visto en vivo en
      // unlimplay.com — «el guion está en la página · no cortó nada» y salió el
      // anuncio igual.
      for (final u in [
        'https://unlimplay.com/f/embed/tv/82452/1/1',
        'https://mixdrop.top/e/abc',
        'https://vimeos.net/embed-abc.html',
      ]) {
        expect(BloqueadorAnuncios.sinBloqueoNativo(u), isFalse, reason: u);
      }
    });

    test('el patrón nativo es chico y reconoce subdominios sin pasarse', () {
      // Con las listas del usuario adentro llegó a medir 6,9 MB y el motor
      // tardaba 574 ms por pedido. Solo va la base de fábrica.
      final patron = BloqueadorAnuncios.patronPara(['anuncios.com']);
      expect(patron, isNotNull);
      expect(patron!.length, lessThan(10 * 1024));
      final re = RegExp(patron, caseSensitive: false);
      expect(re.hasMatch('https://cdn.anuncios.com/x.js'), isTrue);
      expect(re.hasMatch('https://noanuncios.com/x.js'), isFalse,
          reason: 'no es subdominio: no puede caer');
      expect(re.hasMatch('https://anuncios.com.ar/x.js'), isFalse,
          reason: 'es otro dominio');
    });
  });

  group('el corte nativo de Windows', () {
    // Estas pruebas corren en el escritorio (Windows), que es justo donde este
    // camino tiene que estar encendido.
    test('se enciende para un servidor normal', () {
      // Es el agujero por el que entraba el anuncio de vídeo de Google IMA: en
      // Windows los contentBlockers llegan vacíos y el guion no puede parar un
      // <script src> que ya venía escrito en el HTML.
      expect(
        BloqueadorAnuncios.interceptableEnWindows(
            'https://unlimplay.com/f/embed/tv/82452/1/1'),
        isTrue,
      );
    });

    test('respeta la MISMA excepción que el bloqueo nativo de Android', () {
      // Interceptar cada pedido es exactamente lo que dejó a Mega sin cargar en
      // Android. No se puede repetir el error en Windows.
      expect(
        BloqueadorAnuncios.interceptableEnWindows('https://mega.nz/embed/abc'),
        isFalse,
      );
      expect(BloqueadorAnuncios.sinBloqueoNativo('https://mega.nz/embed/abc'),
          isTrue,
          reason: 'las dos vías tienen que mirar la misma lista');
    });

    test('los VAST del anuncio de vídeo caen, y los servidores NO', () {
      // Medido en la página de unlimplay, que publica su PREROLL_CONFIG en
      // texto plano. Bloquear solo imasdk no alcanzaba: el reproductor se trae
      // el manifiesto por su cuenta.
      for (final u in [
        'https://cvt-s2.agl003.com/v/abc.xml?cp.host=x',
        'https://latgw.fun/assets/vendor/abc.xml?v=3.0',
        'https://servetraff.com/ztcuDBsE3-abc',
      ]) {
        final host = Uri.parse(u).host.replaceFirst(RegExp(r'^www\.'), '');
        var cae = false;
        var actual = host;
        while (actual.contains('.')) {
          if (BloqueadorAnuncios.dominiosEnUso.contains(actual)) {
            cae = true;
            break;
          }
          actual = actual.substring(actual.indexOf('.') + 1);
        }
        expect(cae, isTrue, reason: 'el anuncio de vídeo entra por $u');
      }

      // La otra mitad, y la que importa más: estos estaban en la MISMA página
      // y son servidores o recursos legítimos. Bloquearlos deja al usuario sin
      // poder ver nada.
      for (final h in [
        'hglink.to', // streamwish
        'minochinos.com', // vidhide
        'voe.sx',
        'vidhidepro.com',
        'goodstream.one',
        'streamwish.to',
        'vimeos.net',
        'unlimplay.com',
        'flagcdn.com',
        'image.tmdb.org',
      ]) {
        expect(BloqueadorAnuncios.dominiosEnUso, isNot(contains(h)),
            reason: '$h no es un anuncio');
      }
    });

    test('la red de los carteles «18+» sobre el reproductor cae', () {
      // Medido pidiendo la página de voe: de todo lo externo que carga, solo
      // estos dos no eran legítimos. Los demás eran cdnjs, fonts de Google y
      // el propio voe.sx.
      for (final h in [
        'anthemoutbackwrought.com',
        'darnobedienceupscale.com',
      ]) {
        expect(BloqueadorAnuncios.dominiosEnUso, contains(h), reason: h);
      }
      // Y los que el propio registro del app dejó anotados como ventanas
      // emergentes: con el dominio en la lista, el guion ni se descarga.
      for (final h in [
        'luugy.com',
        'gigglemagnetismunaired.com',
        'effectivecpmnetwork.com',
        'nwirirni.in',
      ]) {
        expect(BloqueadorAnuncios.dominiosEnUso, contains(h), reason: h);
      }
      // Lo que la MISMA página de voe cargaba y no se puede tocar.
      for (final h in ['voe.sx', 'cdnjs.cloudflare.com', 'fonts.gstatic.com']) {
        expect(BloqueadorAnuncios.dominiosEnUso, isNot(contains(h)), reason: h);
      }
    });

    test('no tiene lista propia: usa la misma que el resto', () {
      // Una segunda lista se desincronizaría de la del guion y la del corte de
      // navegación. El interceptor pregunta por `bloquea`, que mira este mismo
      // conjunto.
      expect(BloqueadorAnuncios.dominiosEnUso, contains('imasdk.googleapis.com'),
          reason: 'el anuncio de vídeo entra por acá');
      expect(BloqueadorAnuncios.dominiosEnUso, isNot(contains('unlimplay.com')),
          reason: 'el propio servidor no se puede cortar');
    });
  });

  group('qué páginas no vale la pena dejar abiertas', () {
    test('un sub-recurso que falla NO cierra nada', () {
      // Con el bloqueador puesto esto pasa todo el tiempo: es un anuncio que
      // no cargó. Si cerrara la pantalla, el bloqueador rompería justo los
      // servidores que sí andan.
      expect(
        BloqueadorAnuncios.motivoParaNoSeguir(
          esMarcoPrincipal: false,
          errorDeCarga: 'ERR_BLOCKED_BY_CLIENT',
        ),
        isNull,
      );
      expect(
        BloqueadorAnuncios.motivoParaNoSeguir(
          esMarcoPrincipal: false,
          httpStatus: 404,
        ),
        isNull,
      );
    });

    test('el marco principal caído sí, y dice por qué', () {
      // El caso de SmartScreen con Doodstream en Windows: el guion no puede
      // ver ese muro y el bloqueo nativo tampoco, porque el pedido ni se hace.
      final porError = BloqueadorAnuncios.motivoParaNoSeguir(
        esMarcoPrincipal: true,
        errorDeCarga: 'ERR_BLOCKED_BY_ADMINISTRATOR',
      );
      expect(porError, isNotNull);
      expect(porError, contains('ERR_BLOCKED_BY_ADMINISTRATOR'));

      final porHttp = BloqueadorAnuncios.motivoParaNoSeguir(
        esMarcoPrincipal: true,
        httpStatus: 403,
      );
      expect(porHttp, isNotNull);
      expect(porHttp, contains('403'));
    });

    test('una página sana no se toca', () {
      expect(
        BloqueadorAnuncios.motivoParaNoSeguir(
          esMarcoPrincipal: true,
          httpStatus: 200,
        ),
        isNull,
      );
      expect(
        BloqueadorAnuncios.motivoParaNoSeguir(
          esMarcoPrincipal: true,
          errorDeCarga: '',
        ),
        isNull,
      );
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

    test('la ventana emergente se corta SIN devolver null', () {
      // Devolver null rompia la pagina entera: quien abre una ventana encadena
      // window.open(...).focus(), eso tira TypeError, y el error se lleva
      // puesto todo el resto del manejador del clic — incluido el del propio
      // reproductor. Se veia como botones que no responden (calidad e idioma
      // en el servidor Drive de FuegoCine, reportado en vivo).
      final guion = BloqueadorAnuncios.guionPara(['anuncios.com']);
      expect(guion.contains('window.open = function () { return null; }'), isFalse,
          reason: 'esa era la forma que rompia los botones del reproductor');
      expect(guion, contains('ventanaFalsa'),
          reason: 'se devuelve un objeto que se traga los encadenados');
      // Lo mínimo que se encadena en la práctica tiene que estar contemplado.
      for (final miembro in ['focus', 'close', 'document', 'location', 'postMessage']) {
        expect(guion, contains(miembro),
            reason: 'la ventana falsa tiene que aguantar .$miembro');
      }
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
