import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:prismhub/controllers/watch/motor/motor_de_video.dart';
import 'package:prismhub/utils/log.dart';
import 'package:prismhub/utils/platform_tv.dart';

/// Una pista de audio o de subtítulos de las que trae el contenido.
class PistaDeMedia3 {
  const PistaDeMedia3({
    required this.tipo,
    required this.id,
    required this.idioma,
    required this.titulo,
    required this.elegida,
    required this.sePuede,
  });

  /// `audio` o `texto`.
  final String tipo;

  /// Lo que hay que devolver para elegirla. Ver [MotorMedia3.elegirPista].
  final String id;

  final String? idioma;
  final String? titulo;
  final bool elegida;

  /// Si el aparato puede con ella. Una pista que el decodificador no soporta
  /// se lista igual —para poder decir por qué no está— pero no se puede elegir.
  final bool sePuede;

  /// Cómo se muestra en la lista.
  ///
  /// El título es lo que más dice cuando está («Español latino»), y el idioma
  /// es lo único que hay en la mayoría de los archivos. Con ninguno de los dos
  /// queda el número, que al menos permite distinguir una de otra.
  String comoSeLlama(int numero) {
    final t = titulo?.trim() ?? '';
    if (t.isNotEmpty) return t;
    final i = idioma?.trim() ?? '';
    if (i.isNotEmpty) return i;
    return '#$numero';
  }

  static PistaDeMedia3? deMapa(Object? crudo) {
    if (crudo is! Map) return null;
    final id = crudo['id']?.toString();
    if (id == null) return null;
    return PistaDeMedia3(
      tipo: crudo['tipo']?.toString() ?? 'texto',
      id: id,
      idioma: crudo['idioma']?.toString(),
      titulo: crudo['titulo']?.toString(),
      elegida: crudo['elegida'] == true,
      sePuede: crudo['sePuede'] != false,
    );
  }
}

/// El motor de Android: ExoPlayer, hablado directo por Media3.
///
/// ── Por qué se escribió el nativo en vez de usar `video_player` ─────────────
///
/// `video_player` también lleva ExoPlayer adentro, y por eso se probó primero.
/// Se cayó por tres cosas, y las tres se midieron en la app andando:
///
///  1. **No entrega los subtítulos.** En Android no se veía ni uno: el
///     `SubtitleView` que los dibuja cuelga del reproductor de media_kit, que
///     con este motor nunca recibe la fuente. O sea que lo que mandan las
///     extensiones aparte (`.vtt`, `.srt`) se descargaba y no se mostraba.
///  2. **No deja elegir pista de audio.** Un archivo con japonés y castellano
///     se queda con la que decida el sistema.
///  3. **No expone la tunelización**, que es lo que le saca el desfase de audio
///     a un televisor.
///
/// Ninguna de las tres es una limitación de ExoPlayer: las tres las sabe hacer.
/// Son de la API del complemento. Por eso se habla con Media3 directo.
///
/// ── Lo que este motor NO hace ───────────────────────────────────────────────
///
/// No amplifica el volumen por encima del original, y no saca fotogramas para
/// la portada de «continuar viendo». Las dos se preguntan con [soporta] y quien
/// las use ya tiene que estar mirando eso.
///
/// ── Qué pasa si algo falla ──────────────────────────────────────────────────
///
/// [abrir] relanza. Es a propósito: quien llama necesita poder caer al otro
/// motor, y para eso tiene que enterarse. Todo lo demás traga el error, porque
/// una vez que el vídeo anda, que falle un pausar no puede tumbar la app.
class MotorMedia3 implements MotorDeVideo {
  static const _canal = MethodChannel('com.prismhub.app/media3');
  static const _avisos = EventChannel('com.prismhub.app/media3/avisos');

  StreamSubscription<dynamic>? _escucha;
  int? _textura;

