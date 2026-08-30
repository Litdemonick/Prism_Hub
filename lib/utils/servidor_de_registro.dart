import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:prismhub/utils/anuncio_de_registro.dart';
import 'package:prismhub/utils/encabezado_de_sesion.dart';
import 'package:prismhub/utils/exportar_registro.dart';
import 'package:prismhub/utils/log.dart';
import 'package:prismhub/utils/platform_tv.dart';

/// Deja leer el registro del televisor desde otro aparato de la misma red.
///
/// ── Para qué existe ─────────────────────────────────────────────────────────
///
/// En un televisor no hay dónde exportar un archivo ni con qué abrirlo, así
/// que el registro solo se puede mirar en la propia pantalla — con el mando,
/// línea por línea. Para un fallo de dos líneas alcanza; para un cierre que
/// hay que rastrear hacia atrás, no.
///
/// Con esto el televisor levanta un servidor chico en la red de casa y muestra
/// una dirección. Se escribe esa dirección en el navegador de cualquier PC o
/// teléfono y ahí está el registro entero: se puede buscar, copiar y pegar.
///
/// ── Por qué no SSH ──────────────────────────────────────────────────────────
///
/// Es lo primero que se piensa, y es la herramienta equivocada. Un servidor
/// SSH es acceso a una consola del aparato: mucha superficie para lo que hace
/// falta, que es leer un archivo de texto. Además pide claves y configuración
/// de los dos lados. Un servidor de solo lectura, con lo único que sirve y
/// nada más, hace el mismo trabajo sin abrir ninguna puerta.
///
/// ── Lo que lo hace seguro ───────────────────────────────────────────────────
///
///  - **Apagado de fábrica.** Se enciende a mano y solo para esa sesión.
///  - **Con un código al azar en la dirección.** Que alguien esté en el mismo
///    wifi no alcanza: hay que estar viendo la pantalla del televisor para
///    saber la dirección completa. Sin el código, el servidor contesta que no.
///  - **Se apaga solo a los tres cuartos de hora.** Nadie se lo olvida
///    encendido toda la tarde.
///  - **Solo lee el registro.** No hay ninguna otra ruta, y no escribe nada.
///  - **Y ese registro ya viene saneado** desde que se escribe: sin
///    credenciales, sin qué se estaba viendo y sin el nombre de usuario del
///    sistema. Ver [PrismLog.sanear].
class ServidorDeRegistro {
  ServidorDeRegistro._();

  static HttpServer? _servidor;
  static String? _codigo;
  static Timer? _apagado;

  /// Cuánto queda encendido si nadie lo apaga.
  ///
  /// Tres cuartos de hora. Empezó en quince minutos, pensando en «leer un
  /// registro y cerrar», y en el uso real resultó corto: esto se enciende para
  /// dejarlo puesto mientras se prueba algo —reproducir un episodio entero,
  /// recorrer varias extensiones— mirando el navegador en paralelo. Se cortaba
  /// a mitad de la prueba, y volver a levantarlo obliga a escribir otra
  /// dirección porque el código cambia cada vez.
  ///
  /// Sigue habiendo tope, y no es un detalle: es lo que garantiza que nadie
  /// se lo deje abierto sin darse cuenta.
  static const _cuantoDura = Duration(minutes: 45);

  /// La dirección para escribir en el otro aparato, o null si está apagado.
  static String? direccion;

  /// Qué área se está mirando en el televisor, para servir lo mismo.
  ///
  /// Lo pone el visor cuando se cambia de filtro. Null = todas. Si lo que se
  /// ve en la pantalla grande y lo que llega al navegador no coincidieran,
  /// habría que ir traduciendo mentalmente entre los dos, que es justo lo que
  /// esto viene a evitar.
  static String? areaElegida;

  static bool get encendido => _servidor != null;

  /// Qué se está sirviendo, dicho en palabras.
  ///
  /// ── Por qué hace falta escribirlo ───────────────────────────────────────
  ///
  /// La página decía «todo el registro» pasara lo que pasara, así que desde el
  /// navegador no había forma de saber si lo que se estaba mirando era lo que
  /// pasa ahora o una apertura anterior guardada — y las dos se ven igual, con
  /// las mismas líneas y el mismo aspecto.
  ///
  /// Reportado en vivo: «debe especificar cuándo es historial y en qué zona
  /// está». Va a la página Y al registro: quien lo enciende tiene que poder
  /// comprobar después, en el propio archivo, qué estuvo compartiendo.
  static String? queSeSirve;

