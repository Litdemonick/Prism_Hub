import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:prismhub/utils/exportar_registro.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/log.dart';
import 'package:prismhub/utils/platform_tv.dart';
import 'package:prismhub/utils/sesiones_del_registro.dart';
import 'package:prismhub/utils/servidor_de_registro.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/messenger.dart';
import 'package:prismhub/views/widgets/tv/desplazable_con_mando.dart';
import 'package:prismhub/views/widgets/tv/focusable_card.dart';

/// Las veces anteriores que se abrió la app, para poder mirar hacia atrás.
///
/// ── Para qué ────────────────────────────────────────────────────────────────
///
/// Un fallo que cierra la app no se puede diagnosticar con lo que pasa
/// DESPUÉS de volver a abrirla: lo que sirve es lo de antes, y eso pertenece a
/// otra apertura. La pantalla en vivo muestra solo la de ahora —a propósito,
/// para que empiece limpia— así que las anteriores tienen que estar en algún
/// lado, y este es ese lado.
///
/// Cada una se lista con su fecha y su hora, la más reciente arriba, que es el
/// orden en que se busca: casi siempre lo que se quiere es «la vez anterior».
class HistorialDeRegistroPage extends StatefulWidget {
  const HistorialDeRegistroPage({super.key});

  @override
  State<HistorialDeRegistroPage> createState() =>
      _HistorialDeRegistroPageState();
}

class _HistorialDeRegistroPageState extends State<HistorialDeRegistroPage> {
  List<SesionDelRegistro> _sesiones = const [];
  bool _cargando = true;
  String? _fallo;

