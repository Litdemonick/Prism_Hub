import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  /// Arma el enlace de una ficha.
  ///
  /// Los valores van codificados: los identificadores traen barras, signos de
  /// interrogación y acentos según la extensión, y sin codificar cortarían el
  /// enlace a la mitad.
  static String enlaceDetalle({
    required String package,
    required String url,
    bool adulto = false,
  }) {
    final partes = <String>[
      'package=${Uri.encodeQueryComponent(package)}',
      'url=${Uri.encodeQueryComponent(url)}',
      // Solo cuando corresponde: así un enlace normal no arrastra un
      // parámetro que no significa nada.
      if (adulto) 'adult=1',
    ];
    return '$esquema://detail?${partes.join('&')}';
  }

  /// Lee un enlace recibido. Devuelve null si no es nuestro o si viene
  /// incompleto — un enlace roto no tiene que abrir una ficha vacía.
  static ({String package, String url, bool adulto})? leerEnlace(Uri uri) {
    if (uri.scheme != esquema) return null;
    // El "detail" puede llegar como host o como primer tramo de la ruta según
    // cómo lo normalice cada sistema: prismhub://detail?... y
    // prismhub:///detail?... son la misma cosa para el usuario.
    final destino = uri.host.isNotEmpty
        ? uri.host
        : (uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '');
    if (destino != 'detail') return null;

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
      if (!a.startsWith('$esquema:')) continue;
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

    try {
      manejar(await _canalAndroid.invokeMethod<String>('enlaceInicial'));
    } catch (_) {
      // Versión vieja de la actividad sin el canal: no es motivo para romper
      // el arranque, simplemente no hay enlace que abrir.
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
  static Future<void> compartirDetalle({
    required String titulo,
    required String package,
    required String url,
    bool adulto = false,
    Rect? origen,
  }) async {
    final enlace = enlaceDetalle(package: package, url: url, adulto: adulto);
    await Share.share(
      '$titulo\n\n$enlace',
      subject: titulo,
      sharePositionOrigin: origen,
    );
  }
}