  /// Las líneas concretas que hay que servir, o null para el registro entero.
  ///
  /// Lo pone el visor cuando lo que se está mirando es una sesión anterior:
  /// ahí lo que interesa no es lo que está pasando ahora, sino ese arranque
  /// en particular. Sin esto, el navegador mostraría algo distinto de lo que
  /// hay en la pantalla del televisor.
  static List<String>? lineasFijas;

  /// Lo enciende y dice qué pasó.
  ///
  /// Devuelve la dirección, o el motivo por el que no se pudo. Antes devolvía
  /// null a secas para las tres formas de fallar, así que la pantalla solo
  /// podía decir «no se pudo» — y quien lo lee no tiene con qué saber si le
  /// falta conectar el televisor a la red o si el problema es otro.
  ///
  /// Solo en televisor: en un teléfono o un PC ya se puede exportar el
  /// archivo, así que abrir un servidor sería sumar riesgo sin ganar nada.
  static Future<({String? direccion, FalloDeServidor? fallo})> encender() async {
    if (!PlatformTv.esTelevisionSync) {
      return (direccion: null, fallo: FalloDeServidor.noEsTelevisor);
    }
    if (_servidor != null) return (direccion: direccion, fallo: null);
    try {
      // El código se saca UNA vez por arranque de la app, no en cada
      // encendido.
      //
      // Antes cambiaba cada vez, así que apagar y volver a encender —o que se
      // apagara solo a los tres cuartos de hora— obligaba a escribir una
      // dirección nueva entera en el otro aparato. Y no aportaba: lo que
      // protege es que haya que estar viendo la pantalla del televisor para
      // conocerla, y eso vale igual con un código por sesión. Cuando la app se
      // cierra, se va con ella.
      _codigo ??= _codigoAlAzar();
      final s = await _escuchar();
      _servidor = s;
      s.listen(_atender, onError: (Object e) {
        logger.warning('servidor de registro: $e');
      });
      final ip = await _ipDeLaRed();
      if (ip == null) {
        await apagar();
        return (direccion: null, fallo: FalloDeServidor.sinRed);
      }
      // Sin «/r/» delante: eran dos caracteres más que teclear mirando una
      // pantalla a tres metros, y no separaban nada — no hay otra cosa
      // servida en este puerto.
      direccion = 'http://$ip:${s.port}/$_codigo';
      // Y se anuncia, para que el teléfono o el PC lo encuentren sin que
      // nadie tenga que escribir la dirección. Ver AnuncioDeRegistro.
      unawaited(AnuncioDeRegistro.anunciar(
        url: direccion!,
        aparato: EncabezadoDeSesion.resumenDelAparato(),
      ));
      _apagado = Timer(_cuantoDura, apagar);
      logger.info('Registro accesible desde la red durante '
          '${_cuantoDura.inMinutes} minutos · se comparte: $_loQueSeSirve');
      return (direccion: direccion, fallo: null);
    } catch (e) {
      logger.warning('No se pudo levantar el servidor de registro: $e');
      await apagar();
      return (direccion: null, fallo: FalloDeServidor.noSePudo);
    }
  }

  static Future<void> apagar() async {
    _apagado?.cancel();
    _apagado = null;
    unawaited(AnuncioDeRegistro.callar());
    final s = _servidor;
    _servidor = null;
    direccion = null;
    // El código NO se borra: es de la sesión de la app, no de este encendido.
    // Ver encender().
    lineasFijas = null;
    queSeSirve = null;
    areaElegida = null;
    if (s == null) return;
    try {
      await s.close(force: true);
      logger.info('Servidor de registro apagado: se deja de compartir');
    } catch (_) {
      // Ya estaba cerrado.
    }
  }

