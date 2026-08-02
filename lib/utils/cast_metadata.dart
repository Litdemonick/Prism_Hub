import 'dart:convert';

import 'package:dlna_dart/dlna.dart';
import 'package:prismhub/utils/cast_log.dart';

// Le pasa el vídeo al aparato con una ficha DIDL-Lite COMPLETA.
//
// El setUrl() que trae dlna_dart arma la ficha con este `<res>`:
//
//     <res resolution="4"></res>
//
// o sea sin `protocolInfo` y sin la dirección adentro. Kodi parte ese campo
// por ":" esperando algo como `http-get:*:video/mp4:*`, no encuentra nada, y
// deja en su registro `invalid protocol info ':::'` — confirmado en el log del
// usuario. Sin ese dato el receptor no sabe qué formato le está llegando y
// tiene que adivinar el demuxer, que es de donde sale el "no se pudo
// reproducir uno o más elementos".
//
// Como `request()` es público en DLNADevice, se manda el mismo SOAP que
// mandaría el paquete pero con la ficha bien armada, sin necesidad de forkearlo.
Future<void> castearConMetadata(
  DLNADevice device,
  String url, {
  required String titulo,
  String? mime,
  bool puedeSaltar = true,
}) async {
  final tipo = mime ?? mimeDeUrl(url);
  // DLNA.ORG_OP: si el aparato puede o no adelantar por bytes.
  //
  // Iba SIEMPRE en 01 ("sí se puede"), y con el vídeo reempaquetado a MPEG-TS
  // eso es mentira: ese flujo se arma sobre la marcha, no tiene largo, y por eso
  // el relay responde OP=00 y Accept-Ranges: none. O sea que le anunciábamos una
  // cosa y le servíamos la contraria.
  //
  // Medido en vivo con un televisor que usa ExoPlayer: creyendo que puede
  // reposicionarse por bytes, cuando se le llena el buffer cierra la conexión y
  // la vuelve a abrir para seguir desde donde iba. Como el flujo no admite eso,
  // le llega otra vez desde el principio y el capítulo se REINICIA. En el
  // registro se ve como pedidos nuevos cada pocos segundos ("VOLVIÓ a pedir el
  // vídeo tras 8.3 MiB… 16.6 MiB… 33.3 MiB").
  //
  // Diciéndole la verdad desde el anuncio, el receptor sabe que esta fuente se
  // consume de una sola pasada y no intenta un reposicionamiento que no existe.
  final salto = puedeSaltar ? '01' : '00';
  final protocolo = 'http-get:*:$tipo:DLNA.ORG_OP=$salto;DLNA.ORG_CI=0';
  final urlXml = _escapar(url);

  final ficha = '<DIDL-Lite '
      'xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" '
      'xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" '
      'xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<item id="0" parentID="-1" restricted="1">'
      '<dc:title>${_escapar(titulo.isEmpty ? 'Vídeo' : titulo)}</dc:title>'
      '<upnp:class>object.item.videoItem</upnp:class>'
      '<res protocolInfo="${_escapar(protocolo)}">$urlXml</res>'
      '</item>'
      '</DIDL-Lite>';

  final sobre = '<?xml version="1.0" encoding="utf-8" standalone="yes"?>'
      '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
      's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
      '<s:Body>'
      '<u:SetAVTransportURI '
      'xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">'
      '<InstanceID>0</InstanceID>'
      '<CurrentURI>$urlXml</CurrentURI>'
      // La ficha viaja escapada DOS veces: una como XML dentro del sobre SOAP
      // (esto), y la de adentro ya la hizo cada campo por su cuenta.
      '<CurrentURIMetaData>${_escapar(ficha)}</CurrentURIMetaData>'
      '</u:SetAVTransportURI>'
      '</s:Body>'
      '</s:Envelope>';

  // El protocolInfo tal cual va en la ficha: es lo que el aparato usa para
  // decidir si puede con el vídeo, y declararlo mal es peor que no declararlo.
  // El título NO se registra a propósito (ver CastLog).
  CastLog.paso('SetAVTransportURI → protocolInfo="$protocolo", '
      '${CastLog.donde(url)}');
  final respuesta = await device.request('SetAVTransportURI', utf8.encode(sobre));
  // Un aparato que rechaza la orden contesta un cuerpo SOAP de fallo con código
  // 500, así que sin mirarlo todos los rechazos se veían igual que un éxito.
  CastLog.paso('SetAVTransportURI ← ${CastLog.respuestaUpnp(respuesta)}');
}

/// Pone a reproducir a una velocidad distinta de la normal.
///
/// El play() del paquete manda `<Speed>1</Speed>` fijo, así que no hay forma de
/// pedir x2 o x4 con él. Se manda el mismo SOAP con la velocidad pedida.
///
/// OJO: muchos aparatos solo aceptan la velocidad 1 y contestan un error de
/// SOAP. Devuelve si lo aceptó, para poder avisar en vez de dejar al usuario
/// pensando que anda.
Future<bool> reproducirAVelocidad(DLNADevice device, int velocidad) async {
  final sobre = '<?xml version="1.0" encoding="utf-8" standalone="yes"?>'
      '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
      's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
      '<s:Body>'
      '<u:Play xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">'
      '<InstanceID>0</InstanceID>'
      '<Speed>$velocidad</Speed>'
      '</u:Play>'
      '</s:Body>'
      '</s:Envelope>';
  try {
    final respuesta = await device.request('Play', utf8.encode(sobre));
    CastLog.paso(
        'Play (x$velocidad) ← ${CastLog.respuestaUpnp(respuesta)}');
    // Un aparato que no la soporta contesta con un cuerpo de fallo SOAP.
    return !respuesta.contains('Fault') && !respuesta.contains('errorCode');
  } catch (e) {
    CastLog.fallo('Play (x$velocidad) no obtuvo respuesta', e);
    return false;
  }
}

String _escapar(String texto) => texto
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

// La dirección del relay no lleva extensión (termina en /relay/<token>), así
// que ahí se cae en video/mp4: es lo que sirven casi todas las fuentes y es lo
// que cualquier receptor entiende. Vale como pista, no como promesa — el
// receptor igual mira el content-type real que le devuelve el relay.
/// Se expone porque quien castea pasa la dirección ORIGINAL de la fuente, no
/// la del relay (ver el uso en connectDLNADevice).
String mimeDeUrl(String url) {
  final limpia = url.split('?').first.toLowerCase();
  if (limpia.endsWith('.m3u8')) return 'application/vnd.apple.mpegurl';
  if (limpia.endsWith('.mkv')) return 'video/x-matroska';
  if (limpia.endsWith('.webm')) return 'video/webm';
  if (limpia.endsWith('.avi')) return 'video/x-msvideo';
  if (limpia.endsWith('.mov')) return 'video/quicktime';
  if (limpia.endsWith('.ts')) return 'video/mp2t';
  return 'video/mp4';
}
