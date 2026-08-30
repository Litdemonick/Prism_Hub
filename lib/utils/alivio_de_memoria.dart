import 'package:flutter/widgets.dart';
import 'package:prismhub/utils/log.dart';
import 'package:prismhub/utils/platform_tv.dart';
import 'package:prismhub/utils/portadas_perdidas.dart';
import 'package:prismhub/views/widgets/cache_network_image.dart';

/// Escucha el aviso del sistema de que se está quedando sin memoria, y suelta
/// lo que se pueda volver a conseguir.
///
/// ── Por qué hace falta escucharlo ────────────────────────────────────────
///
/// Android manda `onTrimMemory` **antes** de empezar a matar procesos: es el
/// último momento en que la app puede hacer algo. Hasta ahora nadie lo
/// escuchaba, así que la app se enteraba de que faltaba memoria cuando ya la
/// habían cerrado — que es exactamente lo que se reportó en televisores viejos
/// («se peta»).
///
/// Flutter vacía su caché de imágenes él solo ante ese aviso, pero eso es todo
/// lo que hace: los registros que la app fue armando durante la sesión siguen
/// enteros. Acá se suelta también lo demás.
///
/// ── Qué se suelta y qué NO ───────────────────────────────────────────────
///
/// Se suelta lo que es **puro atajo**: las imágenes ya decodificadas y los dos
/// registros de portadas (cuáles fallaron hace poco, cuáles ya se habían
/// visto). Perderlos no cambia lo que la app sabe, solo hace que se vuelva a
/// pedir algo que se podría haber ahorrado.
///
/// **No** se toca nada que la app necesite para decidir bien:
///
///   · `Extension._seguros` / `_adultos` / `_mixtas` — de ahí sale a qué zona
///     va cada extensión y qué filtro se le manda para que el Inicio no
///     muestre contenido para adultos. Vaciarlos no ahorraría casi nada (una
///     entrada por extensión instalada, no por título) y sí podría dejar una
///     puerta abierta. No se tocan.
///   · `FormaDePortada` — una proporción por paquete, y además está guardada
///     en disco. No pesa.
///
/// O sea: esto suelta megas de píxeles, no kilobytes de texto. Es donde de
/// verdad está la memoria.
class AlivioDeMemoria with WidgetsBindingObserver {
  AlivioDeMemoria._();

  static final AlivioDeMemoria _instancia = AlivioDeMemoria._();

  static bool _puesto = false;

  /// Se engancha una sola vez, en el arranque.
  static void ensureInitialized() {
    if (_puesto) return;
    _puesto = true;
    WidgetsBinding.instance.addObserver(_instancia);
  }

  /// El techo de la caché de imágenes que le corresponde a ESTE aparato.
  ///
  /// ── Por qué no es el mismo para todos ────────────────────────────────
  ///
  /// Los 220 MB de siempre están calculados para un teléfono actual, y ahí
  /// siguen (el nivel `alto` es escritorio, teléfono y tablet). Pero en un
  /// televisor viejo o un stick barato, el heap que Android le da a una app
  /// entera ronda los 192-256 MB: un techo de 220 MB **solo para imágenes** se
  /// lo come y el sistema termina matando el proceso. Eso es el «se peta» que
  /// se reportó en televisores.
  ///
  /// Y por eso tampoco se pone `largeHeap` en el manifiesto: más heap en un
  /// aparato de 1 GB no da más memoria, hace trabajar más al recolector y
  /// adelanta el momento en que lo matan. Se arregla la causa.
  ///
  /// Se acota también la CANTIDAD de imágenes, no solo los bytes: de fábrica
  /// son 1000 entradas, y mil entradas de contabilidad son otro peso que un
  /// aparato así no tiene por qué llevar.
  ///
  /// Se puede llamar más de una vez sin problema: es un tope, no una reserva.
  /// De hecho se llama dos veces a propósito — una al arrancar, con el valor
  /// de siempre, y otra apenas se sabe qué aparato es esto.
  static void aplicarTechoDeImagenes() {
    final cache = PaintingBinding.instance.imageCache;
    cache.maximumSizeBytes =
        PerfilDeAparato.nivel.elegir(alto: 220, medio: 96, bajo: 48) << 20;
    cache.maximumSize =
        PerfilDeAparato.nivel.elegir(alto: 1000, medio: 400, bajo: 200);
  }

  /// Suelta las imágenes guardadas ANTES de abrir el reproductor.
  ///
  /// ── Por qué no alcanza con esperar a que el sistema pida ────────────
  ///
  /// [didHaveMemoryPressure] es reactivo: Android avisa cuando ya está
  /// corto de memoria, y en un televisor de 1-2 GB ese aviso puede llegar
  /// tarde — o directamente no llegar, porque el matador de procesos actúa
  /// antes. El síntoma que eso deja es el reportado en vivo: la app "se
  /// congela, se reinicia y expulsa al usuario", sin ninguna pantalla de
  /// error de Flutter, que es la firma de un proceso matado por el sistema
  /// y no de una excepción de Dart.
  ///
  /// Abrir un vídeo es justo el peor momento: el usuario viene de recorrer
  /// el catálogo, así que la caché está llena de portadas grandes, y encima
  /// de eso el reproductor va a pedir su colchón de red y su textura de
  /// vídeo, que es lo más pesado que reserva la app.
  ///
  /// Soltar acá no cuesta nada visible: las portadas que hagan falta al
  /// volver se vuelven a decodificar desde disco (siguen en la caché de
  /// archivos, que es otra cosa), y mientras tanto la pantalla que se está
  /// mirando es el vídeo.
  ///
  /// Solo en aparatos modestos: en un teléfono o una PC con memoria de
  /// sobra, tirar la caché sería pagar decodificaciones de más al volver al
  /// catálogo sin ganar nada a cambio.
  static void soltarAntesDeReproducir() {
    if (!PerfilDeAparato.esModesto) return;
    final antes = PaintingBinding.instance.imageCache.currentSizeBytes;
    if (antes == 0) return;
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    logger.info(
      'Antes de reproducir se soltaron '
      '${(antes / (1024 * 1024)).toStringAsFixed(1)} MB de imágenes '
      '(perfil ${PerfilDeAparato.nivel.name})',
    );
  }

