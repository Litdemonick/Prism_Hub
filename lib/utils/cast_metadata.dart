import 'dart:convert';

import 'package:dlna_dart/dlna.dart';

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
}) {
  final tipo = mime ?? mimeDeUrl(url);
  // DLNA.ORG_OP=01 avisa que se puede adelantar por bytes (el relay ahora
  // conserva el content-length, así que es cierto); DLNA.ORG_CI=0 que el vídeo
  // va tal cual, sin reconvertir.
  final protocolo = 'http-get:*:$tipo:DLNA.ORG_OP=01;DLNA.ORG_CI=0';
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

  return device.request('SetAVTransportURI', utf8.encode(sobre));
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
    // Un aparato que no la soporta contesta con un cuerpo de fallo SOAP.
    return !respuesta.contains('Fault') && !respuesta.contains('errorCode');
  } catch (_) {
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
