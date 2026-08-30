import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/views/widgets/tv/desplazable_con_mando.dart';
import 'package:prismhub/views/widgets/tv/focusable_card.dart';
import 'package:prismhub/utils/log.dart';
import 'package:prismhub/utils/platform_tv.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/messenger.dart';
import 'package:prismhub/views/widgets/platform_widget.dart';

/// El registro de la app, mientras pasa.
///
/// Hasta ahora, para ver qué estaba haciendo la app por dentro había que
/// activar el guardado, reproducir el fallo, exportar el archivo y abrirlo en
/// otro lado. Cuatro pasos y un cambio de aplicación para responder "¿qué
/// acaba de pasar?" — y en el teléfono, donde no hay consola, era la única
/// forma. Acá se ve directamente, mientras ocurre.
///
/// Lee de la memoria y no del archivo a propósito; el porqué está en
/// [PrismLog.enMemoria].
class RegistroEnVivoPage extends StatefulWidget {
  const RegistroEnVivoPage({super.key});

  @override
  State<RegistroEnVivoPage> createState() => _RegistroEnVivoPageState();
}

class _RegistroEnVivoPageState extends State<RegistroEnVivoPage> {
  /// Cada cuánto se mira si hay líneas nuevas.
  ///
  /// Por reloj y no escuchando cada línea: un fallo en cadena (reintentos de
  /// red, un servidor de vídeo que no responde) escupe decenas de líneas por
  /// segundo, y repintar la lista con cada una traba la pantalla justo cuando
  /// se la está mirando. Así, como mucho se repinta cuatro veces por segundo,
  /// que a ojo ya se ve como que va en vivo.
  static const _cadencia = Duration(milliseconds: 250);

  List<String> _lineas = const [];
  int _generacion = -1;
  bool _pausado = false;

  /// Si la vista está pegada al final, que es donde aparece lo nuevo.
  ///
  /// Se apaga solo cuando la persona sube a leer algo: seguir arrastrándola
  /// al fondo mientras lee es la forma más rápida de volver inútil un visor
  /// en vivo. Se vuelve a encender sola al bajar del todo.
  bool _alFinal = true;

  Timer? _reloj;
  final _scroll = ScrollController();

  /// Lo que quedó de arranques anteriores, leído del archivo.
  ///
  /// Va delante de lo que hay en memoria y no se vuelve a leer: el archivo no
  /// cambia hacia atrás, solo crece por el final — y eso ya lo cubre lo que
  /// está en memoria.
  List<String> _deAntes = const [];

  @override
  void initState() {
    super.initState();
    // ── Se lee TAMBIÉN el archivo, en las cuatro plataformas ────────────
    //
    // El visor arrancaba vacío en cada apertura: mostraba lo que estaba
    // pasando, no el historial. Reportado en vivo: «al entrar y salir se
    // borra el historial».
    //
    // Y es justo al revés de lo que hace falta. Lo que explica un cierre no
    // es lo que pasa DESPUÉS de volver a abrir la app: es lo que pasó ANTES,
    // y eso solo existe en el archivo — la memoria se fue con el proceso.
    //
    // En televisor además no hay alternativa: no hay dónde exportar ni con
    // qué abrirlo. Pero en teléfono y en PC tener el historial acá también
    // ahorra el rodeo de exportar, abrir con otra cosa y buscar a mano.
    unawaited(_leerLoAnterior());
    _refrescar();
    _reloj = Timer.periodic(_cadencia, (_) => _refrescar());
  }

  Future<void> _leerLoAnterior() async {
    try {
      final archivo = File(PrismLog.logFilePath);
      if (!await archivo.exists()) return;
      final texto = await archivo.readAsString();
      final todas = const LineSplitter()
          .convert(texto)
          .where((l) => l.trim().isNotEmpty);
      // Solo el final. Un archivo de sesiones enteras puede tener decenas de
      // miles de líneas, y construirlas todas es justo lo que no hay que
      // hacer en un televisor.
      final desde = todas.length > _topeDeLoAnterior
          ? todas.length - _topeDeLoAnterior
          : 0;
      if (!mounted) return;
      setState(() => _deAntes = todas.skip(desde).toList(growable: false));
      if (_alFinal) _bajarAlFinal();
    } catch (e) {
      // Sin permiso, o el archivo a medio escribir: se sigue con lo que haya
      // en memoria, que es como se comportaba antes.
      debugPrint('No se pudo leer el registro anterior: $e');
    }
  }

