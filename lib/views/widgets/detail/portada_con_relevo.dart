import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:prismhub/views/widgets/cache_network_image.dart';
import 'package:prismhub/views/widgets/cover.dart';

/// Dibuja la portada de la ficha sin que se vea un hueco al cambiar de imagen.
///
/// La ficha empieza con la portada que traía la tarjeta tocada (ya descargada,
/// aparece al instante) y después la extensión puede devolver otra distinta. El
/// cambio directo se ve mal: la nueva empieza vacía, así que justo después de
/// haber tenido imagen la tarjeta quedaba en blanco todo lo que durara su
/// descarga —medido en HQPorner, 1265 ms para 108 KB— y de golpe aparecía. Eso
/// es el parpadeo.
///
/// Acá la de antes se queda abajo, puesta, y la nueva se funde ENCIMA recién
/// cuando ya está cargada de verdad. Nunca hay un fotograma sin nada.
class PortadaConRelevo extends StatefulWidget {
  const PortadaConRelevo({
    super.key,
    required this.alt,
    required this.urlPrevia,
    required this.cabecerasPrevias,
    required this.urlFinal,
    required this.cabecerasFinales,
    this.alignment = Alignment.center,
    this.noText = false,
    this.canFullScreen = false,
    this.entera = false,
    this.onTamanoReal,
  });

  /// El tamaño real de la imagen que se termina mostrando.
  ///
  /// La ficha lo usa para darle a la caja la forma de ESTA portada. La forma
  /// que publica el catálogo (ver FormaPortada) es la típica de la extensión y
  /// tarda cuatro portadas en decidirse: hasta entonces, y en los títulos que
  /// traen otra forma, la caja quedaba equivocada y la imagen se veía chica en
  /// el medio con relleno borroso alrededor.
  final void Function(int ancho, int alto)? onTamanoReal;

  /// El título, para el recuadro de color con el nombre cuando no hay imagen.
  final String alt;

  /// La que traía la tarjeta. Null si se llegó sin pasar por una.
  final String? urlPrevia;
  final Map<String, String>? cabecerasPrevias;

  /// La que hay que terminar mostrando: la de la extensión si ya llegó, y si
  /// no, la misma de antes.
  final String? urlFinal;
  final Map<String, String>? cabecerasFinales;

  final Alignment alignment;
  final bool noText;
  final bool canFullScreen;

  /// Mostrar la imagen ENTERA en vez de recortarla para llenar la caja.
  ///
  /// El hueco del póster de la ficha es vertical, pero no todas las portadas
  /// lo son: las de los sitios de vídeo son fotogramas apaisados, y recortados
  /// ahí pierden los costados —justo donde suele estar lo que se quiere ver—.
  /// Con esto se ve completa, y lo que sobra de la caja se rellena con una
  /// copia desenfocada de la misma imagen en vez de quedar en negro.
  ///
  /// En una portada que ya tiene la forma de la caja no se nota: la imagen la
  /// llena igual y el relleno queda tapado.
  final bool entera;

  @override
  State<PortadaConRelevo> createState() => _PortadaConRelevoState();
}

class _PortadaConRelevoState extends State<PortadaConRelevo> {
  /// Si la de arriba ya terminó de cargar y se puede mostrar.
  bool _finalLista = false;

  @override
  void didUpdateWidget(PortadaConRelevo anterior) {
    super.didUpdateWidget(anterior);
    // Cambió la imagen de destino: hay que volver a esperarla. Sin esto, una
    // segunda imagen se mostraría de una (con la marca de la primera todavía
    // puesta) y volvería el hueco que esto viene a evitar.
    if (anterior.urlFinal != widget.urlFinal) _finalLista = false;
  }

  bool get _hayRelevo {
    final previa = widget.urlPrevia;
    final destino = widget.urlFinal;
    return previa != null &&
        previa.isNotEmpty &&
        destino != null &&
        destino.isNotEmpty &&
        destino != previa;
  }

  Widget _imagen(String url, Map<String, String>? cabeceras,
      {bool avisarCuandoCargue = false, bool tocable = false}) {
    // El aviso de "ya cargó" se reaprovecha del tamaño real que manda la
    // imagen. Llega en mitad de un dibujado, así que el cambio de estado se
    // pide para el fotograma siguiente y no en el momento.
    void avisar(int ancho, int alto) {
      widget.onTamanoReal?.call(ancho, alto);
      // El relevo es lo único que necesita rearmarse. Sin relevo (una sola
      // imagen) esto sería un setState de más en cada carga.
      if (!_hayRelevo || _finalLista) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _finalLista = true);
      });
    }

    Widget pic(
        {required BoxFit fit, bool conAviso = false, bool toque = false}) {
      return CacheNetWorkImagePic(
        url,
        fit: fit,
        width: double.infinity,
        height: double.infinity,
        alignment: widget.alignment,
        headers: cabeceras,
        canFullScreen: toque,
        onTamanoReal: conAviso ? avisar : null,
      );
    }

    if (!widget.entera) {
      return pic(
          fit: BoxFit.cover, conAviso: avisarCuandoCargue, toque: tocable);
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // El relleno: la misma imagen estirada y desenfocada. Es la única que
        // siempre combina con la de adelante, venga de donde venga. Va
        // apagada para que no compita con la de verdad.
        ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Opacity(opacity: 0.55, child: pic(fit: BoxFit.cover)),
        ),
        pic(fit: BoxFit.contain, conAviso: avisarCuandoCargue, toque: tocable),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Sin relevo que hacer: es la misma imagen, o solo hay una, o ninguna.
    if (!_hayRelevo) {
      final unica = widget.urlFinal ?? widget.urlPrevia;
      final cabeceras = widget.urlFinal != null
          ? widget.cabecerasFinales
          : widget.cabecerasPrevias;
      // Sin ninguna imagen: Cover ya resuelve ese caso con su recuadro de
      // color y el título.
      if (unica == null || unica.isEmpty) {
        return Cover(
          alt: widget.alt,
          url: unica,
          noText: widget.noText,
          headers: cabeceras,
          alignment: widget.alignment,
        );
      }
      // Y no Cover: Cover recorta siempre, y este es el camino más habitual
      // —la mayoría de las extensiones devuelven la misma portada que ya
      // traía la tarjeta—. Por acá tiene que valer igual el ajuste de que la
      // imagen se vea entera.
      return _imagen(
        unica,
        cabeceras,
        avisarCuandoCargue: widget.onTamanoReal != null,
        tocable: widget.canFullScreen,
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        _imagen(widget.urlPrevia!, widget.cabecerasPrevias,
            tocable: widget.canFullScreen && !_finalLista),
        // IgnorePointer mientras no se ve: una capa transparente por encima
        // igual se come los toques, y el usuario tocaría una imagen invisible
        // en vez de la que tiene delante.
        IgnorePointer(
          ignoring: !_finalLista,
          child: AnimatedOpacity(
            opacity: _finalLista ? 1 : 0,
            // Suave y corto: es para que el cambio no salte, no para hacer
            // esperar a nadie.
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOut,
            child: _imagen(widget.urlFinal!, widget.cabecerasFinales,
                avisarCuandoCargue: true,
                tocable: widget.canFullScreen && _finalLista),
          ),
        ),
      ],
    );
  }
}