  /// El puerto que se intenta primero.
  ///
  /// ── Por qué uno fijo y no el que dé el sistema ──────────────────────────
  ///
  /// Empezó pidiendo el puerto 0 —«que lo elija el sistema»— para no chocar
  /// con nada. Eso está bien cuando la dirección se copia y se pega; acá se
  /// lee de una pantalla a tres metros y se escribe a mano en otro aparato, y
  /// cinco dígitos al azar (`:40365`) son la mitad de lo que hay que teclear.
  ///
  /// Con uno fijo, la dirección solo cambia en la parte que de verdad cambia.
  /// Y si estuviera ocupado no se pierde nada: se cae al de antes.
  ///
  /// 8787 y no algo como 8080: los puertos «bonitos» son los que ya tiene
  /// tomados cualquier otra cosa del aparato.
  static const _puertoPreferido = 8787;

  /// Abre el puerto de siempre, y si no se puede, cualquiera.
  static Future<HttpServer> _escuchar() async {
    try {
      return await HttpServer.bind(InternetAddress.anyIPv4, _puertoPreferido);
    } catch (_) {
      // Ocupado por otra app del televisor. Se sigue con uno al azar: la
      // dirección queda más larga, pero funciona igual.
      return HttpServer.bind(InternetAddress.anyIPv4, 0);
    }
  }

  /// Cuatro caracteres al azar. No es una contraseña —la protección de verdad es
  /// que hay que ver la pantalla— pero evita que alguien que sepa la IP entre
  /// probando la ruta.
  static String _codigoAlAzar() {
    // Sin las letras y números que se confunden leyendo de lejos: ni ele ni
    // uno, ni o ni cero. Escribir mal la dirección y ver un 404 sin saber por
    // qué es peor que tener que mirar la pantalla otra vez.
    const alfabeto = 'abcdefghijkmnpqrstuvwxyz23456789';
    final r = Random.secure();
    // Cuatro y no seis: un millón de combinaciones, en una red de casa, con
    // el servidor apagado casi todo el tiempo y solo lectura del otro lado.
    // La protección de verdad sigue siendo que hay que ver la pantalla; esto
    // es para que alguien que sepa la IP no entre probando la ruta.
    return List.generate(4, (_) => alfabeto[r.nextInt(alfabeto.length)]).join();
  }

  static Future<void> _atender(HttpRequest pedido) async {
    try {
      final esperado = _codigo;
      final ruta = pedido.uri.pathSegments;
      // Dos rutas válidas, las dos con el código: la página y el texto que la
      // página va a buscar cada pocos segundos. Cualquier otra cosa se
      // contesta igual —404 pelado— para no ir diciendo qué existe y qué no.
      final conCodigo =
          esperado != null && ruta.isNotEmpty && ruta[0] == esperado;
      final esLaPagina = conCodigo && ruta.length == 1;
      final esElTexto =
          conCodigo && ruta.length == 2 && ruta[1] == 'texto';
      if (!esLaPagina && !esElTexto) {
        pedido.response.statusCode = HttpStatus.notFound;
        await pedido.response.close();
        return;
      }
      final texto = await ExportarRegistro.armar(
        soloArea: areaElegida,
        lineas: lineasFijas,
      );
      // ── Se cuentan las líneas del REGISTRO, no las del documento ──────
      //
      // Contaba los saltos de línea del texto ya armado, o sea que sumaba
      // también los recuadros, los títulos de sección y los renglones en
      // blanco. Salían 582 arriba y 544 en el resumen de más abajo, en la
      // misma página: dos números distintos para lo mismo, y quien la abre no
      // tiene forma de saber cuál creer.
      final cuantas = ExportarRegistro.cuantasLineas;
      pedido.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType =
            esElTexto ? ContentType.text : ContentType.html
        // Nada de caché: se abre para ver lo último, no lo de hace un rato.
        ..headers.set(HttpHeaders.cacheControlHeader, 'no-store')
        ..write(esElTexto
            ? '$_loQueSeSirve · $cuantas líneas\n$texto'
            : _pagina(texto, cuantas));
      await pedido.response.close();
    } catch (e) {
      logger.info('servidor de registro: $e');
      try {
        pedido.response.statusCode = HttpStatus.internalServerError;
        await pedido.response.close();
      } catch (_) {}
    }
  }

