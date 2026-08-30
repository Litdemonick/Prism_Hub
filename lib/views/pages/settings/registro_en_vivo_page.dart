import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:prismhub/utils/encabezado_de_sesion.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/sesiones_del_registro.dart';
import 'package:prismhub/views/pages/settings/historial_de_registro_page.dart';
import 'package:prismhub/views/widgets/seleccionable_si_se_puede.dart';
import 'package:prismhub/views/widgets/tv/columna_de_acciones.dart';
import 'package:prismhub/views/widgets/tv/desplazable_con_mando.dart';
import 'package:prismhub/views/widgets/tv/focusable_card.dart';
import 'package:prismhub/utils/exportar_registro.dart';
import 'package:prismhub/utils/log.dart';
import 'package:prismhub/utils/servidor_de_registro.dart';
import 'package:prismhub/utils/zonas_del_registro.dart';
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

  /// Un nodo de foco por zona, fijo.
  ///
  /// ── Por qué uno por zona y no uno que se mueva ──────────────────────────
  ///
  /// Antes había un solo nodo que se le pasaba a la zona elegida. O sea que al
  /// cambiar de zona el nodo cambiaba de tarjeta — y una tarjeta a la que le
  /// sacan el nodo nunca se entera de que perdió el foco, así que se quedaba
  /// encendida. Con tres cambios de zona quedaban tres botones marcados a la
  /// vez, y ahí ya no se sabe cuál se va a activar al pulsar.
  ///
  /// Cada zona tiene el suyo desde el principio y no se lo presta a nadie.
  /// «Volver a la columna» es entonces pedirle el foco al de la zona puesta,
  /// sin mover nada.
  late final List<FocusNode> _focosDeZona = [
    for (final z in ZonaDelRegistro.values)
      FocusNode(debugLabel: 'registro-zona-${z.name}'),
  ];

  /// A dónde salta el foco cuando se pulsa izquierda desde el registro.
  ///
  /// Se lo lleva la zona que esté puesta, no la primera de la lista: quien
  /// vuelve a la columna casi siempre viene a cambiar de zona, y aparecer
  /// justo sobre la actual dice además en cuál estaba.
  FocusNode get _focoDelRail => _focosDeZona[_filtro.index];

  /// Si el foco del mando está sobre el registro.
  ///
  /// Un bloque de texto que se desplaza no puede mostrarlo por su cuenta —no
  /// hay tarjeta que se ilumine— y sin eso, en un televisor, no se sabe si las
  /// flechas van a mover el texto o a saltar a otro botón.
  bool _elRegistroTieneFoco = false;

  /// Cuántas aperturas anteriores hay guardadas, para el botón de historial.
  ///
  /// Se muestra el número a propósito: un botón que a veces lleva a una lista
  /// vacía y a veces no, sin decirlo de antemano, es una pulsación perdida —
  /// y con un control remoto eso se nota.
  int _cuantasAnteriores = 0;

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
    // ── Primero se abre la pantalla; después se lee el archivo ──────────
    //
    // Reportado en vivo: «la primera vez entra bien, salgo y entro otra vez y
    // se peta, carga lento y luego entra». Encaja con lo que hace esto: en la
    // primera visita el archivo estaba casi vacío, y en la segunda ya trae la
    // sesión anterior entera.
    //
    // Leer y partir en líneas es trabajo del hilo de la interfaz, y arrancaba
    // en el mismo cuadro en que empieza la animación de entrada. En un
    // televisor eso son varios cuadros perdidos encima de la transición, que
    // es justo donde más se notan.
    //
    // Ahora se espera a que la transición termine. La pantalla entra vacía y
    // fluida, y el historial aparece un instante después — que es el orden
    // correcto: lo primero es que la pantalla responda.
    _refrescar();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final animacion = ModalRoute.of(context)?.animation;
      if (animacion == null || animacion.isCompleted) {
        unawaited(_leerLoAnterior());
        return;
      }
      void alTerminar(AnimationStatus estado) {
        if (estado != AnimationStatus.completed) return;
        animacion.removeStatusListener(alTerminar);
        if (mounted) unawaited(_leerLoAnterior());
      }

      animacion.addStatusListener(alTerminar);
    });
    _reloj = Timer.periodic(_cadencia, (_) => _refrescar());
  }

  Future<void> _leerLoAnterior() async {
    try {
      final archivo = File(PrismLog.logFilePath);
      if (!await archivo.exists()) return;
      final texto = await _colaDelArchivo(archivo);
      final todas = const LineSplitter()
          .convert(texto)
          .where((l) => l.trim().isNotEmpty)
          .toList(growable: false);
      // Solo el final. Un archivo de sesiones enteras puede tener decenas de
      // miles de líneas, y construirlas todas es justo lo que no hay que
      // hacer en un televisor.
      final desde = todas.length > _topeDeLoAnterior
          ? todas.length - _topeDeLoAnterior
          : 0;
      if (!mounted) return;
      // ── Solo la sesión de ahora ───────────────────────────────────────
      //
      // Reportado en vivo: «veo que ya contiene cosas y nunca comienza desde
      // cero», «siempre al cerrar y abrir el app». El archivo es acumulativo
      // y el visor lo mostraba entero, así que al abrirlo ya venía con lo de
      // ayer pegado arriba y no había forma de ver dónde empezaba lo de
      // recién.
      //
      // Ahora acá entra solo la última apertura, que arranca con la
      // presentación. Lo anterior no se pierde: está en «Historial», ordenado
      // por fecha y hora.
      final sesiones = partirEnSesiones(todas.sublist(desde));
      setState(() {
        _deAntes = sesiones.isEmpty ? const [] : sesiones.last.lineas;
        _cuantasAnteriores = sesiones.isEmpty ? 0 : sesiones.length - 1;
        _recalcularVisibles();
      });
      if (_alFinal) _bajarAlFinal();
    } catch (e) {
      // Sin permiso, o el archivo a medio escribir: se sigue con lo que haya
      // en memoria, que es como se comportaba antes.
      debugPrint('No se pudo leer el registro anterior: $e');
    }
  }

  /// El último tramo del archivo, sin traer el resto a memoria.
  ///
  /// El registro se recorta solo a 10 MB (ver `PrismLog._recortar`), así que
  /// `readAsString()` podía cargar diez megas y partirlos en cien mil líneas
  /// para quedarse con las últimas tres mil. En un PC no se nota; en un
  /// televisor es el congelamiento al entrar.
  ///
  /// Se lee desde el final con posicionamiento directo, y se descarta lo que
  /// haya antes del primer salto de línea para no empezar con media línea
  /// cortada, que en pantalla se ve como basura.
  static Future<String> _colaDelArchivo(File archivo) async {
    final largo = await archivo.length();
    if (largo <= _bytesDeCola) return archivo.readAsString();
    final mango = await archivo.open();
    try {
      await mango.setPosition(largo - _bytesDeCola);
      final bytes = await mango.read(_bytesDeCola);
      // allowMalformed: el corte cae en cualquier byte, y bien puede partir
      // un carácter de varios bytes por la mitad. Sin esto, el primer
      // carácter roto tiraría toda la lectura.
      final texto = utf8.decode(bytes, allowMalformed: true);
      final corte = texto.indexOf(String.fromCharCode(10));
      return corte < 0 ? texto : texto.substring(corte + 1);
    } finally {
      await mango.close();
    }
  }

  /// Cuánto se lee del final del archivo.
  ///
  /// A ojo, unas seis mil líneas: de sobra para las tres mil que se
  /// conservan, con margen para las que se descarten por vacías.
  static const _bytesDeCola = 700 * 1024;

  /// Cuántas líneas del archivo se traen.
  ///
  /// Bastante más que las que caben en pantalla, para poder subir a ver qué
  /// pasó antes de un cierre, pero acotado: son widgets que hay que construir.
  static const _topeDeLoAnterior = 3000;

  @override
  void dispose() {
    _reloj?.cancel();
    _scroll.dispose();
    for (final f in _focosDeZona) {
      f.dispose();
    }
    super.dispose();
  }

  void _refrescar() {
    if (_pausado || !mounted) return;
    // ── Leyendo hacia arriba, la lista NO se toca ────────────────────────
    //
    // Reportado en vivo: subiendo con el mando «se repite en vez de llegar al
    // tope». La causa: lo que hay en memoria es un buffer rodante de 1.500
    // líneas, así que mientras llegan líneas nuevas por abajo se van BORRANDO
    // por arriba. Con la vista quieta a mitad de camino, el contenido se corre
    // solo bajo el desplazamiento — lo que se estaba leyendo se va hacia
    // arriba y aparece otra cosa en su lugar. Desde afuera se ve como que el
    // texto se repite y nunca llega al principio.
    //
    // Mientras se está leyendo hacia atrás la lista se queda como está. Al
    // volver al fondo se retoma sola, que es donde el seguimiento en vivo sí
    // es lo que se quiere.
    if (!_alFinal) return;
    final generacion = PrismLog.generacion;
    if (generacion == _generacion) return;
    setState(() {
      _generacion = generacion;
      _lineas = PrismLog.enMemoria;
      _recalcularVisibles();
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

  /// Enciende o apaga el servidor que deja leer el registro desde otro
  /// aparato, y muestra la dirección en grande.
  Future<void> _alternarServidor() async {
    if (ServidorDeRegistro.encendido) {
      // Se pregunta antes de cortar.
      //
      // El mismo botón enciende y apaga, así que con la conexión activa una
      // pulsación de más la corta — y del otro lado hay alguien mirando el
      // registro en un navegador, que se queda sin nada sin entender por qué.
      // Volver a levantarla no es gratis: cambia el código de la dirección y
      // hay que escribirla de nuevo entera.
      if (!await _confirmar(
        titulo: 'settings.log-en-red-cortar'.i18n,
        detalle: 'settings.log-en-red-cortar-detalle'.i18n,
      )) {
        return;
      }
      await ServidorDeRegistro.apagar();
      if (mounted) setState(() {});
      return;
    }
    ServidorDeRegistro.areaElegida = _filtro.area;
    ServidorDeRegistro.lineasFijas = null;
    final r = await ServidorDeRegistro.encender();
    if (!mounted) return;
    setState(() {});
    if (r.direccion == null) {
      // Cada fallo lleva a un arreglo distinto, así que se dice cuál fue en
      // vez de un «no se pudo» que deja a oscuras.
      showPlatformSnackbar(
        context: context,
        content: switch (r.fallo) {
          FalloDeServidor.sinRed => 'settings.log-en-red-sin-red'.i18n,
          FalloDeServidor.noSePudo => 'settings.log-en-red-bloqueado'.i18n,
          _ => 'settings.log-en-red-sin-red'.i18n,
        },
      );
      return;
    }
    final direccion = r.direccion!;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: HomeTheme.cardSurface,
        title: Text('settings.log-en-red'.i18n,
            style: TextStyle(color: HomeTheme.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'settings.log-en-red-como'.i18n,
              style: TextStyle(color: HomeTheme.textMuted, fontSize: 14),
            ),
            const SizedBox(height: 18),
            // Grande y monoespaciada: hay que copiarla mirando la pantalla
            // desde el sillón y escribirla en otro aparato, así que cada
            // carácter tiene que leerse sin dudar.
            SelectableText(
              direccion,
              style: TextStyle(
                fontFamily: 'monospace',
                fontFamilyFallback: const ['Consolas', 'Courier New'],
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: HomeTheme.accentPink,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'settings.log-en-red-aviso'.i18n,
              style: TextStyle(color: HomeTheme.textMuted, fontSize: 13),
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

  void _alternarPausa() {
    setState(() => _pausado = !_pausado);
    // Al reanudar se muestra YA lo que se acumuló mientras estuvo en pausa, sin
    // esperar el siguiente tic.
    if (!_pausado) _refrescar();
  }

  /// Vacía la sesión de ahora y la deja empezada de nuevo.
  ///
  /// ── Qué se lleva y qué no ───────────────────────────────────────────────
  ///
  /// **El historial NO se toca.** Pedido explícito: «el historial no se
  /// limpia, siempre se guarda la info». Y es lo correcto de fondo — las
  /// aperturas anteriores son lo que explica un cierre, así que un botón que
  /// se las llevara de paso destruiría justo lo que sirve para arreglar el
  /// problema que llevó a apretarlo.
  ///
  /// **Se limpia la zona que se esté mirando.** En «Todo» se va todo lo de
  /// esta sesión; en «Reproductor» se va solo eso y lo de las extensiones
  /// queda. Quien limpia ruido de una prueba no quiere perder lo que ni
  /// estaba viendo.
  ///
  /// **Y no queda en blanco**: se vuelve a escribir la presentación, así que
  /// la pantalla queda como recién abierta —con el nombre, qué es esto y de
  /// qué aparato se trata— en vez de un vacío que se lee igual que un fallo.
  ///
  /// Pregunta antes, porque no se puede deshacer.
  Future<void> _limpiar() async {
    final zona = _filtro == ZonaDelRegistro.todo ? null : _filtro.clave.i18n;
    if (!await _confirmar(
      titulo: 'settings.log-limpiar'.i18n,
      detalle: zona == null
          ? 'settings.log-limpiar-todo'.i18n
          : FlutterI18n.translate(
              context,
              'settings.log-limpiar-zona',
              translationParams: {'zona': zona},
            ),
    )) {
      return;
    }
    try {
      final version = await _version();
      await PrismLog.limpiarSesionActual(
        // En «Todo» no sobrevive nada; en una zona concreta sobrevive todo lo
        // que NO sea de esa zona.
        dejar: _filtro == ZonaDelRegistro.todo ? null : (l) => !_filtro.seVe(l),
        escribirCabecera: () => EncabezadoDeSesion.escribir(version: version),
      );
    } catch (e) {
      if (!mounted) return;
      showPlatformSnackbar(
        context: context,
        content: FlutterI18n.translate(
          context,
          'settings.log-clear-error',
          translationParams: {'error': '$e'},
        ),
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _generacion = PrismLog.generacion;
      _lineas = PrismLog.enMemoria;
      // Lo leído del archivo se descarta: el archivo acaba de cambiar debajo,
      // así que lo que había en pantalla ya no se corresponde con él. Se
      // vuelve a leer, que además recuenta las aperturas anteriores.
      _deAntes = const [];
      _alFinal = true;
      _recalcularVisibles();
    });
    unawaited(_leerLoAnterior());
    showPlatformSnackbar(
      context: context,
      content: zona == null
          ? 'settings.log-cleared'.i18n
          : FlutterI18n.translate(
              context,
              'settings.log-cleared-zona',
              translationParams: {'zona': zona},
            ),
    );
  }

  /// La versión que se escribe en la cabecera al limpiar.
  ///
  /// Se pregunta en el momento y no se guarda: pasa una vez, cuando alguien
  /// aprieta un botón, y tener el dato colgando de la pantalla es una copia
  /// más que mantener al día.
  static Future<String> _version() async {
    try {
      return (await PackageInfo.fromPlatform()).version;
    } catch (_) {
      return '';
    }
  }

  /// Un sí o no, con los botones grandes para un control remoto.
  ///
  /// Cancelar toma el foco al abrir: si alguien llegó acá de más, la
  /// pulsación que hace por costumbre es la que NO rompe nada.
  Future<bool> _confirmar({
    required String titulo,
    required String detalle,
  }) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: HomeTheme.bg,
        title: Text(titulo, style: TextStyle(color: HomeTheme.textPrimary)),
        content: Text(
          detalle,
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
    return r ?? false;
  }

  /// Exporta lo que se está mirando, diciendo si algo salió mal.
  ///
  /// Antes se llamaba al exportador directamente y un fallo —sin permiso de
  /// escritura, disco lleno, el menú de compartir que no abre— se perdía sin
  /// que nadie se enterara: el botón se apretaba y no pasaba nada, que es la
  /// peor forma de fallar porque no da ninguna pista de qué hacer.
  Future<void> _exportar() async {
    try {
      final salio = await ExportarRegistro.entregar(
        soloArea: _filtro.area,
        etiqueta: _filtro.name,
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

  /// Abre el historial de aperturas anteriores.
  Future<void> _verHistorial() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const HistorialDeRegistroPage(),
      ),
    );
    // Al volver, el servidor de red puede haber quedado sirviendo una sesión
    // concreta. Acá se mira lo de ahora, así que se le saca esa atadura.
    ServidorDeRegistro.lineasFijas = null;
    if (mounted) setState(() {});
  }

  String get _titulo => 'settings.view-log'.i18n;

  /// Cuántas líneas hay a la vista.
  ///
  /// Cuenta las FILTRADAS, no las que hay en total. Contaba el total, así que
  /// el número no se movía al cambiar de zona: decía «2.560 líneas» tanto en
  /// «Todo» como en «Fallos», donde había doscientas. Un número que no
  /// responde a lo que uno acaba de tocar se lee como que el filtro no hizo
  /// nada.
  ///
  /// Se recalcula solo, porque [_visibles] cambia con cada línea nueva y con
  /// cada cambio de zona.
  String get _contador => FlutterI18n.translate(
        context,
        'settings.log-lines',
        translationParams: {'n': '$_cuantasVisibles'},
      );

  // Los avisos del propio registro llevan color: en una pared de texto gris,
  // encontrar el error a ojo es justamente lo que uno vino a hacer acá.
  Color _colorDe(String linea) => colorDeLinea(linea);

  /// Por qué categoría se está mirando el registro.
  ///
  /// Un archivo de varias sesiones son miles de líneas, y quien lo abre viene
  /// buscando UNA cosa: por qué falló una extensión, por qué se cerró la app,
  /// o qué hizo el reproductor. Recorrerlo entero con el mando para encontrar
  /// eso es lo que lo vuelve inútil en un televisor.
  ZonaDelRegistro _filtro = ZonaDelRegistro.todo;

  /// Las líneas que se están mostrando, ya filtradas.
  ///
  /// ── Por qué se guarda y no se calcula al construir ──────────────────────
  ///
  /// Antes se armaba en cada `build`: juntar el historial con lo de memoria
  /// —hasta 4.500 líneas— y recorrerlas todas aplicando el filtro. Y `build`
  /// corre cuatro veces por segundo mientras entran líneas, más una vez por
  /// cada aviso de desplazamiento. En un televisor eso es un tirón constante
  /// justo mientras se intenta leer.
  ///
  /// Ahora se recalcula solo cuando cambia algo que lo afecta: líneas nuevas,
  /// el historial recién leído, o el filtro.
  List<String> _visibles = const [];

  /// Cuántas líneas hay a la vista, sin agrupar. Ver [_recalcularVisibles].
  int _cuantasVisibles = 0;

  void _recalcularVisibles() {
    final todas = _deAntes.isEmpty
        ? _lineas
        : <String>[..._deAntes, ..._lineas.skip(_dondeSigueLaMemoria())];
    final filtradas = _filtro == ZonaDelRegistro.todo
        ? todas
        : todas.where(_filtro.seVe).toList(growable: false);
    // Se cuenta ANTES de agrupar: agrupar junta las treinta líneas del
    // recuadro en una sola pieza para poder dibujarlo, y si se contara después
    // el número diría treinta menos de las que hay de verdad.
    _cuantasVisibles = filtradas.length;
    _visibles = agruparElRecuadro(filtradas);
  }

  /// Desde qué línea de la memoria hay que seguir, para no repetir.
  ///
  /// ── El solapamiento ─────────────────────────────────────────────────────
  ///
  /// Las dos fuentes se pisan. El archivo se escribe en tandas cada dos
  /// segundos, así que todo lo que hay en memoria ya está también en el
  /// archivo — y al juntar «lo de antes» con «lo de ahora» sin más, el tramo
  /// compartido salía dos veces. Reportado en vivo: «no duplicaciones, veo
  /// que ya contiene cosas».
  ///
  /// El archivo NO se vuelve a leer (solo crece por el final, y ese final es
  /// justo lo que la memoria ya trae), así que lo correcto es lo que dice el
  /// usuario: agregar, no volver a empezar. Se busca dónde termina lo leído
  /// del archivo dentro de la memoria y se sigue desde la línea siguiente.
  ///
  /// ── Por qué se compara un tramo y no una línea ──────────────────────────
  ///
  /// Una sola línea puede repetirse tal cual (un reintento, un aviso que
  /// vuelve), y cortar en la coincidencia equivocada se comería líneas
  /// buenas. Con las últimas del archivo en fila, una coincidencia falsa deja
  /// de ser realista.
  ///
  /// Si no se encuentra nada, la memoria ya dejó atrás lo que se leyó del
  /// archivo —el buffer va rotando y descarta por delante— así que todo lo
  /// que hay en memoria es posterior y entra entero.
  int _dondeSigueLaMemoria() {
    if (_deAntes.isEmpty || _lineas.isEmpty) return 0;
    final cuantas = _deAntes.length < 4 ? _deAntes.length : 4;
    final cola = _deAntes.sublist(_deAntes.length - cuantas);
    // De atrás hacia adelante: interesa la coincidencia MÁS reciente, que es
    // donde de verdad termina lo ya mostrado.
    for (var i = _lineas.length - cola.length; i >= 0; i--) {
      var igual = true;
      for (var j = 0; j < cola.length; j++) {
        if (_lineas[i + j] != cola[j]) {
          igual = false;
          break;
        }
      }
      if (igual) return i + cola.length;
    }
    return 0;
  }

  /// Cambia el filtro y deja todo lo demás mirando lo mismo.
  void _elegirFiltro(ZonaDelRegistro f) {
    setState(() {
      _filtro = f;
      _recalcularVisibles();
      // El que esté mirando desde el navegador ve el mismo cambio en cinco
      // segundos, sin tocar nada de su lado.
      ServidorDeRegistro.areaElegida = f.area;
    });
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

  /// La misma, algo más grande: un televisor se mira desde tres metros y a
  /// 11,5 puntos el registro no se lee, se adivina.
  static final _monoDeTelevisor = _mono.copyWith(fontSize: 13.5);

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
          for (final f in ZonaDelRegistro.values)
            Padding(
              // Con clave por el mismo motivo que en la columna del
              // televisor: que el estado de cada pastilla siga a su zona y no
              // al lugar que ocupa. Acá la lista no cambia de largo hoy, pero
              // el día que cambie el fallo sería invisible.
              key: ValueKey(f.name),
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: FocusableCard(
                  borderRadius: 999,
                  onTap: () => _elegirFiltro(f),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    padding: EdgeInsets.symmetric(
                      horizontal: tv ? 20 : 14,
                      vertical: tv ? 10 : 7,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: _filtro == f
                          ? Color.alphaBlend(
                              HomeTheme.accentPink.withValues(alpha: 0.22),
                              HomeTheme.bg,
                            )
                          : _superficie,
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

  Widget _buildLista({
    bool paraTelevisor = false,
    VoidCallback? alIrIzquierda,
  }) {
    final visibles = _visibles;
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

    // Envuelto y no con un SelectableText por línea: así se puede arrastrar y
    // copiar un tramo entero (un stack trace completo, por ejemplo) para
    // pegarlo en un reporte, en vez de línea por línea. Y solo en escritorio
    // — ver SeleccionableSiSePuede, que explica el fallo que evita.
    return DesplazableConMando(
      controlador: _scroll,
      alCambiarFoco: paraTelevisor
          ? (tiene) {
              if (!mounted) return;
              setState(() => _elRegistroTieneFoco = tiene);
            }
          : null,
      alIrIzquierda: alIrIzquierda,
      child: SeleccionableSiSePuede(
        child: ListView.builder(
          controller: _scroll,
          padding: paraTelevisor
              ? const EdgeInsets.fromLTRB(18, 14, 18, 24)
              : const EdgeInsets.fromLTRB(12, 8, 12, 24),
          itemCount: visibles.length,
          itemBuilder: (context, index) {
            final linea = visibles[index];
            final estilo = (paraTelevisor ? _monoDeTelevisor : _mono)
                .copyWith(color: _colorDe(linea));
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: esElRecuadro(linea)
                  ? _recuadroCompleto(linea, estilo)
                  : Text(linea, style: estilo),
            );
          },
        ),
      ),
    );
  }

  /// El recuadro de presentación, entero y sin cortarse.
  ///
  /// ── Por qué necesita trato aparte ───────────────────────────────────────
  ///
  /// Es dibujo hecho con caracteres: solo se entiende si todas sus líneas
  /// quedan alineadas y ninguna se parte. Como cualquier otra línea del
  /// registro, se le aplicaba el ajuste de texto normal — así que en cuanto
  /// no entraba a lo ancho, las líneas largas se partían en dos y el recuadro
  /// se veía roto. Reportado en vivo: «el prism, el unicode, se corta».
  ///
  /// Se dibuja como UNA sola pieza que se achica hasta entrar. Que sea una
  /// sola importa: si cada línea se escalara por su cuenta, cada una quedaría
  /// de un tamaño distinto y el dibujo se desarmaría igual. Y no se agranda
  /// nunca —solo se reduce— para que en una pantalla ancha se lea al mismo
  /// tamaño que el resto del registro.
  Widget _recuadroCompleto(String bloque, TextStyle estilo) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(bloque, style: estilo, softWrap: false),
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
        // Con la zona adelante: pausado en «Fallos» y pausado en «Todo» se
        // veían igual, y son cosas distintas — en una faltan líneas porque el
        // filtro las saca y en la otra porque la vista está congelada.
        _filtro == ZonaDelRegistro.todo
            ? 'settings.log-paused-hint'.i18n
            : '${_filtro.clave.i18n} · ${'settings.log-paused-hint'.i18n}',
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
        // Se encoge antes que cortarse.
        //
        // Con cinco botones al lado, en un teléfono angosto no quedaba ancho
        // para el título y salía «Ver registro…». Reportado en vivo. Bajar un
        // punto o dos de tamaño lo entra entero, y se lee igual.
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            _titulo,
            maxLines: 1,
            style: TextStyle(color: HomeTheme.textPrimary),
          ),
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
          // Exportar desde acá y no solo desde Ajustes: quien está mirando
          // el registro porque algo falló ya está en la pantalla correcta —
          // mandarlo a volver atrás para encontrar el botón es un rodeo.
          //
          // En televisor no aparece: ahí no hay a dónde exportar ni con qué
          // abrir el archivo.
          if (!PlatformTv.esTelevisionSync)
            IconButton(
              tooltip: 'common.export'.i18n,
              icon: const Icon(Icons.ios_share),
              color: HomeTheme.textPrimary,
              onPressed: _exportar,
            ),
          // En televisor, en vez de exportar: leerlo desde otro aparato de la
          // red. Ver ServidorDeRegistro.
          if (PlatformTv.esTelevisionSync)
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
          IconButton(
            tooltip: _etiquetaDeHistorial,
            icon: const Icon(Icons.history),
            color: HomeTheme.textPrimary,
            onPressed: _verHistorial,
          ),
          IconButton(
            tooltip: 'common.clear'.i18n,
            icon: const Icon(Icons.delete_outline),
            color: HomeTheme.textPrimary,
            onPressed: _limpiar,
          ),
        ],
      ),
      // SafeArea con los lados puestos.
      //
      // El Scaffold ya aparta la barra de estado de arriba, pero no los lados
      // — y apaisado, el recorte de cámara y la barra de gestos se comen texto
      // en el borde. Reportado en vivo: «agregale safearea en modo horizontal
      // en celulares». Arriba va en false: de eso ya se ocupó la barra, y
      // ponerlo dos veces deja un hueco.
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (_pausado) _bandaDePausa(),
            _barraDeFiltros(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _contador,
                  style: TextStyle(fontSize: 12, color: HomeTheme.textMuted),
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
                      style:
                          TextStyle(fontSize: 12, color: HomeTheme.textMuted),
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
                onPressed: _verHistorial,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(fluent.FluentIcons.history, size: 14),
                    const SizedBox(width: 8),
                    Text(_etiquetaDeHistorial),
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
            const SizedBox(height: 10),
          ],
          // FUERA del bloque de pausa: la barra de filtros va siempre.
          // Metida ahí adentro solo aparecía con el registro pausado, que es
          // justo cuando menos falta hace — filtrar sirve mientras se está
          // buscando algo, no cuando se congeló la vista.
          _barraDeFiltros(),
          const SizedBox(height: 10),
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

  // ══ TELEVISOR ═══════════════════════════════════════════════════════════
  //
  // ── Por qué no alcanzaba con la pantalla de Android ────────────────────
  //
  // Reportado en vivo, tres cosas a la vez: «es difícil subir todo eso para
  // tocar los botones de arriba», «al scrollear presionando se para» y «no se
  // ve dónde estoy seleccionando». Las tres salen de lo mismo — una pantalla
  // pensada para el dedo, usada con un mando.
  //
  // Con el dedo, los botones de la barra superior están siempre ahí. Con un
  // mando hay que LLEGAR hasta ellos, y desde el medio de un registro de tres
  // mil líneas eso son cientos de pulsaciones hacia arriba. Un botón que
  // existe pero al que no se puede llegar es lo mismo que no tenerlo.
  //
  // ── La disposición ─────────────────────────────────────────────────────
  //
  // Los mandos a distancia están hechos para moverse en cruz, así que las
  // acciones van en una columna al costado: desde cualquier punto del
  // registro, IZQUIERDA salta directo a ellas — sin importar por dónde vaya
  // el desplazamiento— y DERECHA vuelve al texto. Todo a una pulsación.
  //
  // Y cada cosa que se puede elegir se ilumina al tener el foco, incluido el
  // propio registro, que al ser una pared de texto no tenía forma de decir
  // que estaba seleccionado.
  Widget _buildTelevisor(BuildContext context) {
    return Scaffold(
      backgroundColor: HomeTheme.bg,
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _railDeTelevisor(),
            Expanded(child: _panelDeTelevisor()),
          ],
        ),
      ),
    );
  }

  Widget _railDeTelevisor() {
    return ColumnaDeAcciones(
      titulo: _titulo,
      detalle: _contador,
      grupos: [
        GrupoDeColumna(
          titulo: 'settings.log-zona'.i18n,
          opciones: [
            for (final f in ZonaDelRegistro.values)
              OpcionDeColumna(
                texto: f.clave.i18n,
                elegido: _filtro == f,
                onTap: () => _elegirFiltro(f),
                foco: _focosDeZona[f.index],
              ),
          ],
        ),
        GrupoDeColumna(
          titulo: 'settings.log-acciones'.i18n,
          opciones: [
            OpcionDeColumna(
              id: 'pausa',
              icono: _pausado ? Icons.play_arrow : Icons.pause,
              texto: _pausado
                  ? 'settings.log-resume'.i18n
                  : 'settings.log-pause'.i18n,
              elegido: _pausado,
              onTap: _alternarPausa,
            ),
            // Solo aparece cuando la vista se fue del fondo: un botón que no
            // hace nada, en una columna que se recorre botón por botón, es
            // una pulsación tirada cada vez que se pasa por encima.
            if (!_alFinal)
              OpcionDeColumna(
                icono: Icons.arrow_downward,
                texto: 'settings.log-to-bottom'.i18n,
                onTap: () {
                  setState(() => _alFinal = true);
                  _bajarAlFinal();
                },
              ),
            OpcionDeColumna(
              id: 'historial',
              icono: Icons.history,
              texto: _etiquetaDeHistorial,
              onTap: _verHistorial,
            ),
            OpcionDeColumna(
              id: 'red',
              icono: ServidorDeRegistro.encendido
                  ? Icons.wifi_tethering
                  : Icons.wifi_tethering_off,
              texto: 'settings.log-en-red'.i18n,
              elegido: ServidorDeRegistro.encendido,
              onTap: _alternarServidor,
            ),
            OpcionDeColumna(
              icono: Icons.delete_outline,
              texto: 'common.clear'.i18n,
              onTap: _limpiar,
            ),
          ],
        ),
        // Salir, en su propio grupo y al final.
        //
        // En un televisor el botón de atrás del mando existe, pero no todos
        // los mandos lo traen en un sitio evidente —y en algunos cajones ni
        // siquiera está— así que una pantalla sin salida visible es una
        // pantalla de la que se sale apagando el aparato. Va último porque es
        // lo que menos se usa: bajando se llega a todo lo demás primero.
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
    );
  }

  /// «Historial», con cuántas aperturas anteriores hay detrás.
  ///
  /// El número va en el propio botón porque el resultado de apretarlo depende
  /// de él: sin nada guardado lleva a una pantalla vacía, y con un control
  /// remoto eso son cuatro pulsaciones —entrar, ver que no hay nada, volver—
  /// que se evitan sabiéndolo antes.
  String get _etiquetaDeHistorial {
    final base = 'settings.log-historial'.i18n;
    return _cuantasAnteriores > 0 ? '$base ($_cuantasAnteriores)' : base;
  }

  /// El registro, con un borde que se enciende cuando tiene el foco.
  Widget _panelDeTelevisor() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_pausado) ...[
            _bandaDePausa(),
            const SizedBox(height: 10),
          ],
          Expanded(
            child: PanelDeTelevisor(
              tieneFoco: _elRegistroTieneFoco,
              child: NotificationListener<ScrollNotification>(
                onNotification: _mirarDesplazamiento,
                child: _buildLista(
                  paraTelevisor: true,
                  alIrIzquierda: () => _focoDelRail.requestFocus(),
                ),
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
      androidBuilder: (context) => PlatformTv.esTelevisionSync
          ? _buildTelevisor(context)
          : _buildAndroid(context),
      desktopBuilder: _buildDesktop,
    );
  }
}

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