  /// Cuántas veces pidió memoria el sistema en esta sesión.
  static int _cuantasVeces = 0;

  /// Cuándo fue la última, para no contar dos veces el mismo apretón.
  static DateTime? _laUltima;

  /// Desde cuántos avisos se considera que el aparato va justo de verdad.
  ///
  /// Uno o dos en una sesión larga es Android haciendo su trabajo. Media
  /// docena es otra cosa: el aparato viene peleando por memoria todo el rato,
  /// y ahí el techo que le pusimos a las imágenes es parte del problema.
  static const _cuandoYaEsDemasiado = 6;

  /// Si ya se bajó el techo por insistencia del sistema.
  static bool _techoBajado = false;

  @override
  void didHaveMemoryPressure() {
    // ── Por qué acá no se mide lo que se soltó ──────────────────────────
    //
    // La versión anterior leía `currentSizeBytes` antes de vaciar y escribía
    // cuántos megas se habían soltado. Salía SIEMPRE «0.0 MB», cientos de
    // veces, y parecía que esto no hacía nada.
    //
    // No era eso. Flutter llama a los observadores DESPUÉS de haber vaciado
    // él mismo la caché de imágenes: en `WidgetsBinding.handleMemoryPressure`
    // lo primero es `super.handleMemoryPressure()` —que en `PaintingBinding`
    // hace `imageCache.clear()`— y recién entonces avisa a los observadores.
    // O sea que cuando esto corre, la caché ya está vacía por definición y
    // ese número no podía dar otra cosa.
    //
    // Lo que de verdad suelta este método es lo OTRO: las imágenes vivas —las
    // que están en pantalla, que son las más grandes y que Flutter no toca— y
    // los dos registros de portadas. Eso es lo que se cuenta ahora.
    final vivas = PaintingBinding.instance.imageCache.liveImageCount;

    // `clear` por si acaso —no cuesta nada y no depende del orden de arriba,
    // que es de Flutter y puede cambiar— y `clearLiveImages`, que es lo que
    // aporta esto: sin ella, las portadas que se están viendo en ese momento
    // no se sueltan, y son justo las que hacen la diferencia cuando el
    // sistema está pidiendo aire.
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    CacheNetWorkImagePic.olvidarLoRecordado();
    PortadasPerdidas.olvidarLoMirado();

    // ── Dos avisos seguidos son un solo apretón ─────────────────────────
    //
    // Android manda `onTrimMemory` con varios niveles a la vez, así que esto
    // llega por parejas separadas por un milisegundo. Contarlas dobles
    // inflaba el número y llenaba el registro de líneas repetidas.
    final ahora = DateTime.now();
    final anterior = _laUltima;
    _laUltima = ahora;
    if (anterior != null &&
        ahora.difference(anterior) < const Duration(seconds: 2)) {
      return;
    }
    _cuantasVeces++;

    // ── Y por qué esto es informativo y no un aviso ─────────────────────
    //
    // Que el sistema pida memoria es normal: pasa cada vez que se abre otra
    // app. Que la nuestra la suelte es la app funcionando bien, no fallando.
    // Marcado como aviso, esto llenaba la zona de «Fallos» con cientos de
    // líneas que no son fallos y enterraba las que sí — en un registro real
    // había catorce errores de verdad perdidos entre doscientos cuarenta y
    // nueve avisos.
    logger.info(
      'El sistema pidió memoria ($_cuantasVeces.ª vez): se soltaron '
      '$vivas imágenes en uso · perfil ${PerfilDeAparato.nivel.name}',
    );

    _bajarElTechoSiInsiste();
  }

  /// Si el sistema insiste, se le baja el techo a las imágenes.
  ///
  /// ── Por qué reaccionar y no solo soltar ─────────────────────────────────
  ///
  /// El techo se elige por el perfil del aparato, que es una estimación hecha
  /// de antemano. Cuando el sistema pide memoria media docena de veces en una
  /// sesión, está diciendo con hechos que esa estimación quedó grande para lo
  /// que hoy tiene libre — puede ser un teléfono capaz con otras diez apps
  /// abiertas, y ahí el perfil no se equivocó, cambió la situación.
  ///
  /// Se baja un escalón y no más: pasar de golpe al mínimo haría que el
  /// catálogo tuviera que redecodificar portadas todo el rato, cambiando un
  /// problema de memoria por uno de fluidez. Y una sola vez por sesión, para
  /// que no se vaya escalonando hasta lo inservible.
  static void _bajarElTechoSiInsiste() {
    if (_techoBajado || _cuantasVeces < _cuandoYaEsDemasiado) return;
    _techoBajado = true;
    final cache = PaintingBinding.instance.imageCache;
    final antes = cache.maximumSizeBytes;
    cache.maximumSizeBytes = (antes * 0.6).round();
    cache.maximumSize = (cache.maximumSize * 0.6).round();
    logger.warning(
      'El sistema pidió memoria $_cuantasVeces veces: se baja el techo de '
      'imágenes de ${antes >> 20} a ${cache.maximumSizeBytes >> 20} MB '
      'para lo que queda de sesión',
    );
  }
}
