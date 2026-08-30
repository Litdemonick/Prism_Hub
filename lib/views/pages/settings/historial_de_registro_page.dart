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
import 'package:prismhub/views/widgets/seleccionable_si_se_puede.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/messenger.dart';
import 'package:prismhub/utils/zonas_del_registro.dart';
import 'package:prismhub/views/widgets/tv/columna_de_acciones.dart';
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
    if (!PlatformTv.esTelevisionSync) {
      return Scaffold(
        backgroundColor: HomeTheme.bg,
        appBar: AppBar(
          backgroundColor: HomeTheme.bg,
          title: Text(
            'settings.log-historial'.i18n,
            style: TextStyle(color: HomeTheme.textPrimary),
          ),
        ),
        // Los lados: apaisado, el recorte de cámara y la barra de gestos se
        // comen la primera columna de las tarjetas. Arriba no, que de eso ya
        // se ocupó la barra de título.
        body: SafeArea(top: false, child: _cuerpo()),
      );
    }
    // En televisor, la misma columna que las otras dos pantallas.
    //
    // Acá la lista puede ser larga, y con un mando volver atrás obligaba a
    // recorrerla entera hacia arriba hasta la flecha de la barra. Con la
    // salida al costado se llega desde cualquier punto.
    return Scaffold(
      backgroundColor: HomeTheme.bg,
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ColumnaDeAcciones(
              titulo: 'settings.log-historial'.i18n,
              detalle: _cargando
                  ? null
                  : FlutterI18n.translate(
                      context,
                      'settings.log-historial-cuantas',
                      translationParams: {'n': '${_sesiones.length}'},
                    ),
              grupos: [
                GrupoDeColumna(
                  opciones: [
                    OpcionDeColumna(
                      icono: Icons.arrow_back,
                      texto: 'common.exit'.i18n,
                      onTap: () => Navigator.of(context).maybePop(),
                    ),
                  ],
                ),
              ],
            ),
            Expanded(child: _cuerpo()),
          ],
        ),
      ),
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
      // Aire arriba, y no un margen parejo.
      //
      // La primera tarjeta arrancaba pegada al borde de la pantalla —debajo
      // del título en teléfono y PC, y a la altura del título de la columna
      // en televisor— y se leía como si estuviera cortada por arriba.
      // Reportado en vivo. En televisor va más, que es donde más se nota.
      padding: EdgeInsets.fromLTRB(16, tv ? 34 : 16, tv ? 20 : 16, 20),
      itemCount: _sesiones.length,
      itemBuilder: (context, i) => Padding(
        // La lista se rehace cuando se vuelve de una sesión, y sin clave el
        // estado de cada tarjeta se emparejaría por posición.
        key: ValueKey(_sesiones[i].cuando?.toIso8601String() ?? 'sin-fecha-$i'),
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
    final fallos =
        sesion.lineas.where(ZonaDelRegistro.fallos.acepta).length;
    return FocusableCard(
      borderRadius: 12,
      // Una fila de ancho completo: crecer solo la pega contra los bordes de
      // la pantalla, y dentro de una lista que recorta queda mordida.
      conCrecido: false,
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
          // Opaco a proposito: ver el comentario de _superficie.
          color: _superficie,
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
                    sesion.cuando == null
                        ? 'settings.log-historial-sin-fecha'.i18n
                        : textoDeFecha(context, sesion.cuando!),
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

  /// Qué zona se está mirando de esta sesión.
  ///
  /// Las mismas cuatro que en el registro en vivo, y por el mismo motivo: una
  /// apertura entera son cientos de líneas y quien la abre viene buscando una
  /// cosa. Pedido explícito: «el historial al entrar también debe dejar las
  /// opciones de todos, fallos, extensiones, etc».
  ZonaDelRegistro _zona = ZonaDelRegistro.todo;

  bool _tieneFoco = false;

  /// Un nodo por zona, fijo. Mismo motivo que en el registro en vivo: un
  /// nodo que cambia de tarjeta deja marcada a la que se lo sacaron.
  late final List<FocusNode> _focosDeZona = [
    for (final z in ZonaDelRegistro.values)
      FocusNode(debugLabel: 'sesion-zona-${z.name}'),
  ];

  /// A dónde salta el foco al pulsar izquierda desde el texto.
  FocusNode get _focoDelRail => _focosDeZona[_zona.index];

  @override
  void dispose() {
    _scroll.dispose();
    for (final f in _focosDeZona) {
      f.dispose();
    }
    super.dispose();
  }

  @override
  void deactivate() {
    // Al salir, el servidor de red deja de estar atado a esta sesión: si
    // sigue encendido, lo que corresponde servir es el registro de siempre.
    ServidorDeRegistro.lineasFijas = null;
    ServidorDeRegistro.areaElegida = null;
    super.deactivate();
  }

  List<String> get _visibles => _zona == ZonaDelRegistro.todo
      ? widget.sesion.lineas
      : widget.sesion.lineas.where(_zona.seVe).toList(growable: false);

  void _elegirZona(ZonaDelRegistro z) {
    setState(() {
      _zona = z;
      // Lo que se sirve por la red sigue a lo que se está mirando: ver una
      // cosa en la pantalla y otra en el navegador obliga a ir traduciendo
      // entre las dos.
      if (ServidorDeRegistro.encendido) {
        ServidorDeRegistro.lineasFijas = _visibles;
        ServidorDeRegistro.areaElegida = _zona.area;
        // Las líneas ya vienen filtradas: la zona es solo para el título.
        ServidorDeRegistro.zonaElegida = null;
      }
    });
  }

  Future<void> _exportar() async {
    try {
      // Con «historial» adelante: al recibir dos archivos, uno de la sesión
      // de ahora y otro de una anterior, el nombre tiene que decir cuál es.
      final salio = await ExportarRegistro.entregar(
        lineas: _visibles,
        etiqueta: 'historial-${_zona.name}',
      );
      if (!salio || !mounted) return;
      showPlatformSnackbar(
        context: context,
        content: 'settings.log-export-listo'.i18n,
      );
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
      final seguro = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: HomeTheme.bg,
          title: Text(
            'settings.log-en-red-cortar'.i18n,
            style: TextStyle(color: HomeTheme.textPrimary),
          ),
          content: Text(
            'settings.log-en-red-cortar-detalle'.i18n,
            style: TextStyle(color: HomeTheme.textMuted, fontSize: 13),
          ),
          actions: [
            TextButton(
              autofocus: true,
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('common.cancel'.i18n),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(
                'common.confirm'.i18n,
                style: TextStyle(color: HomeTheme.accentPink),
              ),
            ),
          ],
        ),
      );
      if (seguro != true) return;
      await ServidorDeRegistro.apagar();
      if (mounted) setState(() {});
      return;
    }
    // Se sirve ESTA sesión, y la zona que se esté mirando de ella.
    ServidorDeRegistro.lineasFijas = _visibles;
    ServidorDeRegistro.areaElegida = _zona.area;
    ServidorDeRegistro.zonaElegida = null;
    // Con la fecha, no solo «historial»: hay diez aperturas guardadas y desde
    // el navegador tienen todas la misma pinta.
    ServidorDeRegistro.queSeSirve =
        'historial · apertura del ${_tituloDeLaSesion()}';
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
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(),
            child: Text('common.close'.i18n),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PlatformTv.esTelevisionSync ? _televisor() : _tactil();
  }

  /// En televisor, la misma disposición que el registro en vivo.
  ///
  /// Pedido explícito: «en el historial en Android TV debés hacer el mismo
  /// diseño que registro, porque al entrar, si hay mucho texto, subir hasta
  /// arriba sería un montón». Es el mismo problema y merece la misma
  /// solución — y que las dos pantallas se parezcan es media pantalla menos
  /// que aprender.
  Widget _televisor() {
    final cuando = _tituloDeLaSesion();
    return Scaffold(
      backgroundColor: HomeTheme.bg,
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ColumnaDeAcciones(
              titulo: cuando,
              detalle: FlutterI18n.translate(
                context,
                'settings.log-lines',
                translationParams: {'n': '${_visibles.length}'},
              ),
              grupos: [
                GrupoDeColumna(
                  titulo: 'settings.log-zona'.i18n,
                  opciones: [
                    for (final z in ZonaDelRegistro.values)
                      OpcionDeColumna(
                        id: z.name,
                        texto: z.clave.i18n,
                        elegido: _zona == z,
                        onTap: () => _elegirZona(z),
                        foco: _focosDeZona[z.index],
                      ),
                  ],
                ),
                GrupoDeColumna(
                  titulo: 'settings.log-acciones'.i18n,
                  opciones: [
                    OpcionDeColumna(
                      id: 'red',
                      icono: ServidorDeRegistro.encendido
                          ? Icons.wifi_tethering
                          : Icons.wifi_tethering_off,
                      texto: 'settings.log-en-red'.i18n,
                      elegido: ServidorDeRegistro.encendido,
                      onTap: _alternarServidor,
                    ),
                  ],
                ),
                GrupoDeColumna(
                  opciones: [
                    OpcionDeColumna(
                      icono: Icons.arrow_back,
                      texto: 'common.exit'.i18n,
                      onTap: () => Navigator.of(context).maybePop(),
                    ),
                  ],
                ),
              ],
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 20, 20),
                child: PanelDeTelevisor(
                  tieneFoco: _tieneFoco,
                  child: _texto(paraTelevisor: true),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// En teléfono y escritorio, la barra de arriba de siempre.
  ///
  /// Acá sí funciona: con el dedo o con el ratón se llega a la barra sin
  /// recorrer nada, así que mover los botones a un costado sería quitarle
  /// ancho al texto sin ganar nada.
  ///
  /// Sin «ver desde otro aparato»: acá se puede exportar el archivo y abrirlo
  /// con lo que haya. Levantar un servidor para leer en otra pantalla lo que
  /// ya se puede guardar sería sumar riesgo a cambio de nada.
  Widget _tactil() {
    return Scaffold(
      backgroundColor: HomeTheme.bg,
      appBar: AppBar(
        backgroundColor: HomeTheme.bg,
        // Se encoge antes que cortarse: una fecha larga con el botón al lado
        // no entra en un teléfono angosto.
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            _tituloDeLaSesion(),
            maxLines: 1,
            style: TextStyle(color: HomeTheme.textPrimary),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'common.export'.i18n,
            icon: const Icon(Icons.ios_share),
            color: HomeTheme.textPrimary,
            onPressed: _exportar,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _barraDeZonas(),
            Expanded(child: _texto()),
          ],
        ),
      ),
    );
  }

  /// Las zonas en fila, para tocarlas con el dedo o el ratón.
  Widget _barraDeZonas() {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final z in ZonaDelRegistro.values)
            Padding(
              // Ver la nota de la barra de zonas del registro en vivo.
              key: ValueKey(z.name),
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: FocusableCard(
                  borderRadius: 999,
                  onTap: () => _elegirZona(z),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: _zona == z
                          ? Color.alphaBlend(
                              HomeTheme.accentPink.withValues(alpha: 0.22),
                              HomeTheme.bg,
                            )
                          : _superficie,
                    ),
                    child: Text(
                      z.clave.i18n,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            _zona == z ? FontWeight.w700 : FontWeight.w500,
                        color: _zona == z
                            ? HomeTheme.accentPink
                            : HomeTheme.textMuted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _tituloDeLaSesion() {
    final cuando = widget.sesion.cuando;
    if (cuando == null) return 'settings.log-historial'.i18n;
    return textoDeFecha(context, cuando);
  }

  Widget _texto({bool paraTelevisor = false}) {
    final lineas = _visibles;
    if (lineas.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'settings.log-empty'.i18n,
            textAlign: TextAlign.center,
            style: TextStyle(color: HomeTheme.textMuted, fontSize: 14),
          ),
        ),
      );
    }
    final agrupadas = agruparElRecuadro(lineas);
    return DesplazableConMando(
      controlador: _scroll,
      alCambiarFoco: paraTelevisor
          ? (tiene) {
              if (!mounted) return;
              setState(() => _tieneFoco = tiene);
            }
          : null,
      alIrIzquierda:
          paraTelevisor ? () => _focoDelRail.requestFocus() : null,
      child: SeleccionableSiSePuede(
        child: ListView.builder(
          controller: _scroll,
          padding: paraTelevisor
              ? const EdgeInsets.fromLTRB(18, 14, 18, 24)
              : const EdgeInsets.fromLTRB(12, 8, 12, 24),
          itemCount: agrupadas.length,
          itemBuilder: (context, i) {
            final linea = agrupadas[i];
            final estilo = TextStyle(
              fontFamily: 'monospace',
              fontFamilyFallback: const [
                'Consolas',
                'DejaVu Sans Mono',
                'Courier New',
              ],
              fontSize: paraTelevisor ? 13.5 : 11.5,
              height: 1.35,
              color: _colorDe(linea),
            );
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: esElRecuadro(linea)
                  // El recuadro es un dibujo: se achica entero hasta entrar,
                  // en vez de partirse línea por línea. Ver esElRecuadro.
                  ? FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(linea, style: estilo, softWrap: false),
                    )
                  : Text(linea, style: estilo),
            );
          },
        ),
      ),
    );
  }

  Color _colorDe(String linea) => colorDeLinea(linea);
}

