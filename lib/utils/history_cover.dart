import 'dart:io';

import 'package:prismhub/models/history.dart';
import 'package:prismhub/models/extension.dart';

/// Cómo hay que pintar la portada de un ítem del historial.
///
/// El historial de VÍDEO guarda como portada la captura del frame donde quedó
/// el usuario, que es una ruta de archivo LOCAL. Pero cuando todavía no hay
/// captura (recién abierto, o el frame no se pudo tomar) se cae al póster de
/// la obra, que es una URL de red. O sea que el mismo campo `cover` puede
/// traer las dos cosas y hay que mirarlo para saber cuál es.
///
/// Esta decisión estaba duplicada en home_page y nsfw18_zone_page, y FALTABA
/// en history_page: ahí se envolvía siempre en `File(...)`, así que un ítem de
/// vídeo con portada de red intentaba abrir un archivo llamado "https://..."
/// y la tarjeta quedaba sin imagen para siempre. Se veía como que el botón de
/// mostrar/ocultar imagen dejaba de funcionar, cuando en realidad la imagen
/// nunca había podido cargar.
class PortadaHistorial {
  const PortadaHistorial({this.url, this.archivo, required this.necesitaHeaders});

  /// Portada a bajar por red, o null si hay que usar [archivo].
  final String? url;

  /// Captura local, o null si hay que usar [url].
  final File? archivo;

  /// Las portadas de red de una extensión suelen pedir Referer/User-Agent;
  /// un archivo local, obviamente, no.
  final bool necesitaHeaders;

  static bool esRemota(String? cover) {
    if (cover == null || cover.isEmpty) return false;
    final normalizada = cover.toLowerCase();
    return normalizada.startsWith('http://') ||
        normalizada.startsWith('https://');
  }

  factory PortadaHistorial.de(History h) {
    final esVideo = h.type == ExtensionType.bangumi;
    final remota = esRemota(h.cover);
    // Lectura: siempre póster de red, nunca hay captura.
    if (!esVideo) {
      return PortadaHistorial(url: h.cover, necesitaHeaders: true);
    }
    if (remota) {
      return PortadaHistorial(url: h.cover, necesitaHeaders: true);
    }
    return PortadaHistorial(
      archivo: h.cover != null ? File(h.cover!) : null,
      necesitaHeaders: false,
    );
  }
}
