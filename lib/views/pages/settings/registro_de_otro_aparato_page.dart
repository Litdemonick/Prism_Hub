import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:prismhub/utils/exportar_registro.dart';
import 'package:prismhub/utils/anuncio_de_registro.dart';
import 'package:prismhub/utils/i18n.dart';
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

class _RegistroDeOtroAparatoPageState extends State<RegistroDeOtroAparatoPage> {
  List<({String aparato, String url})> _encontrados = const [];
  bool _buscando = true;

  @override
  void initState() {
    super.initState();
    // ── La búsqueda arranca DESPUÉS de la animación de entrada ──────────
    //
    // Reportado en vivo: «al tocar la zona para ver el registro del televisor
    // parpadea en blanco». Buscar abre un socket, manda mensajes a toda la red
    // y arma un temporizador, y todo eso empezaba en el mismo cuadro en que la
    // pantalla entra deslizándose. Un cuadro perdido justo ahí es el
    // parpadeo — no hay nada dibujado todavía y se ve el fondo de la
    // transición.
    //
    // Esperando a que termine, la pantalla entra limpia y la búsqueda empieza
    // con la animación ya quieta. Mismo criterio que el visor del registro.
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
    if (!mounted) return;
    setState(() {
      _encontrados = hallazgos;
      _buscando = false;
    });
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
          IconButton(
            tooltip: 'common.refresh'.i18n,
            icon: const Icon(Icons.refresh),
            color: HomeTheme.textPrimary,
            onPressed: _buscando ? null : _buscar,
          ),
        ],
      ),
      // ── Ancho acotado, y centrado ────────────────────────────────────
      //
      // En un teléfono de pie la lista ocupa lo que hay y está bien. En un PC
      // a pantalla completa, o en una tablet apaisada, una tarjeta de punta a
      // punta deja el nombre del televisor pegado al borde izquierdo y la
      // flecha al derecho, con medio metro de nada en medio.
      //
      // SafeArea con los lados: apaisado, el recorte de cámara y la barra de
      // gestos se comen la primera columna. Arriba no, que de eso ya se ocupó
      // la barra de título.
      // ColoredBox además del `backgroundColor` del Scaffold: durante la
      // transición, lo que se ve por debajo es el fondo del tema de Material,
      // que en esta app no es el mismo. Pintarlo acá hace que el primer cuadro
      // ya salga del color correcto.
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
    if (_buscando) {
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
    if (_encontrados.isEmpty) {
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
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _encontrados.length,
      itemBuilder: (context, i) {
        final e = _encontrados[i];
        return Padding(
          key: ValueKey(e.url),
          padding: const EdgeInsets.only(bottom: 10),
          child: FocusableCard(
            borderRadius: 12,
            conCrecido: false,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    _RegistroRemotoPage(aparato: e.aparato, url: e.url),
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
                  Icon(Icons.tv, color: HomeTheme.accentPink, size: 24),
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
                            color: HomeTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        // La dirección, a la vista pero sin botones al lado.
                        //
                        // Acá sirve para reconocer cuál televisor es cuando
                        // hay más de uno. Copiarla y abrirla en el navegador
                        // están DENTRO, en la pantalla del registro: son
                        // cosas que se hacen sobre el que ya se eligió, y
                        // acá solo llenaban la fila de iconos chicos entre
                        // los que hay que apuntar.
                        Text(
                          e.url,
                          style: TextStyle(
                            fontSize: 12,
                            color: HomeTheme.textMuted,
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
      },
    );
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

  Future<void> _copiar(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
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
        deOtroAparato:
            widget.aparato.isEmpty ? widget.url : widget.aparato,
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
      final tieneCabecera =
          partido.isNotEmpty && !esElRecuadro(partido.first);
      setState(() {
        _cabecera = tieneCabecera ? partido.first : '';
        _lineas = tieneCabecera
            ? (partido.length > 1 ? partido.sublist(1) : const <String>[])
            : partido;
        _fallo = null;
        _primeraVez = false;
      });
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
              Expanded(child: _texto()),
            ],
          ),
        ),
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
            'settings.log-empty'.i18n,
            textAlign: TextAlign.center,
            style: TextStyle(color: HomeTheme.textMuted, fontSize: 14),
          ),
        ),
      );
    }
    final agrupadas = agruparElRecuadro(_lineas);
    // ── Con barra, y que se pueda arrastrar ────────────────────────────
    //
    // Reportado en vivo: «el scroll es tosco al tocar la barra». La barra que
    // sale por defecto en escritorio es solo un indicador —muestra dónde
    // estás pero no se puede agarrar— así que al intentar arrastrarla no pasa
    // nada y parece que la pantalla se traba. Con `interactive` se agarra y
    // se lleva, que es lo que uno intenta hacer con un registro largo.
    return RawScrollbar(
      controller: _scroll,
      // Siempre a la vista y agarrable.
      //
      // La de por defecto aparece al desplazar y se desvanece, y en escritorio
      // es solo un indicador —no se puede agarrar—. En un registro de miles de
      // líneas eso deja sin la única forma cómoda de moverse rápido: al
      // intentar arrastrarla no pasa nada y parece que la pantalla se trabó.
      //
      // Ancha a propósito: doce puntos es lo que hace falta para acertarle con
      // el dedo, y con el ratón tampoco molesta.
      interactive: true,
      thumbVisibility: true,
      thickness: 12,
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
                      child: Text(linea, style: estilo, softWrap: false),
                    )
                  : Text(linea, style: estilo),
            );
          },
        ),
      ),
    );
  }
}
