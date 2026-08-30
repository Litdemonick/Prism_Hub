import 'package:flutter/widgets.dart';

/// Lo que el reproductor le pide a un motor de vídeo, sea cual sea.
///
/// ── Por qué existe ──────────────────────────────────────────────────────────
///
/// Hasta ahora había un solo motor —mpv, vía media_kit— y el reproductor le
/// hablaba directo. Eso alcanzaba mientras el motor sirviera para las cuatro
/// plataformas, pero hay dos cosas que mpv no puede dar en Android:
///
///  - **El salto en HLS fMP4 lo deja clavado.** Es un bug de ffmpeg
///    (`mpv-player/mpv#15184`), etiquetado `down-upstream:ffmpeg` y cerrado
///    como *not planned*. Ya costó 482 líneas de rodeo en este repo
///    (`RecorteFmp4`) después de doce intentos revertidos.
///  - **No puede reproducir tunelizado.** En Android TV eso significa dejarle
///    la sincronía de audio y vídeo al hardware del televisor, que es lo que
///    elimina el desfase de audio. Necesita una `SurfaceView`, y el camino de
///    media_kit dibuja sobre una textura.
///
/// Las dos las resuelve el motor nativo de Android. Pero en Windows y Linux no
/// hay alternativa a mpv, así que no se trata de cambiar de motor sino de poder
/// tener **dos**, y que el resto del reproductor no se entere de cuál está
/// corriendo. Para eso está esta interfaz.
///
/// ── Qué NO va acá ───────────────────────────────────────────────────────────
///
/// Solo lo que los dos motores pueden hacer. Todo lo que es propio de uno
/// —ajustar propiedades de libmpv, leer el caudal de descarga, el recorte de
/// fMP4— se pregunta antes con [soporta] y se pide por el camino específico. Un
/// contrato que promete algo que un motor no cumple es peor que no tenerlo:
/// mueve el fallo de la compilación al momento de reproducir.
abstract class MotorDeVideo {
  /// Nombre corto, para el registro y para el interruptor de Ajustes.
  String get nombre;

  // ── Abrir y cerrar ────────────────────────────────────────────────────────

  /// Abre una dirección. [cabeceras] son las que exige la fuente (Referer,
  /// User-Agent); sin ellas muchos servidores contestan que no.
  ///
  /// [subtitulosAparte] son los que la extensión entrega por su lado, con
  /// `url`, `idioma` y `titulo`. Van acá y no en una llamada posterior porque
  /// el motor de Android los suma como pistas del contenido al preparar la
  /// fuente: así aparecen en la misma lista que las que trae el archivo y se
  /// eligen igual. mpv los ignora — ya los maneja por su cuenta, con su propia
  /// lista de pistas.
  Future<void> abrir(
    String url, {
    Map<String, String>? cabeceras,
    bool arrancar = true,
    List<Map<String, String>> subtitulosAparte = const [],
  });

  /// Suelta todo lo nativo. Después de esto el motor no se puede volver a usar.
  Future<void> soltar();

  // ── Mandos ────────────────────────────────────────────────────────────────

  Future<void> reproducir();
  Future<void> pausar();
  Future<void> parar();
  Future<void> saltarA(Duration donde);

  /// 0 a 100 es el volumen original. Por encima, si el motor lo permite, es
  /// amplificación — ver [soporta] con [CapacidadDeMotor.volumenAmplificado].
  Future<void> ponerVolumen(double volumen);

  Future<void> ponerVelocidad(double velocidad);

  // ── Estado, ahora mismo ───────────────────────────────────────────────────

  Duration get posicion;
  Duration get duracion;

  /// Hasta dónde llegó la descarga. Es lo que dibuja la sombra de la barra.
  Duration get colchon;

  bool get reproduciendo;

  /// Esperando datos. Es lo que enciende la rueda.
  bool get cargando;

  double get volumen;

  /// Medidas del vídeo, o null mientras no se sepan. Con las dos en cero
  /// todavía no hay imagen.
  int? get ancho;
  int? get alto;

  // ── Avisos ────────────────────────────────────────────────────────────────

  Stream<Duration> get posiciones;
  Stream<Duration> get duraciones;
  Stream<Duration> get colchones;
  Stream<bool> get reproducciones;
  Stream<bool> get cargas;
  Stream<double> get volumenes;
  Stream<String> get errores;

  /// Las medidas del vídeo, cada vez que se conocen o cambian.
  ///
  /// ── Por qué está en la fachada y no se lee de cada motor ────────────────
  ///
  /// Esto no es solo el tamaño de la imagen: es **el aviso de que hay imagen**.
  /// De él cuelgan el apagado de la rueda de carga, el desbloqueo de la barra
  /// de progreso, la detección de vídeo en 360° y el ajuste de frecuencia de
  /// la pantalla del televisor.
  ///
  /// Estaba leído directo de media_kit, y al meter el motor de Android eso
  /// dejó de llegar: la rueda giraba para siempre por encima del vídeo —que se
  /// veía perfecto— y la barra quedaba bloqueada sin poder tocarla. Un dato del
  /// que dependen cuatro cosas no puede salir de un motor concreto.
  Stream<({int ancho, int alto})> get medidas;

  /// El vídeo llegó al final. Es lo que encadena el episodio siguiente.
  Stream<bool> get finales;

  // ── La imagen ─────────────────────────────────────────────────────────────

  /// El widget que muestra el vídeo.
  ///
  /// Cada motor trae el suyo y no son intercambiables: media_kit dibuja sobre
  /// una textura de Flutter y el motor de Android sobre una superficie nativa.
  /// Por eso la vista se pide acá en vez de que la pantalla arme el widget —
  /// así el reproductor no necesita saber cuál está corriendo.
  ///
  /// [encima] se dibuja sobre la imagen. Va por parámetro y no como una capa
  /// que ponga la pantalla por su cuenta porque cada motor lo coloca distinto:
  /// media_kit tiene su propio hueco para eso, y el de Android necesita una
  /// pila aparte. Puesto afuera taparía los botones.
  ///
  /// [alineacion] es dónde queda la imagen cuando no llena el marco — con
  /// «llenar pantalla» se ancla abajo para no recortar los subtítulos quemados.
  Widget vista({
    required BoxFit ajuste,
    required Color fondo,
    Alignment alineacion = Alignment.center,
    Widget? encima,
  });

  // ── Lo que no todos pueden ────────────────────────────────────────────────

  /// Si este motor puede hacer algo. Se pregunta ANTES de pedirlo.
  bool soporta(CapacidadDeMotor cual);
}

/// Cosas que un motor puede tener y otro no.
///
/// Se declaran para poder preguntar en vez de asumir: la interfaz solo promete
/// lo que los dos cumplen, y todo lo demás pasa por acá. Así, cuando se agregue
/// un motor nuevo, lo que no soporte se apaga solo en la interfaz en vez de
/// fallar al reproducir.
enum CapacidadDeMotor {
  /// Subir el volumen por encima del original de la pista.
  volumenAmplificado,

  /// Elegir pista de audio y de subtítulos entre las que trae el archivo.
  pistas,

  /// Sacar un fotograma de lo que se está viendo, para la portada de
  /// «continuar viendo».
  captura,

  /// Reproducción tunelizada: el decodificador escribe directo al hardware y
  /// la sincronía de audio y vídeo la hace el aparato. Solo en Android TV.
  tunelizado,

  /// Saltar dentro de una lista HLS de tipo fMP4 sin quedarse clavado. mpv NO
  /// la tiene — ver `RecorteFmp4`, que es el rodeo que hace falta sin esto.
  saltoEnFmp4,
}