  @override
  void initState() {
    super.initState();
    // Detrás de la transición, igual que el visor en vivo: leer el archivo es
    // trabajo del hilo de la interfaz y hacerlo mientras entra la pantalla se
    // ve como un tirón, sobre todo en un televisor.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final animacion = ModalRoute.of(context)?.animation;
      if (animacion == null || animacion.isCompleted) {
        unawaited(_cargar());
        return;
      }
      void alTerminar(AnimationStatus estado) {
        if (estado != AnimationStatus.completed) return;
        animacion.removeStatusListener(alTerminar);
        if (mounted) unawaited(_cargar());
      }

      animacion.addStatusListener(alTerminar);
    });
  }

  Future<void> _cargar() async {
    try {
      await PrismLog.flush();
      final archivo = File(PrismLog.logFilePath);
      if (!await archivo.exists()) {
        if (mounted) setState(() => _cargando = false);
        return;
      }
      final texto = await archivo.readAsString();
      final lineas = const LineSplitter()
          .convert(texto)
          .where((l) => l.trim().isNotEmpty)
          .toList(growable: false);
      final todas = partirEnSesiones(lineas);
      if (!mounted) return;
      setState(() {
        // La última es la de ahora, y esa ya se ve en la pantalla anterior.
        // Repetirla acá sería ofrecer dos caminos al mismo sitio.
        _sesiones = todas.length <= 1
            ? const []
            : todas.sublist(0, todas.length - 1).reversed.toList();
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _fallo = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HomeTheme.bg,
      appBar: AppBar(
        backgroundColor: HomeTheme.bg,
        title: Text(
          'settings.log-historial'.i18n,
          style: TextStyle(color: HomeTheme.textPrimary),
        ),
      ),
      body: _cuerpo(),
    );
  }

  Widget _cuerpo() {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_fallo != null) {
      return _aviso(
        FlutterI18n.translate(
          context,
          'settings.log-historial-error',
          translationParams: {'error': _fallo!},
        ),
      );
    }
    if (_sesiones.isEmpty) {
      return _aviso('settings.log-historial-vacio'.i18n);
    }
    final tv = PlatformTv.esTelevisionSync;
    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: tv ? 48 : 16, vertical: 12),
      itemCount: _sesiones.length,
      itemBuilder: (context, i) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _tarjeta(_sesiones[i], primera: i == 0),
      ),
    );
  }

  Widget _aviso(String texto) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            texto,
            textAlign: TextAlign.center,
            style: TextStyle(color: HomeTheme.textMuted, fontSize: 14),
          ),
        ),
      );

  Widget _tarjeta(SesionDelRegistro sesion, {required bool primera}) {
    final tv = PlatformTv.esTelevisionSync;
    final fallos = sesion.lineas.where(_esFallo).length;
    return FocusableCard(
      borderRadius: 12,
      // La primera toma el foco al entrar: con un mando, tener que bajar una
      // vez para empezar a elegir es una pulsación que no hace falta.
      autofocus: primera,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _SesionPage(sesion: sesion),
        ),
      ),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: tv ? 20 : 14,
          vertical: tv ? 16 : 12,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.white.withValues(alpha: 0.05),
        ),
        child: Row(
          children: [
            Icon(
              fallos > 0 ? Icons.error_outline : Icons.history,
              size: tv ? 26 : 22,
              color: fallos > 0 ? HomeTheme.accentRed : HomeTheme.textMuted,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _cuando(sesion),
                    style: TextStyle(
                      fontSize: tv ? 17 : 15,
                      fontWeight: FontWeight.w600,
                      color: HomeTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _resumen(sesion, fallos),
                    style: TextStyle(
                      fontSize: tv ? 14 : 12,
                      color: fallos > 0
                          ? HomeTheme.accentRed
                          : HomeTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: tv ? 26 : 22,
              color: HomeTheme.textMuted,
            ),
          ],
        ),
      ),
    );
  }

  /// La fecha en palabras cuando es reciente, y en números cuando no.
  ///
  /// «Hoy 21:45» se ubica de un vistazo; «2026-08-29 21:45» hay que leerlo y
  /// compararlo con el día de hoy. Pasados dos días la fecha completa vuelve a
  /// ser lo más claro.
  String _cuando(SesionDelRegistro sesion) {
    final cuando = sesion.cuando;
    if (cuando == null) return 'settings.log-historial-sin-fecha'.i18n;
    final hora = '${_dosCifras(cuando.hour)}:${_dosCifras(cuando.minute)}';
    final hoy = DateTime.now();
    final dia = DateTime(cuando.year, cuando.month, cuando.day);
    final diaDeHoy = DateTime(hoy.year, hoy.month, hoy.day);
    final diferencia = diaDeHoy.difference(dia).inDays;
    if (diferencia == 0) return '${'settings.log-historial-hoy'.i18n} $hora';
    if (diferencia == 1) return '${'settings.log-historial-ayer'.i18n} $hora';
    return '${cuando.year}-${_dosCifras(cuando.month)}-'
        '${_dosCifras(cuando.day)}  $hora';
  }

  static String _dosCifras(int n) => n.toString().padLeft(2, '0');

  String _resumen(SesionDelRegistro sesion, int fallos) {
    final lineas = FlutterI18n.translate(
      context,
      'settings.log-lines',
      translationParams: {'n': '${sesion.cuantasLineas}'},
    );
    if (fallos == 0) return lineas;
    final cuantos = FlutterI18n.translate(
      context,
      'settings.log-historial-fallos',
      translationParams: {'n': '$fallos'},
    );
    return '$lineas · $cuantos';
  }

  static bool _esFallo(String l) =>
      l.contains(' SEVERE ') ||
      l.contains(' SHOUT ') ||
      l.contains('no se cerro normalmente');
}

/// Una apertura anterior, abierta para leerla.
///
/// Mismas herramientas que el visor en vivo —exportar en PC y teléfono, leerla
/// desde otro aparato en televisor— porque el motivo para usarlas es el mismo,
/// y de hecho más fuerte acá: esta es la sesión en la que pasó el fallo.
class _SesionPage extends StatefulWidget {
  const _SesionPage({required this.sesion});

  final SesionDelRegistro sesion;

  @override
  State<_SesionPage> createState() => _SesionPageState();
}