  /// Qué se está sirviendo, en una línea, para la página y para el registro.
  ///
  /// Dos datos y no uno: DE DÓNDE salen las líneas —lo que está pasando ahora
  /// o una apertura guardada— y QUÉ ZONA de ellas. Sin el primero, una sesión
  /// anterior se lee como si fuera lo de ahora y se persigue un fallo que ya
  /// no está pasando.
  static String get _loQueSeSirve {
    final origen = queSeSirve ?? 'registro de ahora';
    final zona = areaElegida ?? 'todas las zonas';
    return '$origen · $zona';
  }

  /// La página que se ve en el navegador.
  ///
  /// Sencilla a propósito: texto monoespaciado sobre fondo oscuro, con un
  /// refresco cada cinco segundos. Nada de esto se sirve desde fuera —es un
  /// solo archivo, sin recursos— así que no hay nada más que traer.
  /// La página que se ve en el navegador.
  ///
  /// ── Por qué NO se recarga sola con `meta refresh` ───────────────────────
  ///
  /// Era una recarga del navegador cada cinco segundos, y eso tiene un fallo
  /// que aparece justo en el peor momento: **si la app del televisor se cae,
  /// la siguiente recarga no encuentra a nadie y el navegador reemplaza la
  /// página por su pantalla de error**. O sea que se pierde de vista
  /// exactamente lo que se estaba mirando para entender por qué se cayó.
  ///
  /// Reportado en vivo: «si el televisor crasheó no puedo ver los registros
  /// porque la página se cae».
  ///
  /// Ahora la página se carga una vez y va a buscar el texto por su cuenta. Si
  /// la búsqueda falla **no se toca lo que hay en pantalla**: se avisa arriba
  /// de que se cortó y a qué hora fue lo último que llegó, y se sigue
  /// intentando. Lo último que alcanzó a decir el televisor antes de caerse
  /// queda ahí, que es lo único que importa en ese momento.
  ///
  /// Y si la app vuelve, se retoma sola. Salvo que se haya reiniciado: ahí el
  /// código de la dirección es otro y hay que mirar la pantalla del televisor,
  /// cosa que el aviso también dice.
  static String _pagina(String registro, int cuantasLineas) {
    final escapado = const HtmlEscape().convert(registro);
    final aparato =
        const HtmlEscape().convert(EncabezadoDeSesion.resumenDelAparato());
    final queSirve = const HtmlEscape().convert(_loQueSeSirve);
    return '''<!doctype html>
<html lang="es"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Registro de PrismHub</title>
<style>
  body{background:#11131a;color:#c9ccd6;font:12px/1.5 ui-monospace,Consolas,monospace;margin:0;padding:16px}
  h1{color:#f0568d;font-size:15px;margin:0 0 4px}
  p{color:#7b8194;margin:0 0 16px;font-size:12px}
  p.que{color:#e8b339;margin:0 0 4px;font-size:13px;font-weight:600}
  pre{white-space:pre-wrap;word-break:break-word;margin:0}
  #corte{display:none;background:#3a1216;border:1px solid #e5484d;color:#ffb3b6;
         padding:10px 12px;border-radius:6px;margin:0 0 14px;font-size:12px}
  #corte b{color:#fff}
</style></head><body>
<h1>Registro de PrismHub</h1>
<div id="corte"></div>
<p class="que" id="que">$queSirve · $cuantasLineas líneas</p>
<p>$aparato · se actualiza solo cada 5 s</p>
<pre id="txt">$escapado</pre>
<script>
// Se guarda aparte lo ultimo que llego bien. Si el televisor se cae, esto
// sigue en pantalla: es justo lo que hace falta para saber por que se cayo.
var ultimaHora = new Date();
var cortado = false;
function dosCifras(n){ return (n < 10 ? '0' : '') + n; }
function hora(d){
  return dosCifras(d.getHours()) + ':' + dosCifras(d.getMinutes()) +
         ':' + dosCifras(d.getSeconds());
}
function avisarCorte(){
  if (cortado) return;
  cortado = true;
  var c = document.getElementById('corte');
  c.innerHTML = '<b>Se corto la conexion con el televisor.</b> ' +
    'Lo de abajo es lo ultimo que llego, a las ' + hora(ultimaHora) + '. ' +
    'Se sigue intentando: si la app vuelve, esto se actualiza solo. ' +
    'Si se reinicio, la direccion cambio y hay que mirarla en el televisor.';
  c.style.display = 'block';
  document.title = '(sin conexion) Registro de PrismHub';
}
function volvio(){
  if (!cortado) return;
  cortado = false;
  document.getElementById('corte').style.display = 'none';
  document.title = 'Registro de PrismHub';
}
function traer(){
  var x = new XMLHttpRequest();
  // Sin expresion regular a proposito: en Dart, el simbolo de dolar que lleva
  // una dentro se confunde con una interpolacion y hay que escaparlo, que es
  // como se rompen estas cosas al editarlas.
  var base = location.pathname;
  if (base.charAt(base.length - 1) === '/') {
    base = base.substring(0, base.length - 1);
  }
  x.open('GET', base + '/texto', true);
  x.timeout = 8000;
  x.onload = function(){
    if (x.status !== 200 || !x.responseText) { avisarCorte(); return; }
    var todo = x.responseText;
    var corte = todo.indexOf('\n');
    document.getElementById('que').textContent =
      corte < 0 ? '' : todo.substring(0, corte);
    document.getElementById('txt').textContent =
      corte < 0 ? todo : todo.substring(corte + 1);
    ultimaHora = new Date();
    volvio();
  };
  x.onerror = avisarCorte;
  x.ontimeout = avisarCorte;
  try { x.send(); } catch (e) { avisarCorte(); }
}
setInterval(traer, 5000);
</script>
</body></html>''';
  }

