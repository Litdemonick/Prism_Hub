import 'package:flutter/material.dart';
import 'dart:async';
import 'package:prismhub/utils/cast_aparato.dart';
import 'package:prismhub/utils/cast_discovery.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/log.dart';
import 'package:prismhub/views/widgets/progress.dart';

class VideoPlayerCast extends StatefulWidget {
  const VideoPlayerCast({
    super.key,
    this.onDeviceSelected,
  });
  final Function(AparatoDeCasteo aparato)? onDeviceSelected;

  @override
  State<VideoPlayerCast> createState() => _VideoPlayerCastState();
}

class _VideoPlayerCastState extends State<VideoPlayerCast> {
  CastDiscovery? searcher;
  StreamSubscription? _devicesSub;
  Timer? _finDeBusqueda;
  List<AparatoDeCasteo> deviceList = const [];

  /// Si sigue buscando. La busqueda NO puede quedar abierta para siempre.
  ///
  /// DLNAManager.start() emite mensajes SSDP a la red una y otra vez mientras
  /// este vivo, y antes nada lo paraba: la rueda giraba sin fin —incluso con
  /// los aparatos ya encontrados— y el telefono seguia hablandole a la red
  /// entera todo el rato que la lista estuviera abierta.
  bool _buscando = true;

  /// Evita que dos toques seguidos manden el video dos veces.
  bool _eligiendo = false;

  /// Cuanto se busca antes de parar. Los aparatos de la red suelen contestar
  /// en uno o dos segundos; a los diez ya no aparece nada nuevo.
  static const _duracionBusqueda = Duration(seconds: 10);

  @override
  void initState() {
    super.initState();
    _init();
  }

  _init() async {
    setState(() => _buscando = true);
    // Buscador propio: el del paquete no encuentra nada en Windows aunque el
    // mismo aparato aparezca al toque desde el telefono. Ver cast_discovery.
    searcher = CastDiscovery();
    logger.info('DLNA searching devices...');
    await searcher!.start();
    if (!mounted) {
      searcher?.stop();
      return;
    }
    // Se escucha la lista YA CLASIFICADA: solo los que de verdad pueden
    // reproducir. La cruda trae tambien el router y los Chromecast, que
    // elegidos terminaban en "no se pudo enviar la señal".
    _devicesSub = searcher!.aparatos.listen((lista) {
      if (lista.length != deviceList.length) {
        logger.info('Aparatos utiles: ${lista.length}');
      }
      if (!mounted) return;
      setState(() => deviceList = lista);
    });
    _finDeBusqueda?.cancel();
    _finDeBusqueda = Timer(_duracionBusqueda, _pararBusqueda);
  }

  void _pararBusqueda() {
    _finDeBusqueda?.cancel();
    _finDeBusqueda = null;
    searcher?.stop();
    searcher = null;
    _devicesSub?.cancel();
    _devicesSub = null;
    if (mounted) setState(() => _buscando = false);
  }

  Future<void> _buscarDeNuevo() async {
    _pararBusqueda();
    if (!mounted) return;
    // Se conservan los ya encontrados: si el aparato buscado ya esta en la
    // lista, vaciarla solo lo haria desaparecer un rato sin motivo.
    await _init();
  }

  @override
  void dispose() {
    logger.info('DLNA stop searching devices...');
    _finDeBusqueda?.cancel();
    _devicesSub?.cancel();
    searcher?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Text(
            'video.cast'.i18n,
            style: const TextStyle(
              fontSize: 18,
            ),
          ),
        ),
        const SizedBox(height: 10),
        for (final aparato in deviceList)
          ListTile(
            // Un icono por clase: con dos protocolos distintos conviviendo en
            // la misma lista, saber cuál es cuál ayuda a entender por qué en
            // uno hay velocidad y en el otro no.
            leading: Icon(
              aparato.esChromecast ? Icons.cast_rounded : Icons.tv_rounded,
            ),
            title: Text(aparato.nombre),
            subtitle: Text(
              aparato.esChromecast ? 'Chromecast' : 'DLNA',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            // Un segundo toque mandaria el video dos veces.
            onTap: _eligiendo
                ? null
                : () {
                    setState(() => _eligiendo = true);
                    widget.onDeviceSelected?.call(aparato);
                  },
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          child: _buscando
              ? Row(
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: ProgressRing(),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'video.cast-searching'.i18n,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                )
              // Terminada la busqueda hay algo que decir y algo que hacer, en
              // vez de una rueda girando para siempre sin explicar nada.
              //
              // En COLUMNA y no en fila: el texto y el boton uno al lado del
              // otro dejaban al texto en una tira de cuatro palabras de ancho
              // que ademas se cortaba por abajo. Asi cada cosa usa el ancho
              // entero.
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(
                          deviceList.isEmpty
                              ? Icons.tv_off_rounded
                              : Icons.check_circle_outline_rounded,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            deviceList.isEmpty
                                ? 'video.cast-none-found'.i18n
                                : 'video.cast-search-done'.i18n,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    // La explicacion de la red solo cuando no encontro nada:
                    // encontrando algo no hay nada que explicar.
                    if (deviceList.isEmpty) ...[
                      const SizedBox(height: 8),
                      Opacity(
                        opacity: 0.7,
                        child: Text(
                          'video.cast-none-found-hint'.i18n,
                          style: const TextStyle(fontSize: 12, height: 1.35),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    TextButton.icon(
                      onPressed: _buscarDeNuevo,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: Text('video.cast-search-again'.i18n),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}
