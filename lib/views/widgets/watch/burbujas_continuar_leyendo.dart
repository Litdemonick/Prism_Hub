import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:prismhub/controllers/home_controller.dart';
import 'package:prismhub/models/history.dart';
import 'package:prismhub/models/extension.dart';
import 'package:prismhub/router/router.dart' show rootNavigatorKey;
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/utils/history_cover.dart';
import 'package:prismhub/utils/prismhub_storage.dart';
import 'package:prismhub/utils/platform_tv.dart';
import 'package:prismhub/utils/resume_history.dart';
import 'package:prismhub/utils/router.dart';
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
class BurbujasContinuarLeyendo extends StatefulWidget {
  const BurbujasContinuarLeyendo({
    super.key,
    required this.packageActual,
    required this.urlActual,
    required this.isNsfw,
  });

  /// La obra que se está leyendo ahora — se excluye de la fila, no tiene
  /// sentido ofrecer un salto a donde ya se está.
  final String packageActual;
  final String urlActual;

  /// De qué `HomePageController` sacar "Continuar": el normal, o el de la
  /// Zona +18 (`HomePageController.zoneTag`) si esto es contenido +18. Nunca
  /// se mezclan — ver la separación de zonas en el resto de la app.
  final bool isNsfw;

  @override
  State<BurbujasContinuarLeyendo> createState() =>
      _BurbujasContinuarLeyendoState();
}

class _BurbujasContinuarLeyendoState extends State<BurbujasContinuarLeyendo> {
  /// Colapsar/expandir es de ESTA sesión de lectura nomás — un botón
  /// aparte del interruptor de Ajustes (ese apaga la función entera para
  /// siempre; esto solo la aparta un rato sin tener que ir a buscarlo).
  bool _colapsado = false;

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

  /// Ya se tocó una burbuja y el salto está en curso — dos toques rápidos
  /// (dos burbujas distintas, o la misma dos veces) no tienen que abrir dos
  /// lectores. El widget entero se va a desmontar apenas `closeReader`
  /// haga efecto, así que no hace falta `setState` para volver a `false`.
  bool _saltando = false;

  void _saltarA(History h) {
    if (_saltando) return;
    _saltando = true;
    // Cerrar ACÁ, con el contexto de este lector, y abrir con el del
    // navegador raíz — que sigue montado después de que este cierre. Con el
    // mismo `context` para las dos cosas, `resumeHistoryItem` se encuentra
    // con un `context` ya desmontado (su propio `if (!context.mounted)
    // return` lo corta) y no pasa nada al tocar la burbuja.
    RouterUtils.closeReader(context);
    final rootCtx = rootNavigatorKey.currentContext;
    if (rootCtx != null && rootCtx.mounted) {
      resumeHistoryItem(rootCtx, h);
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
    // por qué escuchar cambios acá — Ajustes está en otra pantalla, y al
    // volver al lector esto se reconstruye solo).
    if (PrismHubStorage.getSetting(SettingKey.burbujasContinuarEnLector) !=
        true) {
      return const SizedBox.shrink();
    }
    final c = Get.find<HomePageController>(tag: tag);
    return Obx(() {
      final otras = _otrasEnCurso(c);
      if (otras.isEmpty) return const SizedBox.shrink();
      final esAndroid = Platform.isAndroid;
      final diametro = esAndroid ? 58.0 : 50.0;
      return Center(
        child: Padding(
          padding: EdgeInsets.only(bottom: esAndroid ? 10 : 8, top: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // La flechita: colapsa la fila sin apagar la función. Sola,
              // centrada arriba de las burbujas — así siempre queda un
              // rastro de que hay más para ver, en vez de desaparecer del
              // todo.
              _BotonColapsar(
                colapsado: _colapsado,
                onTap: () => setState(() => _colapsado = !_colapsado),
              ),
              if (!_colapsado) ...[
                const SizedBox(height: 6),
                SizedBox(
                  height: diametro + 8,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: otras.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, i) => _Burbuja(
                      historia: otras[i],
                      diametro: diametro,
                      onTap: () => _saltarA(otras[i]),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    });
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
    final portada = PortadaHistorial.de(historia);
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
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
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 6,
                ),
              ],
            ),
            child: ClipOval(
              child: Container(
                color: HomeTheme.cardSurface,
                // Icono de por sí: una portada vacía o que no llega no
                // puede dejar la burbuja en blanco — sin la imagen, es la
                // única pista de qué se está por abrir.
                child: (portada.url != null && portada.url!.isNotEmpty)
                    ? CacheNetWorkImagePic(
                        portada.url!,
                        fit: BoxFit.cover,
                        headers: portada.necesitaHeaders
                            ? _cabeceras(historia.package)
                            : null,
                        cacheWidth: (diametro * 2).round(),
                        fallback: const _PortadaFaltante(),
                      )
                    : (portada.archivo != null
                        ? Image.file(
                            portada.archivo!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const _PortadaFaltante(),
                          )
                        : const _PortadaFaltante()),
              ),
            ),
          ),
          const SizedBox(height: 3),
          SizedBox(
            width: diametro + 10,
            child: Text(
              historia.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                shadows: [Shadow(blurRadius: 4, color: Colors.black)],
              ),
            ),
          ),
        ],
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
