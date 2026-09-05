import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:prismhub/controllers/home_controller.dart';
import 'package:prismhub/models/history.dart';
import 'package:prismhub/models/extension.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/utils/history_cover.dart';
import 'package:prismhub/utils/platform_tv.dart';
import 'package:prismhub/utils/prismhub_storage.dart';
import 'package:prismhub/views/widgets/cache_network_image.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';

/// Cabeceras para pedir la portada de una extensión — Referer, si lo
/// declara. Copiado del mismo helper privado que ya existe en home_page.dart
/// y favorites_page.dart: es apenas cuatro líneas y viven en librerías
/// distintas (esta no es `part of` ninguna de las dos), así que reusarlo de
/// verdad costaría importar un archivo enorme para esto solo.
Map<String, String>? _cabeceras(String package) {
  final sitio = ExtensionUtils.runtimes[package]?.extension.webSite;
  if (sitio == null || sitio.isEmpty) return null;
  return {'Referer': sitio};
}

/// Cuánto mide el círculo de una burbuja en la fila, según la plataforma.
///
/// Compartido entre `BurbujasContinuarLeyendo` (que arma la fila) y
/// `ReaderView` (que necesita el mismo número para la vista agrandada,
/// afuera de este widget) — un solo lugar que lo decide, para que las dos
/// vistas nunca queden desincronizadas.
double diametroDeBurbuja(bool esAndroid) => esAndroid ? 70.0 : 72.0;

/// Envuelve la fila (o la vista agrandada) en un `Material` transparente.
///
/// ── Las rayas amarillas debajo del texto ─────────────────────────────────
///
/// No eran overflow. Se persiguieron como si lo fueran durante varias
/// vueltas (reservando alto, achicando con FittedBox, sacando cajas de por
/// medio) y volvían igual — porque el aviso de overflow de Flutter son
/// franjas diagonales amarillas y negras SOBRE el borde que se pasa, y esto
/// era otra cosa: el DOBLE SUBRAYADO AMARILLO que Flutter le pone a
/// cualquier `Text` que no tiene un `Material` por encima.
///
/// Y acá no lo había: las burbujas viven en el `Stack` de `ReaderView`, y el
/// `Scaffold` del lector es HIJO de ese Stack (entra como `content`), no
/// ancestro — o sea que las burbujas son hermanas del Scaffold, no
/// descendientes. En PC no se notaba porque la ruta del lector cuelga de un
/// envoltorio de fluent_ui que sí trae Material más arriba; en Android no
/// hay nada de eso y el subrayado salía siempre.
///
/// `MaterialType.transparency` no dibuja NADA (ni fondo, ni sombra, ni
/// esquinas): solo aporta el contexto que el texto necesita.
Widget _conMaterial(Widget hijo) => Material(
      type: MaterialType.transparency,
      child: hijo,
    );

/// La fila de burbujas para saltar a otra obra de "Continuar leyendo" sin
/// salir del lector actual.
///
/// ── Por qué no mantiene nada vivo ────────────────────────────────────────
///
/// La idea original era algo como pestañas de navegador —cada obra abierta
/// en paralelo, lista para volver—, pero eso significa un `ComicController`
/// (o `NovelController`) completo por cada una, con sus imágenes decodificadas
/// y su motor de extensión vivo, todo el tiempo que la app esté abierta. Es
/// exactamente lo contrario del trabajo de esta semana soltando motores e
/// imágenes agresivamente. Acá no se guarda nada en memoria: tocar una
/// burbuja cierra el lector actual y abre el otro donde había quedado, con
/// el mismo camino que ya usa "Continuar" desde Home (`resumeHistoryItem`,
/// llamado desde `ReaderController.saltarABurbuja`). Se siente igual de
/// instantáneo para quien lo usa, sin el costo.
///
/// ── Por qué vive en `ReaderView` y no en cada lector ─────────────────────
///
/// `ReaderView<T>` es el widget compartido entre el lector de manga y el de
/// novela — puesta acá, la fila funciona en los dos sin duplicar nada, y se
/// oculta/muestra junto con el resto de la interfaz (`isShowControlPanel`)
/// automáticamente.
///
/// ── Por qué "colapsado" viene de afuera ──────────────────────────────────
///
/// No es un `State` propio: `ReaderView` desmonta y vuelve a montar este
/// widget cada vez que se oculta/muestra el resto de los controles (está
/// adentro de un `if`, no de un `Opacity`), así que un booleano guardado
/// acá se reiniciaría en cada ciclo. El valor de verdad vive en
/// `ReaderController.burbujasColapsadas`, que dura toda la sesión de
/// lectura — ver el comentario largo ahí.
///
/// ── Toque directo vs. mantener presionado ────────────────────────────────
///
/// Tocar una burbuja manda DIRECTO a esa obra (pedido explícito). Mantener
/// presionado, en cambio, muestra la vista agrandada — imagen y título
/// completos, centrados en TODO el lector — para decidir sin comprometerse;
/// tocar esa vista agrandada confirma el salto, tocar en cualquier otro
/// lado la cierra. Esa vista vive afuera de este widget (`ReaderView` la
/// dibuja aparte, ver `onPreview`/`ReaderController.burbujaExpandida`) para
/// poder centrarse de verdad en toda la pantalla.
class BurbujasContinuarLeyendo extends StatelessWidget {
  const BurbujasContinuarLeyendo({
    super.key,
    required this.packageActual,
    required this.urlActual,
    required this.isNsfw,
    required this.colapsado,
    required this.onToggleColapsado,
    required this.onTocar,
    required this.onPreview,
  });

