import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:prismhub/utils/exportar_registro.dart';
import 'package:prismhub/utils/anuncio_de_registro.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/registro_guardado_de_otro.dart';
import 'package:prismhub/utils/zonas_del_registro.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/messenger.dart';
import 'package:prismhub/views/widgets/seleccionable_si_se_puede.dart';
import 'package:prismhub/views/widgets/tv/focusable_card.dart';
import 'package:url_launcher/url_launcher.dart';

/// Busca televisores con el registro abierto y lo muestra, sin escribir nada.
///
/// ── Por qué ─────────────────────────────────────────────────────────────────
///
/// El televisor podía compartir su registro, pero del otro lado había que leer
/// una dirección de la pantalla y escribirla a mano en el navegador. Se acortó
/// todo lo que se pudo y sigue siendo escribir una IP mirando de lejos.
///
/// Acá no hace falta: se pregunta a la red quién tiene el registro abierto, se
/// muestra lo que conteste y se abre de un toque. Ver [AnuncioDeRegistro].
///
/// ── Por qué dentro de la app y no en el navegador ───────────────────────────
///
/// Se podría abrir la dirección en el navegador del sistema y listo. Pero
/// entonces hay que salir de la app, y lo que se ve es una página pelada sin
/// los colores ni los filtros que ya tiene el visor de acá. Trayendo el texto y
/// mostrándolo con el mismo aspecto, leer el registro de otro aparato se
/// parece a leer el propio.
class RegistroDeOtroAparatoPage extends StatefulWidget {
  const RegistroDeOtroAparatoPage({super.key});

  @override
  State<RegistroDeOtroAparatoPage> createState() =>
      _RegistroDeOtroAparatoPageState();
}