  /// La dirección de este aparato en la red de casa.
  static Future<String?> _ipDeLaRed() async {
    final candidatas = await _todasLasDeCasa();
    if (candidatas.isEmpty) return null;
    // ── Se prefiere 192.168.x.x ─────────────────────────────────────────
    //
    // Antes se tomaba la primera que apareciera, sin mirar cuál era. En un
    // televisor con cable Y wifi hay dos —visto en vivo: eth0 192.168.50.183 y
    // wlan0 192.168.50.236— y si la elegida no es la que el PC puede alcanzar,
    // la dirección no abre y no hay forma de saber por qué.
    //
    // 192.168 es el rango que reparten prácticamente todos los routers de
    // casa, así que ante la duda es la que más probabilidades tiene de ser la
    // buena. Las otras dos —10.x y 172.16-31— suelen ser de redes virtuales,
    // VPN o del propio sistema.
    final elegida = candidatas.firstWhere(
      (a) => a.startsWith('192.168.'),
      orElse: () => candidatas.first,
    );
    // Y se anotan TODAS, no solo la elegida: si la que se muestra no abre, en
    // el registro está la otra para probar sin adivinar.
    if (candidatas.length > 1) {
      logger.info('Direcciones de red del aparato: ${candidatas.join(", ")} '
          '· se publica $elegida');
    }
    return elegida;
  }

  /// Las direcciones privadas del aparato, en el orden en que las da el
  /// sistema.
  ///
  /// Solo redes privadas: si lo único que hay es una dirección pública, esto
  /// no es una red de casa y no corresponde publicar nada en ella.
  static Future<List<String>> _todasLasDeCasa() async {
    final salida = <String>[];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
      for (final iface in interfaces) {
        for (final dir in iface.addresses) {
          final a = dir.address;
          if (a.startsWith('192.168.') ||
              a.startsWith('10.') ||
              RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(a)) {
            salida.add(a);
          }
        }
      }
    } catch (_) {
      // Sin permiso de red o sin interfaces: se avisa arriba.
    }
    return salida;
  }
}

/// Por qué no se pudo encender el servidor.
///
/// Cada uno lleva a un mensaje distinto en pantalla, porque llevan a arreglos
/// distintos: uno se soluciona conectando el televisor a la red y los otros
/// no se solucionan desde ahí.
enum FalloDeServidor {
  /// No es un televisor. No debería llegar acá: el botón no existe fuera de
  /// televisor. Está por si algún día se llama desde otro lado.
  noEsTelevisor,

  /// El aparato no está en ninguna red de casa. Es el caso realista: un
  /// televisor sin wifi ni cable conectado.
  sinRed,

  /// El sistema no dejó abrir el puerto. Algunos televisores con la app en
  /// segundo plano, o con políticas del fabricante, lo bloquean.
  noSePudo,
}