/// Cuándo se abrió esa sesión: fecha completa y hora exacta.
///
/// ── Por qué no dice «Hoy» ni «Ayer» ─────────────────────────────────────────
///
/// Se mostraba así porque se ubica de un vistazo. Y sirve mientras se mira el
/// historial en el momento — pero estas fechas se leen sobre todo al revés:
/// alguien reporta un fallo, dice cuándo le pasó, y hay que encontrar esa
/// apertura. Con «Ayer» hay que ir calculando contra el día de hoy, y si el
/// registro se exportó anteayer la cuenta ya no da.
///
/// Pedido explícito: «que agregue la fecha en vez de que diga ayer, y que diga
/// bien la hora». Va también con los segundos: dos aperturas del mismo minuto
/// se veían idénticas y no había forma de saber cuál era cuál.
String textoDeFecha(BuildContext context, DateTime cuando) {
  final fecha = '${cuando.year}-${_dosCifras(cuando.month)}-'
      '${_dosCifras(cuando.day)}';
  return '$fecha · ${_hora(context, cuando)}';
}

/// La hora en el formato que use el aparato, con los segundos.
///
/// ── Por qué no se escribe en 24 h y listo ───────────────────────────────────
///
/// `alwaysUse24HourFormat` es el interruptor de «usar 24 horas» del sistema, y
/// en un televisor va con la configuración de hora y país del propio aparato.
/// Escribirla siempre en 24 h se ve raro para quien tiene el suyo en 12 — es
/// el mismo criterio que ya usa el reloj de la pantalla de inicio de TV, y
/// tienen que decir la hora igual.
///
/// No se usa `formatTimeOfDay` porque `TimeOfDay` no lleva segundos, y acá
/// hacen falta: dos aperturas del mismo minuto se veían idénticas y no había
/// forma de saber cuál era cuál.
String _hora(BuildContext context, DateTime cuando) {
  final minutos =
      '${_dosCifras(cuando.minute)}:${_dosCifras(cuando.second)}';
  if (MediaQuery.alwaysUse24HourFormatOf(context)) {
    return '${_dosCifras(cuando.hour)}:$minutos';
  }
  final l = MaterialLocalizations.of(context);
  final doce = cuando.hour % 12 == 0 ? 12 : cuando.hour % 12;
  final marca = cuando.hour < 12
      ? l.anteMeridiemAbbreviation
      : l.postMeridiemAbbreviation;
  return '$doce:$minutos $marca';
}

String _dosCifras(int n) => n.toString().padLeft(2, '0');

/// El relleno de las tarjetas de estas pantallas, opaco.
///
/// ── Por qué no puede ser semitransparente ───────────────────────────────
///
/// El resplandor de foco de [FocusableCard] se dibuja DEBAJO del hijo, y
/// cuenta con que el hijo lo tape: así solo queda a la vista lo que desborda,
/// que es el halo alrededor. Con un relleno al 5% de blanco eso no pasa — el
/// difuminado se ve entero a través de la tarjeta y parece que la luz se
/// sale del área. Reportado en vivo con foto: «al pasar el mouse y volver, la
/// luz se sale del área».
///
/// Se mezcla contra el fondo en vez de usar un color aparte para que el
/// aspecto quede igual que antes y siga siguiendo al tema claro/oscuro.
Color get _superficie =>
    Color.alphaBlend(Colors.white.withValues(alpha: 0.05), HomeTheme.bg);