  /// Cuántas líneas del archivo se traen.
  ///
  /// Bastante más que las que caben en pantalla, para poder subir a ver qué
  /// pasó antes de un cierre, pero acotado: son widgets que hay que construir.
  static const _topeDeLoAnterior = 3000;

  @override
  void dispose() {
    _reloj?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _refrescar() {
    if (_pausado || !mounted) return;
    final generacion = PrismLog.generacion;
    if (generacion == _generacion) return;
    setState(() {
      _generacion = generacion;
      _lineas = PrismLog.enMemoria;
    });
    if (_alFinal) _bajarAlFinal();
  }

  /// Al final después de que la lista crezca, no antes.
  ///
  /// En el momento del setState el largo nuevo todavía no está medido y el
  /// salto se quedaba una línea corto: siempre faltaba ver justo la última,
  /// que es la que se está esperando.
  void _bajarAlFinal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      // jumpTo y no animateTo: con líneas entrando seguido, una animación
      // arranca de nuevo antes de terminar la anterior y el texto queda
      // temblando sin llegar nunca abajo.
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  void _alternarPausa() {
    setState(() => _pausado = !_pausado);
    // Al reanudar se muestra YA lo que se acumuló mientras estuvo en pausa, sin
    // esperar el siguiente tic.
    if (!_pausado) _refrescar();
  }

  Future<void> _limpiar() async {
    await PrismLog.limpiar();
    if (!mounted) return;
    setState(() {
      _generacion = PrismLog.generacion;
      _lineas = const [];
      _alFinal = true;
    });
    showPlatformSnackbar(
      context: context,
      content: 'settings.log-cleared'.i18n,
    );
  }

  String get _titulo => 'settings.view-log'.i18n;

  String get _contador => FlutterI18n.translate(
        context,
        'settings.log-lines',
        translationParams: {'n': '${_lineas.length}'},
      );

  // Los avisos del propio registro llevan color: en una pared de texto gris,
  // encontrar el error a ojo es justamente lo que uno vino a hacer acá.
  Color _colorDe(String linea) {
    if (linea.contains(' SEVERE ') || linea.contains(' SHOUT ')) {
      return HomeTheme.accentRed;
    }
    if (linea.contains(' WARNING ')) return const Color(0xFFE8B339);
    // La cabecera de sesión, en verde y fuerte: es lo que separa una sesión de
    // la siguiente en un archivo que ya trae varias, así que tiene que
    // encontrarse de un vistazo al recorrer.
    if (linea.contains('═══')) return const Color(0xFF6FCFA5);
    // El veredicto de cada servidor y el rastro del último cierre: son las dos
    // líneas que se buscan a propósito, así que se despegan del resto.
    if (linea.contains('RESULTADO ·')) return const Color(0xFF62B6FF);
    if (linea.contains('LO ULTIMO QUE HIZO')) return const Color(0xFFD98CFF);
    return const Color(0xFFB9BBC6);
  }

  /// Por qué categoría se está mirando el registro.
  ///
  /// Un archivo de varias sesiones son miles de líneas, y quien lo abre viene
  /// buscando UNA cosa: por qué falló una extensión, por qué se cerró la app,
  /// o qué hizo el reproductor. Recorrerlo entero con el mando para encontrar
  /// eso es lo que lo vuelve inútil en un televisor.
  _Filtro _filtro = _Filtro.todo;

  /// Las líneas que corresponden al filtro puesto.
  ///
  /// Se calcula al construir y no se guarda: el registro crece mientras se
  /// mira, así que una copia filtrada quedaría vieja enseguida.
  List<String> _conFiltro(List<String> todas) {
    if (_filtro == _Filtro.todo) return todas;
    return todas.where((l) => _filtro.acepta(l)).toList(growable: false);
  }

  // Monoespaciada con lista de reemplazos: 'monospace' es un nombre genérico
  // que resuelve Android, pero en Windows y Linux no siempre hay una fuente con
  // ese nombre y el texto caía a la de siempre — con la hora y el nivel de cada
  // línea desalineados, que es lo que hace legible un registro en columna.
  static const _mono = TextStyle(
    fontFamily: 'monospace',
    fontFamilyFallback: ['Consolas', 'DejaVu Sans Mono', 'Courier New'],
    fontSize: 11.5,
    height: 1.35,
  );

  /// La barra de filtros.
  ///
  /// Botones y no un menú desplegable: con un control remoto un desplegable
  /// son tres pulsaciones y perder de vista el registro. Acá se ve qué hay y
  /// se cambia con una.
  ///
  /// Se desplaza en horizontal para que en una pantalla angosta —un teléfono
  /// de pie— no se aplaste ninguno ni se corte el texto.
  Widget _barraDeFiltros() {
    final tv = PlatformTv.esTelevisionSync;
    return SizedBox(
      height: tv ? 56 : 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: tv ? 20 : 12),
        children: [
          for (final f in _Filtro.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: FocusableCard(
                  borderRadius: 999,
                  onTap: () => setState(() => _filtro = f),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    padding: EdgeInsets.symmetric(
                      horizontal: tv ? 20 : 14,
                      vertical: tv ? 10 : 7,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: _filtro == f
                          ? HomeTheme.accentPink.withValues(alpha: 0.22)
                          : Colors.white.withValues(alpha: 0.06),
                    ),
                    child: Text(
                      f.clave.i18n,
                      style: TextStyle(
                        fontSize: tv ? 15 : 13,
                        fontWeight:
                            _filtro == f ? FontWeight.w700 : FontWeight.w500,
                        color: _filtro == f
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

  Widget _buildLista() {
    final visibles = _conFiltro([..._deAntes, ..._lineas]);
    if (visibles.isEmpty && _lineas.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'settings.log-empty'.i18n,
            textAlign: TextAlign.center,
            style: TextStyle(color: HomeTheme.textMuted, fontSize: 13),
          ),
        ),
      );
    }

    // SelectionArea y no un SelectableText por línea: así se puede arrastrar y
    // copiar un tramo entero (un stack trace completo, por ejemplo) para
    // pegarlo en un reporte, en vez de línea por línea.
    return DesplazableConMando(
      controlador: _scroll,
      child: SelectionArea(
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        itemCount: visibles.length,
        itemBuilder: (context, index) {
          final linea = visibles[index];
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(linea, style: _mono.copyWith(color: _colorDe(linea))),
          );
        },
      ),
      ),
    );
  }

  /// Avisa de que quedó en pausa.
  ///
  /// Sin esto, una pantalla pausada y una app que no está registrando nada se
  /// ven exactamente igual, y el botón queda arriba fuera de la vista.
  Widget _bandaDePausa() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: HomeTheme.accentPink.withValues(alpha: 0.14),
      child: Text(
        'settings.log-paused-hint'.i18n,
        style: TextStyle(fontSize: 12, color: HomeTheme.textPrimary),
      ),
    );
  }

