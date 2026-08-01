import 'package:flutter/material.dart';
import 'package:dlna_dart/dlna.dart';
import 'dart:async';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/log.dart';
import 'package:prismhub/views/widgets/progress.dart';

class VideoPlayerCast extends StatefulWidget {
  const VideoPlayerCast({
    super.key,
    this.onDeviceSelected,
  });
  final Function(DLNADevice device)? onDeviceSelected;

  @override
  State<VideoPlayerCast> createState() => _VideoPlayerCastState();
}

class _VideoPlayerCastState extends State<VideoPlayerCast> {
  DLNAManager? searcher;
  StreamSubscription? _devicesSub;
  Timer? _finDeBusqueda;
  Map<String, DLNADevice> deviceList = {};

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
    searcher = DLNAManager();
    logger.info('DLNA searching devices...');
    final m = await searcher!.start();
    if (!mounted) {
      searcher?.stop();
      return;
    }
    _devicesSub = m.devices.stream.listen((deviceList) {
      logger.info('DLNA devices: $deviceList');
      if (!mounted) return;
      setState(() {
        this.deviceList = deviceList;
      });
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
        for (final device in deviceList.entries)
          ListTile(
            leading: const Icon(Icons.tv_rounded),
            title: Text(device.value.info.friendlyName),
            subtitle: Text(
              device.key,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            // Un segundo toque mandaria el video dos veces.
            onTap: _eligiendo
                ? null
                : () {
                    setState(() => _eligiendo = true);
                    widget.onDeviceSelected?.call(device.value);
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
              : Row(
                  children: [
                    Expanded(
                      child: Text(
                        deviceList.isEmpty
                            ? 'video.cast-none-found'.i18n
                            : 'video.cast-search-done'.i18n,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 12),
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
