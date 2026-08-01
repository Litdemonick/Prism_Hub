import 'package:flutter/material.dart';
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
