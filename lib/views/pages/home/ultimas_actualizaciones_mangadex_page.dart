import 'dart:async';

import 'package:flutter/material.dart';
import 'package:prismhub/models/extension.dart';
import 'package:prismhub/utils/breakpoints.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/views/widgets/extension_item_card.dart';
import 'package:prismhub/views/widgets/home/esqueleto.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/home/tarjeta_de_catalogo.dart';

/// «Últimas actualizaciones» de MangaDex, a pantalla completa.
///
/// ── Para qué, si la fila del Inicio ya la muestra ────────────────────────
///
/// Porque la fila muestra una tanda y se acaba. Esta pantalla es el «ver todo»:
/// la misma sección, en grilla, y siguiendo hacia abajo mientras haya. Es lo
/// que hace el propio sitio cuando se toca el título de su sección.
///
/// ── Por qué de MangaDex y no de cualquiera ───────────────────────────────
///
/// Porque la sección es SUYA: «Últimas actualizaciones» es como MangaDex llama
/// a lo suyo, y cada sitio le dice de otra forma. Las demás van a tener la
/// propia cuando se sumen — a pedido, de a una.
///
/// Y hay un motivo técnico además del nombre: no todas paginan bien su sección
/// de novedades, y una flecha que lleva a una pantalla que se queda en la
/// primera tanda es peor que no tenerla. De MangaDex está medido que la página
/// 2 trae obras distintas de la 1.
class UltimasActualizacionesMangaDexPage extends StatefulWidget {
  const UltimasActualizacionesMangaDexPage({
    super.key,
    required this.titulo,
    this.etiqueta,
  });

  /// El nombre de la extensión, para el encabezado. Llega de la fila en vez de
  /// escribirse acá: si algún día cambia, cambia en un solo lugar.
  final String titulo;

  /// Cómo llama MangaDex a su sección. El nombre lo declara la extensión y lo
  /// traduce el Inicio; acá llega ya resuelto para no repetir esa lógica.
  final String? etiqueta;

  static const paquete = 'io.prismhub.mangadex';

  /// Si ESTA fila es la que tiene esta pantalla.
  static bool disponiblePara(String package) => package == paquete;

  /// Abre la pantalla. Navigator y no Get.to: Get.to no navega en escritorio.
  static void abrir(
    BuildContext context, {
    required String titulo,
    String? etiqueta,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        // SigueElModo: es una pantalla empujada, así que sus colores se leen
        // una sola vez al abrirla. Ver el comentario de home_theme.
        builder: (_) => SigueElModo(
          builder: (_) => UltimasActualizacionesMangaDexPage(
            titulo: titulo,
            etiqueta: etiqueta,
          ),
        ),
      ),
    );
  }

  @override
  State<UltimasActualizacionesMangaDexPage> createState() =>
      _UltimasActualizacionesMangaDexPageState();
}