  final _posiciones = StreamController<Duration>.broadcast();
  final _duraciones = StreamController<Duration>.broadcast();
  final _colchones = StreamController<Duration>.broadcast();
  final _reproducciones = StreamController<bool>.broadcast();
  final _cargas = StreamController<bool>.broadcast();
  final _volumenes = StreamController<double>.broadcast();
  final _errores = StreamController<String>.broadcast();
  final _finales = StreamController<bool>.broadcast();
  final _pistas = StreamController<List<PistaDeMedia3>>.broadcast();
  final _subtitulos = StreamController<List<String>>.broadcast();

  Duration _posicion = Duration.zero;
  Duration _duracion = Duration.zero;
  Duration _colchon = Duration.zero;
  bool _reproduciendo = false;
  bool _cargando = false;
  double _volumen = 100;
  int? _ancho;
  int? _alto;
  var _ultimasPistas = <PistaDeMedia3>[];

  /// El tamaño de la imagen, para que la vista sepa qué proporción tiene.
  final _medidas = ValueNotifier<Size?>(null);

  /// Las últimas líneas de subtítulo, para dibujarlas.
  ///
  /// Va por [ValueNotifier] y no por el flujo: lo dibuja un widget que tiene
  /// que reconstruirse solo él, y un `StreamBuilder` acá adentro reconstruiría
  /// también todo lo que lo envuelve en cada línea.
  final lineasDeSubtitulo = ValueNotifier<List<String>>(const []);

  @override
  String get nombre => 'media3';

  /// Las pistas del contenido, cada vez que cambian.
  Stream<List<PistaDeMedia3>> get pistas => _pistas.stream;

  /// Las que se conocen ahora mismo.
  List<PistaDeMedia3> get pistasDeAhora => _ultimasPistas;

  /// El texto del subtítulo, por si alguien prefiere el flujo.
  Stream<List<String>> get subtitulos => _subtitulos.stream;

  // ── Abrir ─────────────────────────────────────────────────────────────────

  /// [subtitulosAparte] son los que entrega la extensión por su cuenta, con
  /// `url`, `idioma` y `titulo`. Van al abrir y no después porque Media3 los
  /// suma como pistas del contenido: así aparecen en la misma lista que las que
  /// trae el archivo, y se eligen igual.
  @override
  Future<void> abrir(
    String url, {
    Map<String, String>? cabeceras,
    bool arrancar = true,
    List<Map<String, String>> subtitulosAparte = const [],
  }) async {
    _reiniciarEstado();
    _textura ??= await _canal.invokeMethod<int>('crear');
    _escucha ??= _avisos.receiveBroadcastStream().listen(
          _mirarYAvisar,
          onError: (Object e) {
            if (!_errores.isClosed) _errores.add('$e');
          },
        );
    await _canal.invokeMethod<void>('abrir', {
      'url': url,
      'cabeceras': cabeceras ?? const <String, String>{},
      'subtitulos': subtitulosAparte,
      'arrancar': arrancar,
      // Cuánto colchón puede permitirse este aparato. Ver colchonPara() del
      // lado nativo para por qué no es el mismo para todos.
      'perfil': switch (PerfilDeAparato.nivel) {
        NivelDeAparato.alto => 'alto',
        NivelDeAparato.medio => 'medio',
        NivelDeAparato.bajo => 'bajo',
      },
      // Todavía no: la tunelización necesita una superficie nativa de verdad, y
      // hoy se dibuja sobre una textura. Encenderla acá dejaría la pantalla
      // negra con el audio andando, que es exactamente el fallo que ya se vio
      // en un televisor. Se prende cuando esté la SurfaceView.
      'tunelizar': false,
    });
  }

  void _reiniciarEstado() {
    _posicion = Duration.zero;
    _duracion = Duration.zero;
    _colchon = Duration.zero;
    _reproduciendo = false;
    _cargando = false;
    _ancho = null;
    _alto = null;
    _ultimasPistas = const [];
    lineasDeSubtitulo.value = const [];
    _medidas.value = null;
  }