  /// Vuelve al fondo cuando la persona se fue para arriba.
  Widget _botonAlFinal() {
    return Positioned(
      right: 16,
      bottom: 16,
      child: FloatingActionButton.extended(
        backgroundColor: HomeTheme.accentPink,
        foregroundColor: Colors.black,
        onPressed: () {
          setState(() => _alFinal = true);
          _bajarAlFinal();
        },
        icon: const Icon(Icons.arrow_downward, size: 18),
        label: Text('settings.log-to-bottom'.i18n),
      ),
    );
  }

  /// Apaga el seguimiento cuando el desplazamiento se va del fondo.
  ///
  /// Mira la posición y no quién la movió: el salto automático también dispara
  /// estos avisos, pero ese siempre termina abajo, así que no apaga nada.
  bool _mirarDesplazamiento(ScrollNotification n) {
    if (n is! ScrollUpdateNotification && n is! ScrollEndNotification) {
      return false;
    }
    final abajo = n.metrics.maxScrollExtent - n.metrics.pixels < 24;
    if (abajo != _alFinal) setState(() => _alFinal = abajo);
    return false;
  }

  Widget _buildAndroid(BuildContext context) {
    return Scaffold(
      backgroundColor: HomeTheme.bg,
      appBar: AppBar(
        backgroundColor: HomeTheme.bg,
        title: Text(
          _titulo,
          style: TextStyle(color: HomeTheme.textPrimary),
        ),
        actions: [
          IconButton(
            tooltip: _pausado
                ? 'settings.log-resume'.i18n
                : 'settings.log-pause'.i18n,
            icon: Icon(_pausado ? Icons.play_arrow : Icons.pause),
            color: _pausado ? HomeTheme.accentPink : HomeTheme.textPrimary,
            onPressed: _alternarPausa,
          ),
          IconButton(
            tooltip: 'common.clear'.i18n,
            icon: const Icon(Icons.delete_outline),
            color: HomeTheme.textPrimary,
            onPressed: _limpiar,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_pausado) _bandaDePausa(),
          _barraDeFiltros(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _contador,
                style: TextStyle(
                    fontSize: 12, color: HomeTheme.textMuted),
              ),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                NotificationListener<ScrollNotification>(
                  onNotification: _mirarDesplazamiento,
                  child: _buildLista(),
                ),
                if (!_alFinal) _botonAlFinal(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // En escritorio la página es solo el cuerpo: el marco (barra de título,
  // panel de navegación y botón de atrás) lo pone el armazón de go_router.
  Widget _buildDesktop(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(30, 20, 30, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _titulo,
                      style: fluent.FluentTheme.of(context).typography.subtitle,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _contador,
                      style: TextStyle(
                          fontSize: 12, color: HomeTheme.textMuted),
                    ),
                  ],
                ),
              ),
              fluent.Button(
                onPressed: _alternarPausa,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _pausado
                          ? fluent.FluentIcons.play
                          : fluent.FluentIcons.pause,
                      size: 14,
                    ),
                    const SizedBox(width: 8),
                    Text(_pausado
                        ? 'settings.log-resume'.i18n
                        : 'settings.log-pause'.i18n),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              fluent.Button(
                onPressed: _limpiar,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(fluent.FluentIcons.delete, size: 14),
                    const SizedBox(width: 8),
                    Text('common.clear'.i18n),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_pausado) ...[
            _bandaDePausa(),
            _barraDeFiltros(),
            const SizedBox(height: 10),
          ],
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: HomeTheme.cardSurface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: HomeTheme.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  NotificationListener<ScrollNotification>(
                    onNotification: _mirarDesplazamiento,
                    child: _buildLista(),
                  ),
                  if (!_alFinal)
                    Positioned(
                      right: 16,
                      bottom: 16,
                      child: fluent.FilledButton(
                        onPressed: () {
                          setState(() => _alFinal = true);
                          _bajarAlFinal();
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(fluent.FluentIcons.down, size: 12),
                            const SizedBox(width: 8),
                            Text('settings.log-to-bottom'.i18n),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PlatformBuildWidget(
      androidBuilder: _buildAndroid,
      desktopBuilder: _buildDesktop,
    );
  }
}

/// Por qué se filtra el registro.
///
/// No son niveles de gravedad —eso ya lo dice el color— sino ÁREAS: quien abre
/// el registro viene buscando una cosa concreta, y son casi siempre estas
/// cuatro. Filtrar por área es lo que hace utilizable un archivo de miles de
/// líneas en un televisor, donde recorrerlo con el mando no es opción.
enum _Filtro {
  todo('settings.log-filtro-todo'),

  /// Solo lo que salió mal. Es el primer sitio donde mirar.
  fallos('settings.log-filtro-fallos'),

  /// Extensiones y servidores: qué resolvió, cuál falló, cuánto tardó.
  extensiones('settings.log-filtro-extensiones'),

  /// El reproductor: qué decodifica, cuadros perdidos, saltos.
  reproductor('settings.log-filtro-reproductor');

  const _Filtro(this.clave);

  /// La clave de idioma del botón.
  final String clave;

  /// Si una línea entra en este filtro.
  bool acepta(String l) => switch (this) {
        _Filtro.todo => true,
        _Filtro.fallos => l.contains(' SEVERE ') ||
            l.contains(' SHOUT ') ||
            l.contains(' WARNING ') ||
            l.contains('LO ULTIMO QUE HIZO') ||
            l.contains('no se cerro normalmente'),
        // La cabecera de sesión entra en TODOS los filtros: sin ella no se
        // sabría de qué sesión ni de qué aparato son las líneas que quedan.
        _Filtro.extensiones => l.contains('═══') ||
            l.contains('RESULTADO ·') ||
            l.contains('switchServer') ||
            l.contains('[home]') ||
            l.contains('ficha ·') ||
            l.contains('extension') ||
            l.contains('Extension'),
        _Filtro.reproductor => l.contains('═══') ||
            l.contains('medición') ||
            l.contains('rueda') ||
            l.contains('recorte') ||
            l.contains('DECODIFICACIÓN') ||
            l.contains('FRAME LENTO') ||
            l.contains('Pantalla puesta') ||
            l.contains('Dibujado del vídeo') ||
            l.contains('Motor de vídeo'),
      };
}