  /// La obra que se está leyendo ahora — se excluye de la fila, no tiene
  /// sentido ofrecer un salto a donde ya se está.
  final String packageActual;
  final String urlActual;

  /// De qué `HomePageController` sacar "Continuar": el normal, o el de la
  /// Zona +18 (`HomePageController.zoneTag`) si esto es contenido +18. Nunca
  /// se mezclan — ver la separación de zonas en el resto de la app.
  final bool isNsfw;

  final bool colapsado;
  final VoidCallback onToggleColapsado;

  /// Toque simple: salta directo a esa obra.
  final ValueChanged<History> onTocar;

  /// Mantener presionado: muestra la vista agrandada de esa obra.
  final ValueChanged<History> onPreview;

  List<History> _otrasEnCurso(HomePageController c) {
    final actual = '$packageActual|$urlActual';
    final vistos = <String>{};
    final resultado = <History>[];
    for (final h in c.resents) {
      // El video (bangumi) no entra: esto es para saltar entre lecturas, no
      // para mezclar con lo que se mira en el reproductor. `mixed` sigue
      // adentro a propósito — una extensión mixta puede guardar así una
      // entrada que en verdad es de lectura, y filtrarla del todo dejaría
      // afuera casos válidos; en el peor caso, tocar esa burbuja abre lo
      // que de verdad es (resumeHistoryItem resuelve el tipo real solo).
      if (h.type == ExtensionType.bangumi) continue;
      final clave = '${h.package}|${h.url}';
      if (clave == actual) continue;
      if (!vistos.add(clave)) continue; // misma obra, ya está en la fila
      resultado.add(h);
    }
    return resultado;
  }

  @override
  Widget build(BuildContext context) {
    // En Android TV esto no tiene forma de alcanzarse: las burbujas son
    // círculos sueltos sin FocusNode propio, pensados para tocar o
    // cliquear — con el mando quedarían ahí, sin que nadie pueda llegarles,
    // tapando parte de la pantalla para nada. Mismo criterio que ya usa la
    // pista de "esto se desliza" del carrusel, que tampoco se muestra en TV.
    if (PlatformTv.esTelevisionSync) return const SizedBox.shrink();
    final tag = isNsfw ? HomePageController.zoneTag : null;
    if (!Get.isRegistered<HomePageController>(tag: tag)) {
      return const SizedBox.shrink();
    }
    // Apagado en Ajustes: ni se arma la lista. Se lee en cada build (no hay
    // por qué escuchar cambios acá — Ajustes está en otra pantalla o en el
    // propio panel de ajustes del lector, y al volver esto se reconstruye
    // solo).
    if (PrismHubStorage.getSetting(SettingKey.burbujasContinuarEnLector) !=
        true) {
      return const SizedBox.shrink();
    }
    final c = Get.find<HomePageController>(tag: tag);
    return Obx(() {
      final otras = _otrasEnCurso(c);
      if (otras.isEmpty) return const SizedBox.shrink();
      final esAndroid = Platform.isAndroid;
      return _FilaDeBurbujas(
        otras: otras,
        diametro: diametroDeBurbuja(esAndroid),
        esAndroid: esAndroid,
        colapsado: colapsado,
        onToggleColapsado: onToggleColapsado,
        onTocar: onTocar,
        onPreview: onPreview,
      );
    });
  }
}