class _RegistroDeOtroAparatoPageState
    extends State<RegistroDeOtroAparatoPage> {
  /// Los que están contestando ahora mismo.
  List<TelevisorConocido> _enLinea = const [];

  /// Los que compartieron alguna vez y ahora no contestan.
  ///
  /// ── Por qué se muestran igual ───────────────────────────────────────────
  ///
  /// Un televisor deja de contestar por tres motivos que desde acá se ven
  /// idénticos: se apagó el servidor a mano, se cumplieron los tres cuartos de
  /// hora, o la app se cayó. Sin mostrarlos, los tres se leen como «acá nunca
  /// hubo nada» — y el tercero es justamente el caso en el que uno estaba
  /// mirando.
  ///
  /// Se quedan apagados y aparte, con su dirección y con cuándo se los vio por
  /// última vez. Se pueden abrir igual por si volvieron.
  List<TelevisorConocido> _sinConexion = const [];

  bool _buscando = true;

  @override
  void initState() {
    super.initState();
    // Lo conocido se muestra YA, antes de buscar.
    //
    // Buscar tarda un par de segundos, y arrancar con la pantalla vacía hace
    // creer que no hay nada — justo lo contrario de lo que se quiere cuando el
    // televisor se cayó y uno viene a ver por qué.
    _sinConexion = TelevisoresConocidos.leer();
    // La búsqueda arranca DESPUÉS de la animación de entrada: abre un socket,
    // manda mensajes a toda la red y arma un temporizador, y todo eso en el
    // mismo cuadro en que la pantalla entra deslizándose cuesta un cuadro —
    // que es el parpadeo.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final animacion = ModalRoute.of(context)?.animation;
      if (animacion == null || animacion.isCompleted) {
        unawaited(_buscar());
        return;
      }
      void alTerminar(AnimationStatus estado) {
        if (estado != AnimationStatus.completed) return;
        animacion.removeStatusListener(alTerminar);
        if (mounted) unawaited(_buscar());
      }

      animacion.addStatusListener(alTerminar);
    });
  }

  Future<void> _buscar() async {
    setState(() => _buscando = true);
    final hallazgos = await AnuncioDeRegistro.buscar();
    await TelevisoresConocidos.anotar(hallazgos);
    if (!mounted) return;
    final vivos = {for (final h in hallazgos) h.url};
    final ahora = DateTime.now();
    setState(() {
      _enLinea = [
        for (final h in hallazgos)
          TelevisorConocido(aparato: h.aparato, url: h.url, visto: ahora),
      ];
      _sinConexion = [
        for (final t in TelevisoresConocidos.leer())
          if (!vivos.contains(t.url)) t,
      ];
      _buscando = false;
    });
  }

  Future<void> _olvidarLosCaidos() async {
    if (!await _confirmar(
      'settings.log-olvidar'.i18n,
      'settings.log-olvidar-detalle'.i18n,
    )) {
      return;
    }
    // Y también el registro que se guardó de cada uno. Olvidar a medias
    // —sacarlo de la lista pero dejar su registro en el disco— no es lo que
    // pidió quien tocó «olvidar».
    for (final t in _sinConexion) {
      await RegistroGuardadoDeOtro.olvidar(t.url);
    }
    await TelevisoresConocidos.olvidar();
    // Los que están en línea se vuelven a anotar enseguida: lo que se olvida
    // de verdad es lo que ya no contesta.
    await TelevisoresConocidos.anotar(
      [for (final t in _enLinea) (aparato: t.aparato, url: t.url)],
    );
    if (!mounted) return;
    setState(() => _sinConexion = const []);
  }

  Future<bool> _confirmar(String titulo, String detalle) async {
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
              'common.delete'.i18n,
              style: TextStyle(color: HomeTheme.accentRed),
            ),
          ),
        ],
      ),
    );
    return r ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HomeTheme.bg,
      appBar: AppBar(
        backgroundColor: HomeTheme.bg,
        title: Text(
          'settings.log-buscar'.i18n,
          style: TextStyle(color: HomeTheme.textPrimary),
        ),
        actions: [
          if (_sinConexion.isNotEmpty)
            IconButton(
              tooltip: 'settings.log-olvidar'.i18n,
              icon: const Icon(Icons.delete_sweep_outlined),
              color: HomeTheme.textMuted,
              onPressed: _olvidarLosCaidos,
            ),
          IconButton(
            tooltip: 'common.refresh'.i18n,
            icon: _buscando
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: HomeTheme.textPrimary,
                    ),
                  )
                : const Icon(Icons.refresh),
            color: HomeTheme.textPrimary,
            onPressed: _buscando ? null : _buscar,
          ),
        ],
      ),
      // ColoredBox además del `backgroundColor` del Scaffold: durante la
      // transición, lo que se ve por debajo es el fondo del tema de Material,
      // que en esta app no es el mismo. Pintarlo acá hace que el primer cuadro
      // ya salga del color correcto.
      //
      // Y el ancho se acota y se centra: en un PC a pantalla completa, o en una
      // tablet apaisada, una tarjeta de punta a punta deja el nombre pegado a
      // un borde y la flecha al otro, con medio metro de nada en medio.
      body: ColoredBox(
        color: HomeTheme.bg,
        child: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: _cuerpo(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cuerpo() {
    final hayAlgo = _enLinea.isNotEmpty || _sinConexion.isNotEmpty;
    if (_buscando && !hayAlgo) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 18),
            Text(
              'settings.log-buscando'.i18n,
              style: TextStyle(color: HomeTheme.textMuted, fontSize: 13),
            ),
          ],
        ),
      );
    }
    if (!hayAlgo) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_find, size: 44, color: HomeTheme.textMuted),
              const SizedBox(height: 16),
              Text(
                'settings.log-nada-en-la-red'.i18n,
                textAlign: TextAlign.center,
                style: TextStyle(color: HomeTheme.textMuted, fontSize: 14),
              ),
              const SizedBox(height: 20),
              // Un botón acá abajo además del de la barra: en un teléfono
              // grande el de arriba queda lejos del pulgar, y volver a buscar
              // es justo lo que uno quiere hacer al leer este mensaje.
              FilledButton.icon(
                onPressed: _buscar,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text('common.retry'.i18n),
              ),
            ],
          ),
        ),
      );
    }
    final filas = <Widget>[
      if (_enLinea.isNotEmpty) _rotulo('settings.log-en-linea'.i18n),
      for (final e in _enLinea) _tarjeta(e, activo: true),
      if (_sinConexion.isNotEmpty) ...[
        const SizedBox(height: 8),
        _rotulo('settings.log-sin-conexion'.i18n),
        for (final e in _sinConexion) _tarjeta(e, activo: false),
      ],
    ];
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filas.length,
      itemBuilder: (context, i) => filas[i],
    );
  }

  Widget _rotulo(String texto) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
        child: Text(
          texto.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 1.1,
            fontWeight: FontWeight.w700,
            color: HomeTheme.textMuted,
          ),
        ),
      );

  Widget _tarjeta(TelevisorConocido e, {required bool activo}) {
    return Padding(
      key: ValueKey(e.url),
      padding: const EdgeInsets.only(bottom: 10),
      child: FocusableCard(
        borderRadius: 12,
        conCrecido: false,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => _RegistroRemotoPage(aparato: e.aparato, url: e.url),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Color.alphaBlend(
              Colors.white.withValues(alpha: 0.05),
              HomeTheme.bg,
            ),
          ),
          child: Row(
            children: [
              Icon(
                activo ? Icons.tv : Icons.tv_off,
                color: activo ? HomeTheme.accentPink : HomeTheme.textMuted,
                size: 24,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.aparato.isEmpty ? 'PrismHub' : e.aparato,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color:
                            activo ? HomeTheme.textPrimary : HomeTheme.textMuted,
                      ),
                    ),
                    const SizedBox(height: 3),
                    // La dirección, a la vista pero sin botones al lado: acá
                    // sirve para reconocer cuál es cuando hay más de uno.
                    // Copiarla y abrirla en el navegador están DENTRO, sobre el
                    // que ya se eligió.
                    Text(
                      e.url,
                      style:
                          TextStyle(fontSize: 12, color: HomeTheme.textMuted),
                    ),
                    const SizedBox(height: 2),
                    // Cuándo se lo vio. En los caídos es el dato que dice si
                    // vale la pena intentar —hace un minuto o antier— y en los
                    // que están en línea confirma que la respuesta es de ahora.
                    Text(
                      activo
                          ? 'settings.log-visto-ahora'.i18n
                          : FlutterI18n.translate(
                              context,
                              'settings.log-visto',
                              translationParams: {'cuando': _cuando(e.visto)},
                            ),
                      style: TextStyle(
                        fontSize: 11,
                        color: activo
                            ? const Color(0xFF6FCFA5)
                            : HomeTheme.textPlaceholder,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: HomeTheme.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  /// Fecha y hora de cuándo se lo vio.
  ///
  /// Completas y no «hace un rato»: estas listas se miran para decidir si esa
  /// dirección todavía sirve, y para eso hace falta el dato, no una impresión.
  String _cuando(DateTime d) {
    String dos(int n) => n.toString().padLeft(2, '0');
    final fecha = '${d.year}-${dos(d.month)}-${dos(d.day)}';
    return '$fecha · ${dos(d.hour)}:${dos(d.minute)}';
  }
}

/// El registro de otro aparato, en vivo.
class _RegistroRemotoPage extends StatefulWidget {
  const _RegistroRemotoPage({required this.aparato, required this.url});

  final String aparato;
  final String url;

  @override
  State<_RegistroRemotoPage> createState() => _RegistroRemotoPageState();
}

class _RegistroRemotoPageState extends State<_RegistroRemotoPage> {
  final _scroll = ScrollController();
  List<String> _lineas = const [];
  String _cabecera = '';
  String? _fallo;
  bool _primeraVez = true;

  /// De cuándo es lo que se está viendo, si viene de lo guardado en disco.
  ///
  /// Null quiere decir que lo de pantalla llegó en esta sesión. Con fecha, lo
  /// que se ve es de la última vez que este aparato contestó — y eso hay que
  /// decirlo, porque un registro viejo que parece de ahora lleva a conclusiones
  /// equivocadas.
  DateTime? _deCuandoEs;

  /// Cuántas líneas tenía lo último que se guardó, para no reescribir el
  /// archivo en cada refresco de cinco segundos si no cambió nada.
  int _lineasGuardadas = -1;

  /// Si hay una lectura en curso.
  ///
  /// Evita que el botón de refrescar y el temporizador de cinco segundos se
  /// pisen: dos lecturas a la vez sobre una red de casa lenta terminan
  /// llegando en cualquier orden, y la que llega segunda puede ser la MÁS
  /// VIEJA — o sea que el registro daría un paso hacia atrás solo.
  bool _trayendo = false;

  Timer? _reloj;

  @override
  void initState() {
    super.initState();
    // Lo que se guardó la última vez se muestra YA, antes de pedir nada.
    //
    // Si el televisor está caído —que es justo cuando uno entra a mirar por
    // qué— la petición va a fallar, y sin esto la pantalla quedaba vacía
    // debajo de un cartel que promete «lo de abajo es lo último que llegó».
    final guardado = RegistroGuardadoDeOtro.leer(widget.url);
    if (guardado != null) {
      _cabecera = guardado.cabecera;
      _lineas = guardado.lineas;
      _lineasGuardadas = guardado.lineas.length;
      _deCuandoEs = guardado.cuando;
      _primeraVez = false;
    }
    // Igual que en la búsqueda: pedir por red en el mismo cuadro en que la
    // pantalla entra deslizándose cuesta un cuadro, y ese cuadro se ve como un
    // parpadeo. Se espera a que la animación termine.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final animacion = ModalRoute.of(context)?.animation;
      void arrancar() {
        if (!mounted) return;
        unawaited(_traer());
        // Cada cinco segundos, igual que la página que sirve el televisor: es
        // lo que hace que esto se sienta en vivo sin castigar una red de casa.
        _reloj = Timer.periodic(const Duration(seconds: 5), (_) => _traer());
      }

      if (animacion == null || animacion.isCompleted) {
        arrancar();
        return;
      }
      void alTerminar(AnimationStatus estado) {
        if (estado != AnimationStatus.completed) return;
        animacion.removeStatusListener(alTerminar);
        arrancar();
      }

      animacion.addStatusListener(alTerminar);
    });
  }

  @override
  void dispose() {
    _reloj?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  /// Si la vista está pegada al final, que es donde aparece lo nuevo.
  bool _alFinal = true;

  /// Apaga el seguimiento cuando el desplazamiento se va del fondo.
  bool _mirarDesplazamiento(ScrollNotification n) {
    if (n is! ScrollUpdateNotification && n is! ScrollEndNotification) {
      return false;
    }
    final abajo = n.metrics.maxScrollExtent - n.metrics.pixels < 24;
    if (abajo != _alFinal) setState(() => _alFinal = abajo);
    return false;
  }

  /// La cabecera sin el «· N líneas» del final.
  static String _sinElConteo(String cabecera) {
    final corte = cabecera.lastIndexOf(' · ');
    return corte < 0 ? cabecera : cabecera.substring(0, corte);
  }

  Future<void> _copiar(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    showPlatformSnackbar(context: context, content: 'common.copied'.i18n);
  }

  Future<void> _copiarTodo() async {
    await Clipboard.setData(ClipboardData(text: _lineas.join('\n')));
    if (!mounted) return;
    showPlatformSnackbar(context: context, content: 'common.copied'.i18n);
  }

  /// Guarda o comparte el registro que llegó del televisor.
  ///
  /// Se marca de quién es: la ficha del aparato la arma quien exporta, y sin
  /// decirlo el archivo saldría diciendo que ese registro es de este teléfono
  /// o de este PC — y quien lo recibiera buscaría el fallo en el aparato
  /// equivocado.
  Future<void> _exportar() async {
    try {
      final salio = await ExportarRegistro.entregar(
        lineas: _lineas,
        etiqueta: 'televisor',
        deOtroAparato: widget.aparato.isEmpty ? widget.url : widget.aparato,
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

  /// Abre la dirección en el navegador del sistema.
  ///
  /// Sigue estando aunque el registro se vea acá dentro: en un PC es cómodo
  /// tenerlo en otra ventana, al lado de la app, en vez de ir y venir entre
  /// pantallas.
  Future<void> _enElNavegador(String url) async {
    try {
      final abierto = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (abierto) return;
    } catch (_) {
      // Se cae al portapapeles, abajo.
    }
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    showPlatformSnackbar(
      context: context,
      content: 'settings.log-sin-navegador'.i18n,
    );
  }

  Future<void> _traer() async {
    if (_trayendo) return;
    if (mounted) setState(() => _trayendo = true);
    final cliente = HttpClient()
      ..connectionTimeout = const Duration(seconds: 6);
    try {
      final pedido = await cliente.getUrl(Uri.parse('${widget.url}/texto'));
      final res = await pedido.close().timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) throw HttpException('${res.statusCode}');
      final texto = await res.transform(utf8.decoder).join();
      if (!mounted) return;
      final partido = const LineSplitter().convert(texto);
      // ── La primera línea es la cabecera SOLO si lo es ─────────────────
      //
      // El televisor manda una línea suya arriba —qué sirve, de qué zona,
      // cuántas líneas— y el resto es el registro. Se tomaba la primera sin
      // mirar qué era, y si por lo que fuera esa línea faltara, lo que se
      // comía era el borde de arriba del recuadro de PrismHub: el dibujo
      // aparecía descabezado. Reportado en vivo: «se come el logo».
      //
      // Comprobando que no sea parte del recuadro, eso no puede pasar: en el
      // peor caso se ve una línea de más, que es infinitamente mejor que ver
      // el registro con la primera línea cortada sin saberlo.
      final tieneCabecera = partido.isNotEmpty && !esElRecuadro(partido.first);
      final nuevaCabecera = tieneCabecera ? partido.first : '';
      // ── Se compara SIN el conteo de líneas ────────────────────────────
      //
      // La cabecera termina en «· N líneas», y ese número sube con cada línea
      // nueva. Comparándola entera, CADA refresco parecía un cambio de lo que
      // se sirve — reportado en vivo: «a veces al arrastrar la barra me
      // devuelve arriba». Era esto, no la barra.
      //
      // Lo que importa es si cambió el ORIGEN o la ZONA, que es todo lo que va
      // antes del conteo.
      final cambioLoQueSeSirve = _cabecera.isNotEmpty &&
          _sinElConteo(nuevaCabecera) != _sinElConteo(_cabecera);
      setState(() {
        _cabecera = nuevaCabecera;
        _lineas = tieneCabecera
            ? (partido.length > 1 ? partido.sublist(1) : const <String>[])
            : partido;
        _fallo = null;
        _primeraVez = false;
        // Lo que se ve ahora es de ahora.
        _deCuandoEs = null;
      });
      // Y se guarda, para que siga estando si el televisor se cae.
      //
      // Solo cuando cambió la cantidad de líneas: esto se refresca cada cinco
      // segundos, y reescribir el archivo entero cada vez sería castigar el
      // disco para guardar lo mismo.
      if (_lineas.length != _lineasGuardadas) {
        _lineasGuardadas = _lineas.length;
        unawaited(RegistroGuardadoDeOtro.guardar(
          url: widget.url,
          cabecera: _cabecera,
          lineas: _lineas,
        ));
      }
      // ── Se sigue el FINAL, no el principio ────────────────────────────
      //
      // Un registro en vivo se lee por abajo: lo último que pasó es lo que
      // interesa. Mandaba la vista arriba, o sea al principio de la sesión,
      // que es lo más viejo — reportado en vivo: «se actualiza y me sube
      // arriba en vez de abajo».
      //
      // Y solo mientras se esté abajo. Si la persona subió a leer algo, se
      // queda donde está: arrastrarla al fondo mientras lee es la forma más
      // rápida de volver inútil un visor en vivo. Mismo criterio que el visor
      // del propio aparato.
      if ((cambioLoQueSeSirve || _alFinal) && _scroll.hasClients) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_scroll.hasClients) return;
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        });
      }
    } catch (e) {
      if (!mounted) return;
      // Lo que ya llegó NO se borra: si el televisor se cayó, esto es
      // justamente lo que hace falta para saber por qué. Mismo criterio que la
      // página que sirve él.
      setState(() {
        _fallo = '$e';
        _primeraVez = false;
      });
    } finally {
      cliente.close(force: true);
      if (mounted) setState(() => _trayendo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HomeTheme.bg,
      appBar: AppBar(
        backgroundColor: HomeTheme.bg,
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            widget.aparato.isEmpty ? 'PrismHub' : widget.aparato,
            maxLines: 1,
            style: TextStyle(color: HomeTheme.textPrimary),
          ),
        ),
        actions: [
          // Refrescar a mano, aunque se actualice solo cada cinco segundos.
          //
          // Los cinco segundos están bien para mirar; cuando uno acaba de
          // hacer algo en el televisor y quiere ver el efecto YA, esperar
          // hasta cinco segundos sin saber cuánto falta se siente colgado.
          // El botón no reemplaza al automático: lo adelanta.
          IconButton(
            tooltip: 'common.refresh'.i18n,
            icon: _trayendo
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: HomeTheme.textPrimary,
                    ),
                  )
                : const Icon(Icons.refresh),
            color: HomeTheme.textPrimary,
            onPressed: _trayendo ? null : () => unawaited(_traer()),
          ),
          // Guardar o compartir lo que llegó.
          //
          // En teléfono sale por el menú de compartir del sistema —WhatsApp,
          // correo, lo que haya— y en escritorio se elige dónde guardarlo. En
          // los dos casos lo decide la persona; la app no elige por ella.
          IconButton(
            tooltip: 'common.export'.i18n,
            icon: const Icon(Icons.ios_share),
            color: HomeTheme.textPrimary,
            onPressed: _lineas.isEmpty ? null : _exportar,
          ),
          // ── Copiar el registro entero, sin seleccionar nada a mano ──────
          //
          // En PC la selección con el mouse existe (ver SeleccionableSiSePuede),
          // pero Ctrl+A no alcanza a todo el registro: la lista se arma de a
          // poco (`ListView.builder`) y solo entra en la selección lo que ya
          // se dibujó en pantalla, no lo que sigue más abajo sin construirse
          // todavía. Reportado en vivo: «no me deja copiar todo con
          // control+A». Y en el teléfono la selección con el dedo está
          // apagada del todo —ver el porqué en SeleccionableSiSePuede—, así
          // que ahí no había NINGUNA forma de sacar el registro salvo
          // exportarlo a un archivo.
          //
          // Este botón no depende de qué esté dibujado: toma `_lineas`
          // directo, la misma lista completa que ya usa `_exportar`, y la
          // manda entera al portapapeles. Sirve igual en PC y en teléfono.
          IconButton(
            tooltip: 'settings.log-copiar-todo'.i18n,
            icon: const Icon(Icons.copy_all_rounded),
            color: HomeTheme.textPrimary,
            onPressed: _lineas.isEmpty ? null : _copiarTodo,
          ),
          IconButton(
            tooltip: 'settings.log-copiar'.i18n,
            icon: const Icon(Icons.copy_rounded),
            color: HomeTheme.textPrimary,
            onPressed: () => _copiar(widget.url),
          ),
          IconButton(
            tooltip: 'settings.log-en-navegador'.i18n,
            icon: const Icon(Icons.open_in_browser),
            color: HomeTheme.textPrimary,
            onPressed: () => _enElNavegador(widget.url),
          ),
        ],
      ),
      // Acá el ancho NO se acota: son líneas de registro, y cuanto más
      // entren a lo ancho menos se parten. Es lo contrario que en la lista de
      // arriba, y por eso se decide por separado.
      body: ColoredBox(
        color: HomeTheme.bg,
        child: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_cabecera.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                  child: Text(
                    _cabecera,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: HomeTheme.accentPink,
                    ),
                  ),
                ),
              if (_fallo != null)
                Container(
                  margin: const EdgeInsets.fromLTRB(14, 6, 14, 6),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: HomeTheme.accentRed.withValues(alpha: 0.16),
                    border: Border.all(color: HomeTheme.accentRed),
                  ),
                  child: Text(
                    'settings.log-remoto-cortado'.i18n,
                    style:
                        TextStyle(fontSize: 12, color: HomeTheme.textPrimary),
                  ),
                ),
              if (_deCuandoEs != null) _avisoDeQueEsDeAntes(),
              Expanded(child: _texto()),
            ],
          ),
        ),
      ),
    );
  }

  /// Avisa, sin lugar a dudas, que lo que se está viendo NO es de ahora.
  ///
  /// Un registro viejo que parece de ahora es peor que no tener nada: lleva a
  /// mirar un fallo que ya se arregló, o a no ver el que está pasando.
  Widget _avisoDeQueEsDeAntes() {
    final d = _deCuandoEs!;
    String dos(int n) => n.toString().padLeft(2, '0');
    final cuando = '${d.year}-${dos(d.month)}-${dos(d.day)} '
        '${dos(d.hour)}:${dos(d.minute)}';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: const Color(0x33B98A00),
        border: Border.all(color: const Color(0x66D9A400)),
      ),
      child: Text(
        FlutterI18n.translate(
          context,
          'settings.log-remoto-guardado',
          translationParams: {'cuando': cuando},
        ),
        style: TextStyle(fontSize: 13, color: HomeTheme.textPrimary),
      ),
    );
  }

  Widget _texto() {
    if (_primeraVez) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_lineas.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(
            // Vacío Y sin conexión no es lo mismo que vacío a secas.
            //
            // Decía «dejá esta pantalla abierta y usá la app: lo que vaya
            // pasando aparece acá», que es cierto cuando hay conexión y
            // mentira cuando se cortó — ahí no va a aparecer nada por más que
            // se espere. Se ve en la foto: el aviso rojo de arriba dice que se
            // cortó y el de abajo invita a esperar.
            _fallo != null
                ? 'settings.log-remoto-vacio-sin-conexion'.i18n
                : 'settings.log-empty'.i18n,
            textAlign: TextAlign.center,
            style: TextStyle(color: HomeTheme.textMuted, fontSize: 14),
          ),
        ),
      );
    }
    final agrupadas = agruparElRecuadro(_lineas);
    return NotificationListener<ScrollNotification>(
      onNotification: _mirarDesplazamiento,
      child: Padding(
        // ── El registro, dentro de un panel con contorno ────────────────
        //
        // Igual que la página que sirve el televisor. No es adorno: un texto
        // monoespaciado pegado a los cuatro bordes de la ventana se lee como
        // parte del marco de la app, y cuesta ver dónde empieza y dónde
        // termina — sobre todo buscando una línea concreta entre miles. Con el
        // contorno, el registro es un objeto con principio y fin.
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: Colors.black.withValues(alpha: 0.22),
            border: Border.all(color: HomeTheme.border),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(9),
            // ── Con barra, agarrable y de tamaño estable ────────────────
            //
            // La que sale por defecto en escritorio aparece al desplazar, se
            // desvanece y no se puede agarrar: al intentar arrastrarla no pasa
            // nada y parece que la pantalla se trabó.
            //
            // Y el tirador se agrandaba y achicaba solo. Una lista perezosa no
            // sabe cuánto mide en total: lo ESTIMA con el promedio de lo que
            // ya construyó, y las líneas de un registro miden cosas muy
            // distintas —una suelta, un recuadro de veinte—. Con un mínimo
            // deja de encogerse hasta casi desaparecer.
            child: RawScrollbar(
              controller: _scroll,
              interactive: true,
              thumbVisibility: true,
              thickness: 12,
              minThumbLength: 48,
              radius: const Radius.circular(6),
              thumbColor: HomeTheme.accentPink.withValues(alpha: 0.55),
              child: SeleccionableSiSePuede(
                child: ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
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
                      fontSize: 11.5,
                      height: 1.35,
                      color: colorDeLinea(linea),
                    );
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: esElRecuadro(linea)
                          ? FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child:
                                  Text(linea, style: estilo, softWrap: false),
                            )
                          : Text(linea, style: estilo),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
