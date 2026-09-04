import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:prismhub/controllers/home_controller.dart';
import 'package:prismhub/models/history.dart';
import 'package:prismhub/models/extension.dart';
import 'package:prismhub/router/router.dart' show currentContext;
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/utils/history_cover.dart';
import 'package:prismhub/utils/platform_tv.dart';
import 'package:prismhub/utils/prismhub_storage.dart';
import 'package:prismhub/utils/resume_history.dart';
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
/// el mismo camino que ya usa "Continuar" desde Home (`resumeHistoryItem`).
/// Se siente igual de instantáneo para quien lo usa, sin el costo.
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
class BurbujasContinuarLeyendo extends StatefulWidget {
  const BurbujasContinuarLeyendo({
    super.key,
    required this.packageActual,
    required this.urlActual,
    required this.isNsfw,
    required this.colapsado,
    required this.onToggleColapsado,
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

  @override
  State<BurbujasContinuarLeyendo> createState() =>
      _BurbujasContinuarLeyendoState();
}

class _BurbujasContinuarLeyendoState extends State<BurbujasContinuarLeyendo> {
  /// Ya se tocó una burbuja y el salto está en curso — dos toques rápidos
  /// (dos burbujas distintas, o la misma dos veces) no tienen que abrir dos
  /// lectores.
  bool _saltando = false;

  /// Cuál burbuja está en medio de la animación de "se agranda en el
  /// centro" — null si ninguna. Mientras tanto la fila normal se esconde y
  /// se dibuja el círculo grande encima de todo.
  History? _expandiendo;

  List<History> _otrasEnCurso(HomePageController c) {
    final actual = '${widget.packageActual}|${widget.urlActual}';
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

  Future<void> _saltarA(History h) async {
    if (_saltando) return;
    // Todo lo que necesita el `context` de ESTE widget se saca ANTES de
    // cualquier `await` — un `Navigator`/`ModalRoute` no cambia de
    // significado con el tiempo, así que no hay ganancia en pedirlos más
    // tarde, y sí el riesgo de terminar usando un `context` de un widget
    // que ya se desmontó.
    final rutaVieja = ModalRoute.of(context);
    final navegadorDeEsteLector = Navigator.of(context, rootNavigator: true);
    setState(() {
      _saltando = true;
      _expandiendo = h;
    });
    // La animación de agrandarse, primero — nada más. `resumeHistoryItem`
    // recién se llama después de que se alcanza a VER el círculo grande.
    await Future<void>.delayed(const Duration(milliseconds: 260));
    if (!mounted) return;

    // ── Por qué `currentContext` y no el `context` de este widget ────────
    //
    // `resumeHistoryItem` empuja la ruta nueva con
    // `Navigator.of(context, rootNavigator: true)` — y "raíz" es relativo a
    // DESDE QUÉ `context` se lo pida: en Android el lector se abre sobre el
    // Navigator propio de GetX (`Get.context`), no sobre el de go_router
    // (`rootNavigatorKey`), así que pasarle el `context` de go_router
    // empujaba la obra nueva a una pila que no es la que se está mirando —
    // el lector se cerraba (eso sí pasaba) pero la obra nueva quedaba
    // abierta en otro lado, invisible. `currentContext` (router.dart) ya
    // resuelve esta diferencia por plataforma; es el mismo que usa el resto
    // de la app para esto. Es un getter, no un `context` capturado antes
    // del `await`: cada lectura devuelve el de ESE momento, así que el
    // aviso de "no uses un context después de un async gap" no aplica acá.
    // ignore: use_build_context_synchronously
    await resumeHistoryItem(currentContext, h);
    if (!mounted) return;
    // ── Empuja PRIMERO, cierra DESPUÉS ────────────────────────────────────
    //
    // Al revés —cerrar este lector y recién ahí abrir el otro— hay un
    // instante en el medio sin nada válido que mostrar si algo del camino
    // de apertura tarda (red, chequeo de actualización pendiente). Abriendo
    // primero, lo peor que puede pasar es quedar con las dos rutas un
    // instante; se saca la vieja apenas la nueva ya está en camino. El
    // `Navigator` se guardó ANTES del primer `await` a propósito: es el
    // mismo objeto de siempre, no depende de que este `context` siga vivo.
    if (rutaVieja != null && rutaVieja.isActive) {
      navegadorDeEsteLector.removeRoute(rutaVieja);
    }
  }

  @override
  Widget build(BuildContext context) {
    // En Android TV esto no tiene forma de alcanzarse: las burbujas son
    // círculos sueltos sin FocusNode propio, pensados para tocar o
    // cliquear — con el mando quedarían ahí, sin que nadie pueda llegarles,
    // tapando parte de la pantalla para nada. Mismo criterio que ya usa la
    // pista de "esto se desliza" del carrusel, que tampoco se muestra en TV.
    if (PlatformTv.esTelevisionSync) return const SizedBox.shrink();
    final tag = widget.isNsfw ? HomePageController.zoneTag : null;
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
      final diametro = esAndroid ? 56.0 : 48.0;
      return Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          if (_expandiendo == null)
            _FilaDeBurbujas(
              otras: otras,
              diametro: diametro,
              esAndroid: esAndroid,
              colapsado: widget.colapsado,
              onToggleColapsado: widget.onToggleColapsado,
              onTocar: _saltarA,
            ),
          if (_expandiendo != null)
            _BurbujaExpandida(historia: _expandiendo!, diametro: diametro),
        ],
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
  });

  final List<History> otras;
  final double diametro;
  final bool esAndroid;
  final bool colapsado;
  final VoidCallback onToggleColapsado;
  final ValueChanged<History> onTocar;

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
    return Padding(
      // El contador de página ("12/34") vive pegado a la esquina inferior
      // izquierda (ver comic_reader_content.dart, _buildBottomBar) en su
      // propia capa, sin saber nada de esto. En un celular angosto una fila
      // centrada de punta a punta le pasa por encima. 96 de margen es más
      // que de sobra para ese contador (nunca pasa de 3-4 dígitos por
      // lado) sin robarle a la fila más espacio del necesario.
      padding: EdgeInsets.only(
        left: widget.esAndroid ? 96 : 16,
        right: 16,
        bottom: widget.esAndroid ? 10 : 8,
        top: 4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _BotonColapsar(
            colapsado: widget.colapsado,
            onTap: widget.onToggleColapsado,
          ),
          if (!widget.colapsado) ...[
            const SizedBox(height: 6),
            SizedBox(
              height: widget.diametro + 8,
              child: Row(
                children: [
                  if (!widget.esAndroid)
                    _FlechitaBurbujas(
                      icono: Icons.chevron_left_rounded,
                      onTap: () => _correr(-1),
                    ),
                  Expanded(
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      controller: _scroll,
                      itemCount: widget.otras.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (context, i) => _Burbuja(
                        historia: widget.otras[i],
                        diametro: widget.diametro,
                        onTap: () => widget.onTocar(widget.otras[i]),
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

/// Una burbuja de la fila — solo el círculo con la portada. El título NO va
/// acá abajo a texto fijo: a este tamaño (48-56px) una sola línea de título
/// completo no entra sin desbordar, y es justo lo que se reportó como una
/// raya amarilla en Android (el aviso de overflow de Flutter). El título se
/// ve al tocar, en `_BurbujaExpandida`, donde sí hay sitio para mostrarlo
/// entero.
class _Burbuja extends StatelessWidget {
  const _Burbuja({
    required this.historia,
    required this.diametro,
    required this.onTap,
  });

  final History historia;
  final double diametro;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: _CirculoDePortada(historia: historia, diametro: diametro),
    );
  }
}

/// El círculo con la portada — compartido entre la fila y la vista
/// expandida, para que sea EXACTAMENTE el mismo dibujo en los dos casos y
/// la animación de agrandarse se sienta continua.
class _CirculoDePortada extends StatelessWidget {
  const _CirculoDePortada({required this.historia, required this.diametro});

  final History historia;
  final double diametro;

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
                  cacheWidth: (diametro * 3).round(),
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

/// Lo que se ve al tocar una burbuja: el mismo círculo, grande, en el medio
/// de la pantalla, con el título completo debajo — y de ahí, un instante
/// después, sigue el salto de verdad al otro lector.
class _BurbujaExpandida extends StatelessWidget {
  const _BurbujaExpandida({required this.historia, required this.diametro});

  final History historia;
  final double diametro;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: diametro, end: diametro * 2.6),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        builder: (context, tam, child) => Container(
          color: Colors.black.withValues(alpha: 0.55),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _CirculoDePortada(historia: historia, diametro: tam),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: Text(
                  historia.title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    shadows: [Shadow(blurRadius: 6, color: Colors.black)],
                  ),
                ),
              ),
            ],
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