class _FilaDeBurbujas extends StatefulWidget {
  const _FilaDeBurbujas({
    required this.otras,
    required this.diametro,
    required this.esAndroid,
    required this.colapsado,
    required this.onToggleColapsado,
    required this.onTocar,
    required this.onPreview,
  });

  final List<History> otras;
  final double diametro;
  final bool esAndroid;
  final bool colapsado;
  final VoidCallback onToggleColapsado;
  final ValueChanged<History> onTocar;
  final ValueChanged<History> onPreview;

  @override
  State<_FilaDeBurbujas> createState() => _FilaDeBurbujasState();
}

class _FilaDeBurbujasState extends State<_FilaDeBurbujas> {
  // Solo hace falta en PC: en Android se desliza con el dedo, igual que
  // cualquier otra fila de la app — agregar flechitas ahí sería un botón
  // más sin ningún gesto nuevo que resolver.
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _correr(int signo) {
    if (!_scroll.hasClients) return;
    final salto = (widget.diametro + 10) * 3;
    _scroll.animateTo(
      (_scroll.offset + salto * signo)
          .clamp(0.0, _scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return _conMaterial(_fila());
  }

  Widget _fila() {
    return Padding(
      // SIN padding izquierdo/derecho acá: pedido explícito, la fila tiene
      // que arrancar del borde izquierdo de la pantalla y llegar hasta el
      // derecho. El respiro para no tapar el contador de página ("12/34",
      // ver _buildBottomBar en comic_reader_content.dart) se resuelve
      // ADENTRO, con el padding propio del ListView (ver más abajo) — así
      // solo se corre el CONTENIDO que desliza, no el ancho de la fila
      // entera (que es lo que necesita también la flechita de colapsar,
      // centrada más abajo contra este mismo ancho completo).
      padding: EdgeInsets.only(bottom: widget.esAndroid ? 10 : 8, top: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Centrada contra el ANCHO COMPLETO del lector, no contra la caja
          // (antes angosta y corrida) del contenido de la fila — reportado
          // en vivo: "queda como hacia un lado". Al no tener este Center
          // ningún padding lateral heredado, coincide con el centro real de
          // la pantalla.
          Center(
            child: _BotonColapsar(
              colapsado: widget.colapsado,
              onTap: widget.onToggleColapsado,
            ),
          ),
          if (!widget.colapsado) ...[
            const SizedBox(height: 6),
            SizedBox(
              // El círculo + el aire de su sombra + los DOS renglones que
              // ahora puede ocupar el título (ver _Burbuja): 4 de separación
              // + 32 de texto + 6 de respiro.
              height: widget.diametro + 42,
              child: Row(
                children: [
                  if (!widget.esAndroid)
                    _FlechitaBurbujas(
                      icono: Icons.chevron_left_rounded,
                      onTap: () => _correr(-1),
                    ),
                  Expanded(
                    // Un insinuado de que hay más para el lado, no un
                    // desvanecido de verdad — reportado en vivo: "no le
                    // pongas esa difuminación tan [fuerte] que ni se ve".
                    // Nunca baja de la mitad de opacidad, y el tramo que se
                    // atenúa es bien angosto (2% de cada lado).
                    child: ShaderMask(
                      shaderCallback: (rect) => LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          Colors.white.withValues(alpha: 0.5),
                          Colors.white,
                          Colors.white,
                          Colors.white.withValues(alpha: 0.5),
                        ],
                        stops: const [0, 0.02, 0.98, 1],
                      ).createShader(rect),
                      blendMode: BlendMode.dstIn,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        controller: _scroll,
                        // El contador de página vive pegado a la esquina
                        // inferior izquierda de la PANTALLA — un padding
                        // más grande solo del lado izquierdo, acá adentro
                        // del scroll, deja la primera burbuja sin taparlo
                        // sin angostar la fila entera (que va de punta a
                        // punta, ver el comentario del Padding de afuera).
                        padding: EdgeInsets.only(
                          left: widget.esAndroid ? 90 : 66,
                          right: 12,
                        ),
                        itemCount: widget.otras.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (context, i) => _Burbuja(
                          historia: widget.otras[i],
                          diametro: widget.diametro,
                          onTap: () => widget.onTocar(widget.otras[i]),
                          onLongPress: () => widget.onPreview(widget.otras[i]),
                        ),
                      ),
                    ),
                  ),
                  if (!widget.esAndroid)
                    _FlechitaBurbujas(
                      icono: Icons.chevron_right_rounded,
                      onTap: () => _correr(1),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Flecha para correr la fila con mouse/teclado en PC — en Android no se
/// dibuja, ahí se desliza con el dedo como cualquier otra fila de la app.
class _FlechitaBurbujas extends StatelessWidget {
  const _FlechitaBurbujas({required this.icono, required this.onTap});

  final IconData icono;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 28,
          height: 28,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black.withValues(alpha: 0.45),
          ),
          child: Icon(icono, size: 18, color: Colors.white),
        ),
      ),
    );
  }
}

class _BotonColapsar extends StatelessWidget {
  const _BotonColapsar({required this.colapsado, required this.onTap});

  final bool colapsado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 32,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(20),
          ),
          child: AnimatedRotation(
            turns: colapsado ? 0.5 : 0,
            duration: const Duration(milliseconds: 200),
            child: const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

/// Una burbuja de la fila: el círculo con la portada y el título debajo.
class _Burbuja extends StatelessWidget {
  const _Burbuja({
    required this.historia,
    required this.diametro,
    required this.onTap,
    required this.onLongPress,
  });

  final History historia;
  final double diametro;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: SizedBox(
        width: diametro + 26,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CirculoDePortada(historia: historia, diametro: diametro),
            const SizedBox(height: 4),
            // ── Tamaño fijo, no "lo que entre" ──────────────────────────
            //
            // Antes esto era un FittedBox que achicaba el título hasta que
            // entrara en un solo renglón — o sea que cuanto MÁS largo el
            // nombre, más chico se veía, y con un título largo terminaba
            // ilegible. Reportado en vivo: "se ve diminuto, no sé qué
            // dice". Ahora la letra mide siempre lo mismo (que es lo que
            // se puede leer) y lo que sobra se corta con puntos suspensivos
            // después de dos renglones — se lee el principio del nombre,
            // que alcanza para reconocerlo, en vez de todo el nombre
            // ilegible.
            //
            // El fondo oscuro es para que el texto se lea SIEMPRE: esto
            // flota sobre la página del manga, que puede ser blanca,
            // clara o llena de detalle. Con solo una sombra alrededor
            // había fondos donde el título se perdía.
            SizedBox(
              height: 32,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                child: Text(
                  historia.title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1.15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// El círculo con la portada — compartido entre la fila y la vista
/// expandida, para que sea EXACTAMENTE el mismo dibujo en los dos casos.
class _CirculoDePortada extends StatelessWidget {
  const _CirculoDePortada({
    required this.historia,
    required this.diametro,
    this.anchoDeCache,
  });

  final History historia;
  final double diametro;

  /// Ancho de decodificación a usar en vez del que sale de [diametro].
  ///
  /// Lo usa la vista expandida (`BurbujaExpandidaOverlay`, reader_view.dart)
  /// para pedir la imagen al MISMO ancho que ya pidió la fila (`diametro`
  /// de ahí, no el 2.6x de acá) — así reutiliza la entrada de caché que la
  /// fila ya dejó cargada en vez de disparar una descarga/decodificación
  /// nueva solo porque el círculo se ve más grande. La calidad se resigna
  /// un poco (una imagen chica estirada), pero es una vista temporal que
  /// dura lo que tarda en decidirse — no vale la pena una descarga extra
  /// por eso.
  final int? anchoDeCache;

  @override
  Widget build(BuildContext context) {
    final portada = PortadaHistorial.de(historia);
    return Container(
      width: diametro,
      height: diametro,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            HomeTheme.accentPink,
            HomeTheme.accentPink.withValues(alpha: 0.35),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 6),
        ],
      ),
      child: ClipOval(
        child: Container(
          color: HomeTheme.cardSurface,
          // Ícono de por sí: una portada vacía o que no llega no puede
          // dejar la burbuja en blanco — sin la imagen, es la única pista
          // de qué se está por abrir.
          child: (portada.url != null && portada.url!.isNotEmpty)
              ? CacheNetWorkImagePic(
                  portada.url!,
                  fit: BoxFit.cover,
                  headers: portada.necesitaHeaders
                      ? _cabeceras(historia.package)
                      : null,
                  cacheWidth: anchoDeCache ?? (diametro * 3).round(),
                  fallback: const _PortadaFaltante(),
                )
              : (portada.archivo != null
                  ? Image.file(
                      portada.archivo!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const _PortadaFaltante(),
                    )
                  : const _PortadaFaltante()),
        ),
      ),
    );
  }
}

/// La vista grande al mantener presionada una burbuja: se agranda para ver
/// bien la portada y el título completo, centrada en TODO el lector — no en
/// la franja de abajo donde vive la fila (pedido explícito, antes quedaba
/// "hacia un lado" porque solo tenía dónde centrarse ahí). Tocarla confirma
/// el salto; tocar en cualquier otro lado la cierra sin hacer nada, como
/// cancelar. Vive en `ReaderView`, no en `BurbujasContinuarLeyendo` — ver el
/// comentario largo de esa clase.
class BurbujaExpandidaOverlay extends StatelessWidget {
  const BurbujaExpandidaOverlay({
    super.key,
    required this.historia,
    required this.diametroFila,
    required this.onConfirmar,
    required this.onCancelar,
  });

  final History historia;

  /// El diámetro que la burbuja tiene en la FILA (56-68px según
  /// plataforma) — de ahí sale tanto el tamaño final agrandado (un
  /// múltiplo fijo de este) como el ancho de caché a reutilizar (ver
  /// `_CirculoDePortada.anchoDeCache`).
  final double diametroFila;

  final VoidCallback onConfirmar;
  final VoidCallback onCancelar;

  @override
  Widget build(BuildContext context) {
    final diametroGrande = diametroFila * 2.6;
    // El fondo entero (tocar afuera) cancela; el contenido de adentro tiene
    // su PROPIO GestureDetector que confirma y, con `opaque`, se queda con
    // el toque antes de que le llegue al de afuera — sin esto, tocar la
    // burbuja agrandada cancelaría Y confirmaría a la vez.
    return Positioned.fill(
      // Mismo motivo que en la fila: sin un Material por encima, Flutter le
      // pone doble subrayado amarillo al título — ver _conMaterial.
      child: _conMaterial(
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onCancelar,
          child: Container(
            // Bien liviano a propósito: en el lector de cómic esto puede
            // coincidir con el contador de página ("2/34") — un fondo oscuro
            // de verdad lo tapaba justo mientras más se necesita ver que
            // sigue ahí. Reportado con foto. Con esto tan tenue el círculo
            // igual se destaca (crece y tiene su propio marco/sombra), pero
            // no esconde nada detrás.
            color: Colors.black.withValues(alpha: 0.12),
            alignment: Alignment.center,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onConfirmar,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── Por qué Transform.scale y no reconstruir más grande ──
                    //
                    // Antes esto era un `TweenAnimationBuilder<double>` que
                    // reconstruía `_CirculoDePortada` con un `diametro`
                    // DISTINTO en cada frame de la animación (220ms, ~13
                    // frames) — y como `cacheWidth` sale de `diametro`, cada
                    // frame pedía la imagen decodificada a un tamaño nuevo:
                    // se veía recargar/parpadear durante todo el agrandado.
                    // Reportado en vivo más de una vez.
                    //
                    // Ahora el círculo se construye UNA sola vez, ya al
                    // tamaño final Y con el `anchoDeCache` de la FILA (no el
                    // suyo propio, más grande) — mismo ancho, misma clave de
                    // caché, la MISMA imagen que la fila ya tiene decodificada
                    // se reusa tal cual. Lo que anima es solo la ESCALA
                    // (`Transform.scale`), una operación de pintado que no
                    // toca la red ni el decodificador para nada.
                    TweenAnimationBuilder<double>(
                      tween: Tween(
                        begin: diametroFila / diametroGrande,
                        end: 1.0,
                      ),
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      child: _CirculoDePortada(
                        historia: historia,
                        diametro: diametroGrande,
                        anchoDeCache: (diametroFila * 3).round(),
                      ),
                      builder: (context, escala, child) =>
                          Transform.scale(scale: escala, child: child),
                    ),
                    const SizedBox(height: 12),
                    // Fondo sólido, no una sombra: esto se dibuja sobre la
                    // página del manga, que puede ser blanca — con texto
                    // blanco y solo sombra alrededor, el título desaparecía
                    // del todo ahí. Reportado en vivo con foto.
                    Container(
                      constraints: const BoxConstraints(maxWidth: 260),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        historia.title,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lo que se ve dentro de la burbuja cuando la portada no llegó — vacía,
/// el archivo local ya no existe, o la red falló. Un ícono genérico, no un
/// hueco en blanco: sigue siendo un botón, aunque no se sepa de qué obra.
class _PortadaFaltante extends StatelessWidget {
  const _PortadaFaltante();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: HomeTheme.cardSurface,
      child: Icon(
        Icons.menu_book_rounded,
        color: HomeTheme.textMuted,
        size: 20,
      ),
    );
  }
}
