import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prismhub/models/extension.dart';
import 'package:share_plus/share_plus.dart';

/// Enlaces para compartir contenido, y cómo se vuelven a leer al abrirlos.
///
/// El enlace apunta al APP y no al sitio de origen. Podría parecer más simple
/// mandar la página del sitio, pero no sirve: cada extensión guarda la obra a
/// su manera. Eporner usa la url completa, Ikigai un slug suelto
/// ("la-creadora-de-escandalos-ha-regresado") y otras un identificador
/// numérico. No hay forma de armar una dirección web válida para todas.
///
/// Con un enlace propio se comparte lo único que sí es común: de qué extensión
/// viene y cuál es su identificador ahí adentro. El que lo recibe abre la misma
/// ficha, con su propia copia de la extensión.
class Compartir {
  Compartir._();

  /// El esquema tiene que coincidir con el declarado en cada plataforma:
  /// AndroidManifest.xml (intent-filter) y el instalador de Windows (registro).
  static const esquema = 'prismhub';

  /// Página puente del sitio del proyecto.
  ///
  /// Lo que se COMPARTE es una dirección https, no el `prismhub://` directo.
  /// WhatsApp y la mayoría de los chats convierten en enlace lo que empieza con
  /// http(s) pero NO los esquemas propios de una app: el enlace llegaba como
  /// texto plano que nadie podía tocar, justo lo contrario de para qué está el
  /// botón. La página salta sola a la app, y a quien no la tenga le queda una
  /// explicación con el enlace de descarga en vez de un error.
  static const _puente = 'https://litdemonick.github.io/Prism_Hub/abrir';

  /// Arma el enlace de una ficha.
  ///
  /// Los valores van codificados: los identificadores traen barras, signos de
  /// interrogación y acentos según la extensión, y sin codificar cortarían el
  /// enlace a la mitad.
  static String enlaceDetalle({
    required String package,
    required String url,
    bool adulto = false,
    String titulo = '',
    String portada = '',
  }) {
    final partes = <String>[
      'package=${Uri.encodeQueryComponent(package)}',
      'url=${Uri.encodeQueryComponent(url)}',
      // Solo cuando corresponde: así un enlace normal no arrastra un
      // parámetro que no significa nada.
      if (adulto) 'adult=1',
      // Para que la página puente pueda decir QUÉ se está abriendo. La app lo
      // ignora: el título real lo saca de la extensión.
      if (titulo.isNotEmpty) 't=${Uri.encodeQueryComponent(titulo)}',
      // La portada la muestra la página puente al abrirla. Nunca con contenido
      // para adultos: ahí la página se queda con el logo del app.
      if (!adulto && portada.isNotEmpty)
        'img=${Uri.encodeQueryComponent(portada)}',
    ];
    return '$_puente?${partes.join('&')}';
  }