  void _mirarYAvisar(dynamic crudo) {
    if (crudo is! Map) return;
    switch (crudo['que']) {
      case 'posicion':
        _posicion = Duration(milliseconds: (crudo['valor'] as num).toInt());
        if (!_posiciones.isClosed) _posiciones.add(_posicion);
      case 'duracion':
        _duracion = Duration(milliseconds: (crudo['valor'] as num).toInt());
        if (!_duraciones.isClosed) _duraciones.add(_duracion);
      case 'colchon':
        _colchon = Duration(milliseconds: (crudo['valor'] as num).toInt());
        if (!_colchones.isClosed) _colchones.add(_colchon);
      case 'reproduciendo':
        _reproduciendo = crudo['valor'] == true;
        if (!_reproducciones.isClosed) _reproducciones.add(_reproduciendo);
      case 'cargando':
        _cargando = crudo['valor'] == true;
        if (!_cargas.isClosed) _cargas.add(_cargando);
      case 'volumen':
        _volumen = ((crudo['valor'] as num).toDouble()) * 100;
        if (!_volumenes.isClosed) _volumenes.add(_volumen);
      case 'medidas':
        _ancho = (crudo['ancho'] as num?)?.toInt();
        _alto = (crudo['alto'] as num?)?.toInt();
        final a = _ancho ?? 0;
        final b = _alto ?? 0;
        _medidas.value = (a > 0 && b > 0)
            ? Size(a.toDouble(), b.toDouble())
            : null;
      case 'error':
        final texto = crudo['valor']?.toString() ?? 'error desconocido';
        logger.severe('media3: $texto');
        if (!_errores.isClosed) _errores.add(texto);
      case 'final':
        if (!_finales.isClosed) _finales.add(true);
      case 'pistas':
        final lista = (crudo['valor'] as List?)
                ?.map(PistaDeMedia3.deMapa)
                .whereType<PistaDeMedia3>()
                .toList(growable: false) ??
            const <PistaDeMedia3>[];
        _ultimasPistas = lista;
        if (!_pistas.isClosed) _pistas.add(lista);
      case 'subtitulo':
        final lineas = (crudo['valor'] as List?)
                ?.map((e) => e.toString())
                .where((e) => e.isNotEmpty)
                .toList(growable: false) ??
            const <String>[];
        lineasDeSubtitulo.value = lineas;
        if (!_subtitulos.isClosed) _subtitulos.add(lineas);
    }
  }

  // ── Mandos ────────────────────────────────────────────────────────────────

  /// Todo lo que no sea abrir traga el error.
  ///
  /// Una vez que el vídeo anda, que falle un pausar o un salto no puede tumbar
  /// nada: se anota y se sigue.
  Future<void> _intentar(String que, Future<void> Function() accion) async {
    try {
      await accion();
    } catch (e) {
      logger.info('media3: $que falló: $e');
    }
  }

  @override
  Future<void> reproducir() =>
      _intentar('reproducir', () => _canal.invokeMethod('reproducir'));

  @override
  Future<void> pausar() =>
      _intentar('pausar', () => _canal.invokeMethod('pausar'));

  @override
  Future<void> parar() => _intentar('parar', () => _canal.invokeMethod('parar'));

  @override
  Future<void> saltarA(Duration donde) => _intentar(
        'saltar',
        () => _canal.invokeMethod('saltar', {'ms': donde.inMilliseconds}),
      );

  @override
  Future<void> ponerVolumen(double volumen) => _intentar('volumen', () {
        // La fachada habla de 0 a 100 (y más arriba es amplificar, que este
        // motor no puede); Media3 habla de 0 a 1.
        return _canal.invokeMethod('volumen', {
          'valor': (volumen / 100).clamp(0.0, 1.0),
        });
      });

  @override
  Future<void> ponerVelocidad(double velocidad) => _intentar(
        'velocidad',
        () => _canal.invokeMethod('velocidad', {'valor': velocidad}),
      );

  /// Elige una pista. Con [id] en null se apaga ese tipo — que en subtítulos es
  /// «ninguno».
  Future<void> elegirPista({required String tipo, String? id}) => _intentar(
        'elegir pista',
        () => _canal.invokeMethod('elegirPista', {'tipo': tipo, 'id': id}),
      );

  // ── Estado ────────────────────────────────────────────────────────────────

  @override
  Duration get posicion => _posicion;