class _UltimasActualizacionesMangaDexPageState
    extends State<UltimasActualizacionesMangaDexPage> {
  final _scroll = ScrollController();
  final _items = <ExtensionListItem>[];

  /// Las direcciones que ya están, para no repetir una obra.
  final _vistas = <String>{};

  int _pagina = 0;
  bool _trayendo = false;
  bool _sinMas = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_alDesplazar);
    _traer();
  }

  @override
  void dispose() {
    _scroll.removeListener(_alDesplazar);
    _scroll.dispose();
    super.dispose();
  }

  /// Pide la siguiente tanda antes de llegar al fondo.
  ///
  /// Con un margen de una pantalla: esperando a tocar el final, el usuario ve
  /// el vacío y recién ahí empieza la espera. Pidiendo antes, lo nuevo suele
  /// estar puesto para cuando llega.
  void _alDesplazar() {
    if (!_scroll.hasClients || _trayendo || _sinMas) return;
    final falta = _scroll.position.maxScrollExtent - _scroll.offset;
    if (falta < _scroll.position.viewportDimension) _traer();
  }

  Future<void> _traer() async {
    if (_trayendo || _sinMas) return;
    setState(() {
      _trayendo = true;
      _error = null;
    });
    final siguiente = _pagina + 1;
    try {
      final runtime =
          ExtensionUtils.runtimes[UltimasActualizacionesMangaDexPage.paquete];
      if (runtime == null) throw Exception('extension.gone-uninstalled');
      final tanda =
          await runtime.latest(siguiente).timeout(const Duration(seconds: 20));
      if (!mounted) return;
      // Sin repetidos: varias extensiones devuelven alguna obra que ya estaba
      // en la página anterior, y dos tarjetas con la misma clave además rompen
      // la grilla.
      final nuevos =
          tanda.where((e) => !_vistas.contains(e.url)).toList(growable: false);
      setState(() {
        _pagina = siguiente;
        _trayendo = false;
        if (nuevos.isEmpty) {
          // Se acabó. Sin esta marca, una extensión que al pasarse del final
          // devuelve siempre lo mismo pediría para siempre.
          _sinMas = true;
        } else {
          _vistas.addAll(nuevos.map((e) => e.url));
          _items.addAll(nuevos);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _trayendo = false;
        // El error solo corta si NO hay nada que mostrar. Con contenido en
        // pantalla se deja lo que hay y el próximo desplazamiento reintenta:
        // borrar lo que el usuario ya estaba mirando porque falló la página
        // seis es peor que no traer la seis.
        _error = e;
      });
    }
  }

  /// Cuántas columnas entran, y de qué ancho.
  ///
  /// Sale del MISMO ancho de tarjeta que usa el Inicio, así que una portada
  /// mide igual en las dos pantallas y pasar de una a otra no se siente un
  /// cambio de app. Se reparte el sobrante entre las columnas en vez de dejar
  /// un hueco al costado.
  ({int columnas, double ancho}) _rejilla(double disponible) {
    final ideal = TarjetaDeCatalogo.anchoPara(Ancho.de(context));
    const separacion = 16.0;
    final columnas =
        ((disponible + separacion) / (ideal + separacion)).floor().clamp(2, 10);
    final ancho = (disponible - separacion * (columnas - 1)) / columnas;
    return (columnas: columnas, ancho: ancho);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HomeTheme.bg,
      appBar: AppBar(
        backgroundColor: HomeTheme.bg,
        foregroundColor: HomeTheme.textPrimary,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.etiqueta ?? widget.titulo,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
                color: HomeTheme.textPrimary,
              ),
            ),
            // De dónde sale, en chico. El título grande es el de la SECCIÓN,
            // que es lo que se vino a ver; el nombre de la extensión acompaña.
            Text(
              widget.titulo,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: HomeTheme.textMuted,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, caja) {
            const margen = 16.0;
            final disponible = caja.maxWidth - margen * 2;
            if (disponible <= 0) return const SizedBox.shrink();
            final rejilla = _rejilla(disponible);
            // La misma proporción que la tarjeta del Inicio: póster 2:3 más el
            // alto del texto. Si no coincidiera, al llegar el contenido las
            // tarjetas cambiarían de forma respecto a los bloques que esperan.
            final alto = TarjetaDeCatalogo.altoTotalDeAncho(rejilla.ancho);

            // Primera carga: la grilla entera de bloques que brillan. No una
            // rueda: así la pantalla ya tiene la forma que va a tener y al
            // llegar las portadas nada salta de lugar.
            if (_items.isEmpty && _trayendo) {
              return EsqueletoDeGrilla(
                columnas: rejilla.columnas,
                proporcion: rejilla.ancho / alto,
                padding: const EdgeInsets.fromLTRB(margen, 8, margen, 8),
              );
            }

            if (_items.isEmpty) return _sinNada();

            // Una fila más de bloques mientras se trae: dice que hay más en
            // camino sin mover ninguna de las tarjetas que ya están.
            final extra = _trayendo ? rejilla.columnas : 0;
            return GridView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(margen, 8, margen, 24),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: rejilla.columnas,
                childAspectRatio: rejilla.ancho / alto,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemCount: _items.length + extra,
              itemBuilder: (context, i) {
                if (i >= _items.length) {
                  return EsqueletoTarjeta(ancho: rejilla.ancho);
                }
                final item = _items[i];
                return ExtensionItemCard(
                  key: ValueKey(item.url),
                  title: item.title,
                  url: item.url,
                  package: UltimasActualizacionesMangaDexPage.paquete,
                  cover: item.cover,
                  update: item.update,
                  headers: item.headers,
                );
              },
            );
          },
        ),
      ),
    );
  }

  /// Ni contenido ni nada en camino: o falló, o esta sección vino vacía.
  Widget _sinNada() {
    final fallo = _error != null;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              fallo ? Icons.cloud_off_rounded : Icons.inbox_rounded,
              size: 40,
              color: HomeTheme.textMuted,
            ),
            const SizedBox(height: 12),
            Text(
              fallo
                  ? 'No se pudo traer esta sección.'
                  : 'Esta sección no devolvió nada.',
              textAlign: TextAlign.center,
              style: TextStyle(color: HomeTheme.textMuted, fontSize: 13),
            ),
            if (fallo) ...[
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  // La página que falló se vuelve a pedir, no la siguiente: si
                  // no, ese tramo del catálogo se saltearía para siempre.
                  setState(() => _sinMas = false);
                  _traer();
                },
                child: const Text('Reintentar'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