  /// Lee un enlace recibido. Devuelve null si no es nuestro o si viene
  /// incompleto — un enlace roto no tiene que abrir una ficha vacía.
  static ({String package, String url, bool adulto})? leerEnlace(Uri uri) {
    // Se aceptan las DOS formas y no solo la propia:
    //
    //  - prismhub://detail?…  la que abre la app desde la página puente.
    //  - https://…/abrir?…    la que se comparte, por si el sistema se la pasa
    //    directo a la app (en Android, con el enlace verificado, entra así sin
    //    pasar por el navegador).
    //
    // Los parámetros son los mismos en las dos, así que de acá para abajo no
    // hay que distinguirlas.
    final esPropio = uri.scheme == esquema;
    final esPuente = (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.pathSegments.isNotEmpty &&
        uri.pathSegments.last == 'abrir';
    if (!esPropio && !esPuente) return null;

    if (esPropio) {
      // El "detail" puede llegar como host o como primer tramo de la ruta
      // según cómo lo normalice cada sistema: prismhub://detail?... y
      // prismhub:///detail?... son la misma cosa para el usuario.
      final destino = uri.host.isNotEmpty
          ? uri.host
          : (uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '');
      if (destino != 'detail') return null;
    }

    final package = uri.queryParameters['package'] ?? '';
    final url = uri.queryParameters['url'] ?? '';
    if (package.isEmpty || url.isEmpty) return null;

    return (
      package: package,
      url: url,
      adulto: uri.queryParameters['adult'] == '1',
    );
  }

  /// Enlace recibido que todavía no se pudo abrir.
  ///
  /// Se anota al arrancar y se consume cuando el árbol de widgets ya existe:
  /// navegar antes de eso no tiene a dónde ir. Se limpia al consumirlo para que
  /// no se vuelva a abrir la misma ficha si algo reconstruye la pantalla.
  static Uri? enlacePendiente;

  /// El enlace con el que arrancó la app, si arrancó por uno.
  ///
  /// En escritorio el sistema pasa la dirección como un argumento más del
  /// proceso: al abrir un `prismhub://…`, Windows ejecuta el programa
  /// registrado con esa dirección al final de la línea de comandos. Se recorren
  /// los argumentos en vez de mirar solo el primero porque el orden no está
  /// garantizado y pueden venir otros banderines por delante.
  ///
  /// Devuelve null si ninguno es un enlace nuestro, que es el caso normal.
  static Uri? enlaceDeArranque(List<String> args) {
    for (final a in args) {
      // Se prueba TODO argumento con pinta de direccion, no solo los del
      // esquema propio: en escritorio el sistema puede pasar el https del
      // puente si el navegador lo delega.
      if (!a.contains('://')) continue;
      final uri = Uri.tryParse(a);
      if (uri != null && leerEnlace(uri) != null) return uri;
    }
    return null;
  }

  /// Convierte un enlace recibido en la ruta interna del app.
  ///
  /// Es la MISMA ruta que usa la navegación normal, así que la ficha se abre
  /// por el camino de siempre: con su comprobación de extensión instalada, su
  /// bloqueo por actualización pendiente y su pregunta de +18. No hay una
  /// entrada paralela que se saltee esos pasos.
  static String? rutaInterna(Uri uri) {
    final datos = leerEnlace(uri);
    if (datos == null) return null;
    return '/detail?package=${Uri.encodeQueryComponent(datos.package)}'
        '&url=${Uri.encodeQueryComponent(datos.url)}'
        '${datos.adulto ? '&adult=1' : ''}';
  }

  /// Canal con la actividad de Android. Ver MainActivity.kt.
  static const _canalAndroid = MethodChannel('com.prismhub.app/enlaces');

  /// Empieza a atender los enlaces que llegan en Android.
  ///
  /// Hacen falta las dos vías y no alcanza con una:
  ///
  ///  - El enlace que ABRIÓ la app. La actividad lo guarda porque el intent
  ///    llega antes de que Dart esté listo para escuchar.
  ///  - Los que llegan con la app YA abierta. La actividad está declarada
  ///    singleTop, así que no se crea otra instancia y el intent entra por
  ///    onNewIntent; sin atender eso, compartir algo mientras PrismHub está
  ///    abierto no hacía nada.
  ///
  /// En escritorio no se usa: ahí el enlace viene en los argumentos del
  /// proceso (ver enlaceDeArranque).
  static Future<void> escucharAndroid(void Function(Uri) alRecibir) async {
    if (!Platform.isAndroid) return;

    void manejar(String? crudo) {
      if (crudo == null || crudo.isEmpty) return;
      final uri = Uri.tryParse(crudo);
      if (uri != null && leerEnlace(uri) != null) alRecibir(uri);
    }

    _canalAndroid.setMethodCallHandler((call) async {
      if (call.method == 'enlaceNuevo') manejar(call.arguments as String?);
      return null;
    });

    // Se pregunta VARIAS veces, no una.
    //
    // El canal lo crea la actividad al engancharse al motor de Flutter, y ese
    // motor ahora se comparte con el servicio de la notificación: puede estar
    // corriendo Dart antes de que la actividad llegue a registrar nada. En ese
    // hueco, preguntar una sola vez daba "no hay canal", el error se tragaba, y
    // abrir un enlace con la app cerrada la abría sin llevar a la ficha.
    //
    // Cinco intentos con un cuarto de segundo entre ellos: sobra para el
    // arranque más lento y se termina rápido cuando no hay ningún enlace, que
    // es el caso normal.
    for (var intento = 0; intento < 5; intento++) {
      try {
        final crudo = await _canalAndroid.invokeMethod<String>('enlaceInicial');
        // Contestó: haya enlace o no, ya no hace falta seguir preguntando.
        manejar(crudo);
        return;
      } catch (_) {
        // Todavía no está el canal. Se reintenta; si nunca aparece —una versión
        // vieja de la actividad, por ejemplo— simplemente no hay enlace que
        // abrir, y eso no puede romper el arranque.
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  /// Abre el menú de compartir del sistema con el título y el enlace.
  ///
  /// Va el título además del enlace porque el enlace es opaco: quien lo recibe
  /// vería solo "prismhub://detail?package=..." y no sabría de qué se trata.
  ///
  /// [origen] posiciona el menú en iPad y en escritorio, donde el sistema lo
  /// ancla a lo que se tocó en vez de mostrarlo centrado. Sin eso revienta en
  /// iPad y en escritorio aparece en una esquina cualquiera.
  /// Cómo se nombra lo que se comparte, según con qué se abre.
  ///
  /// El tipo es lo más fino que se puede saber sin volver a preguntarle al
  /// sitio: dice si esto se mira o se lee, no si es anime, película o manhwa.
  /// Se redacta con eso y no se inventa una precisión que no hay.
  static (String, String) _emojiYFrase(ExtensionType? tipo) {
    switch (tipo) {
      case ExtensionType.manga:
      case ExtensionType.mixedReading:
        return ('📖', 'Disfrutá esta lectura');
      case ExtensionType.fikushon:
        return ('📚', 'Disfrutá esta novela');
      default:
        return ('🍿', 'Disfrutá este vídeo');
    }
  }

  /// Devuelve true si terminó copiando al portapapeles en vez de abrir el menú
  /// del sistema, para que quien llama pueda avisarlo.
  static Future<bool> compartirDetalle({
    required String titulo,
    required String package,
    required String url,
    bool adulto = false,
    ExtensionType? tipo,
    String portada = '',
    Rect? origen,
  }) async {
    final enlace = enlaceDetalle(
      package: package,
      url: url,
      adulto: adulto,
      titulo: titulo,
      portada: portada,
    );

    // El mensaje es lo que va a leer la otra persona, así que se escribe como
    // un mensaje y no como un volcado de datos: qué es, por qué se lo mandan y
    // dónde tocar.
    //
    // Con contenido para adultos NO va ni el título ni la portada. Ese texto
    // puede quedar a la vista de cualquiera en una notificación o en la vista
    // previa del chat, y quien lo comparte no eligió eso.
    final String texto;
    if (adulto) {
      texto = '🔞 Te comparto algo en PrismHub\n\n'
          'Contenido para adultos: se abre solo con la Zona +18 activada.\n\n'
          '👉 $enlace';
    } else {
      final (emoji, frase) = _emojiYFrase(tipo);
      texto = [
        '✨ Mirá esto en PrismHub',
        '',
        if (titulo.isNotEmpty) '$emoji $titulo',
        frase,
        '',
        '👉 $enlace',
      ].join('\n');
    }

    // En escritorio no hay menú de compartir del sistema como en el teléfono:
    // Windows y Linux no exponen nada equivalente, así que el plugin no tiene
    // a quién pedírselo y el botón no hacía absolutamente nada. Copiar el
    // enlace es lo que se puede ofrecer ahí, y es lo que uno termina haciendo
    // igual para pegarlo en un chat.
    if (!Platform.isAndroid && !Platform.isIOS) {
      await Clipboard.setData(ClipboardData(text: texto));
      return true;
    }

    try {
      await Share.share(texto, subject: titulo, sharePositionOrigin: origen);
      return false;
    } catch (_) {
      // Sin ninguna app que sepa recibir el texto, o el plugin no disponible:
      // mejor dejar el enlace copiado que no hacer nada.
      await Clipboard.setData(ClipboardData(text: texto));
      return true;
    }
  }
}