  @override
  Duration get duracion => _duracion;

  @override
  Duration get colchon => _colchon;

  @override
  bool get reproduciendo => _reproduciendo;

  @override
  bool get cargando => _cargando;

  @override
  double get volumen => _volumen;

  @override
  int? get ancho => _ancho;

  @override
  int? get alto => _alto;

  @override
  Stream<Duration> get posiciones => _posiciones.stream;

  @override
  Stream<Duration> get duraciones => _duraciones.stream;

  @override
  Stream<Duration> get colchones => _colchones.stream;

  @override
  Stream<bool> get reproducciones => _reproducciones.stream;

  @override
  Stream<bool> get cargas => _cargas.stream;

  @override
  Stream<double> get volumenes => _volumenes.stream;

  @override
  Stream<String> get errores => _errores.stream;

  @override
  Stream<bool> get finales => _finales.stream;

  // ── La imagen ─────────────────────────────────────────────────────────────

  @override
  Widget vista({
    required BoxFit ajuste,
    required Color fondo,
    Alignment alineacion = Alignment.center,
    Widget? encima,
  }) {
    final id = _textura;
    return ColoredBox(
      color: fondo,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (id != null)
            // Escucha SOLO las medidas del vídeo.
            //
            // Es lo único de acá que cambia cuando cambia el vídeo, y aislarlo
            // en un ValueListenableBuilder evita que la posición —que llega
            // cuatro veces por segundo— haga reconstruir la imagen. Ese es el
            // grueso de la diferencia entre una interfaz fluida y una que da
            // tirones mientras se reproduce.
            ValueListenableBuilder<Size?>(
              valueListenable: _medidas,
              builder: (context, medidas, _) {
                final t = Texture(textureId: id);
                if (medidas == null) return t;
                // FittedBox con el tamaño real: es lo que hace que `ajuste` y
                // `alineacion` signifiquen lo mismo que en el otro motor. La
                // textura sola se estira para llenar y no respeta ninguno.
                return FittedBox(
                  fit: ajuste,
                  alignment: alineacion,
                  child: SizedBox(
                    width: medidas.width,
                    height: medidas.height,
                    child: t,
                  ),
                );
              },
            ),
          if (encima != null) encima,
        ],
      ),
    );
  }

  // ── Soltar ────────────────────────────────────────────────────────────────

  @override
  Future<void> soltar() async {
    await _escucha?.cancel();
    _escucha = null;
    _textura = null;
    try {
      await _canal.invokeMethod<void>('soltar');
    } catch (e) {
      logger.info('media3: no se pudo soltar: $e');
    }
    for (final c in <StreamController<dynamic>>[
      _posiciones,
      _duraciones,
      _colchones,
      _reproducciones,
      _cargas,
      _volumenes,
      _errores,
      _finales,
      _pistas,
      _subtitulos,
    ]) {
      if (!c.isClosed) await c.close();
    }
    // Los dos notificadores NO se destruyen a propósito.
    //
    // El orden de desmontaje no está garantizado: el controlador puede cerrarse
    // antes de que la pantalla del reproductor termine de irse, y un widget que
    // todavía esté escuchando a un ValueNotifier ya destruido revienta al
    // volver a suscribirse. Son dos objetos minúsculos que se van con el motor
    // cuando lo recoge el recolector; destruirlos a mano no gana nada y abre
    // una caída que aparecería justo al salir del vídeo.
    _medidas.value = null;
    lineasDeSubtitulo.value = const [];
  }

  @override
  bool soporta(CapacidadDeMotor cual) => switch (cual) {
        // Las dos razones por las que existe este motor.
        CapacidadDeMotor.saltoEnFmp4 => true,
        CapacidadDeMotor.pistas => true,
        // La sabe hacer, pero necesita una superficie nativa y hoy se dibuja
        // sobre una textura. Se enciende cuando esté la SurfaceView; hasta
        // entonces prometerla sería mentir en el contrato.
        CapacidadDeMotor.tunelizado => false,
        CapacidadDeMotor.volumenAmplificado => false,
        CapacidadDeMotor.captura => false,
      };
}