class _SesionPageState extends State<_SesionPage> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void deactivate() {
    // Al salir, el servidor de red deja de estar atado a esta sesión: si
    // sigue encendido, lo que corresponde servir es el registro de siempre.
    ServidorDeRegistro.lineasFijas = null;
    super.deactivate();
  }

  Future<void> _exportar() async {
    try {
      await ExportarRegistro.entregar(lineas: widget.sesion.lineas);
    } catch (e) {
      if (!mounted) return;
      showPlatformSnackbar(
        context: context,
        content: FlutterI18n.translate(
          context,
          'settings.log-export-error',
          translationParams: {'error': '$e'},
        ),
      );
    }
  }

  Future<void> _alternarServidor() async {
    if (ServidorDeRegistro.encendido) {
      await ServidorDeRegistro.apagar();
      if (mounted) setState(() {});
      return;
    }
    // Se sirve ESTA sesión y no el registro entero: es lo que se está
    // mirando en la pantalla, y ver una cosa en el televisor y otra en el
    // navegador obliga a ir traduciendo entre las dos.
    ServidorDeRegistro.lineasFijas = widget.sesion.lineas;
    ServidorDeRegistro.areaElegida = null;
    final r = await ServidorDeRegistro.encender();
    if (!mounted) return;
    setState(() {});
    if (r.direccion == null) {
      ServidorDeRegistro.lineasFijas = null;
      showPlatformSnackbar(
        context: context,
        content: switch (r.fallo) {
          FalloDeServidor.noSePudo => 'settings.log-en-red-bloqueado'.i18n,
          _ => 'settings.log-en-red-sin-red'.i18n,
        },
      );
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: HomeTheme.bg,
        title: Text(
          'settings.log-en-red'.i18n,
          style: TextStyle(color: HomeTheme.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'settings.log-en-red-como'.i18n,
              style: TextStyle(color: HomeTheme.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 16),
            SelectableText(
              r.direccion!,
              style: TextStyle(
                color: HomeTheme.accentPink,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'settings.log-en-red-aviso'.i18n,
              style: TextStyle(color: HomeTheme.textMuted, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('common.close'.i18n),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tv = PlatformTv.esTelevisionSync;
    return Scaffold(
      backgroundColor: HomeTheme.bg,
      appBar: AppBar(
        backgroundColor: HomeTheme.bg,
        title: Text(
          'settings.log-historial'.i18n,
          style: TextStyle(color: HomeTheme.textPrimary),
        ),
        actions: [
          if (!tv)
            IconButton(
              tooltip: 'common.export'.i18n,
              icon: const Icon(Icons.ios_share),
              color: HomeTheme.textPrimary,
              onPressed: _exportar,
            ),
          if (tv)
            IconButton(
              tooltip: 'settings.log-en-red'.i18n,
              icon: Icon(ServidorDeRegistro.encendido
                  ? Icons.wifi_tethering
                  : Icons.wifi_tethering_off),
              color: ServidorDeRegistro.encendido
                  ? HomeTheme.accentPink
                  : HomeTheme.textPrimary,
              onPressed: _alternarServidor,
            ),
        ],
      ),
      body: DesplazableConMando(
        controlador: _scroll,
        child: SelectionArea(
          child: ListView.builder(
            controller: _scroll,
            padding: EdgeInsets.fromLTRB(tv ? 32 : 12, 8, tv ? 32 : 12, 24),
            itemCount: widget.sesion.lineas.length,
            itemBuilder: (context, i) {
              final linea = widget.sesion.lineas[i];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  linea,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontFamilyFallback: const [
                      'Consolas',
                      'DejaVu Sans Mono',
                      'Courier New',
                    ],
                    fontSize: tv ? 13.5 : 11.5,
                    height: 1.35,
                    color: _colorDe(linea),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Color _colorDe(String linea) {
    if (linea.contains(' SEVERE ') || linea.contains(' SHOUT ')) {
      return HomeTheme.accentRed;
    }
    if (linea.contains(' WARNING ')) return const Color(0xFFE0A93B);
    if (linea.contains('═══') || linea.contains('║')) {
      return HomeTheme.accentPink;
    }
    if (linea.contains('LO ULTIMO QUE HIZO')) return const Color(0xFFB07BE0);
    if (linea.contains('RESULTADO ·')) return const Color(0xFF6FA8DC);
    return HomeTheme.textMuted;
  }
}
