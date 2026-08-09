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

  /// Lo que se muestra: SOLO la página en la que se está.
  final _items = <ExtensionListItem>[];

  /// En qué página está. Empieza en 1, como la numera el sitio.
  int _pagina = 1;

  /// La página más alta que se comprobó que trae contenido.
  ///
  /// El paginador no puede dibujar «313» como el sitio: la extensión devuelve
  /// una tanda, no cuántas hay en total. Así que los números crecen a medida
  /// que se descubren, y la flecha de avanzar se apaga cuando una página
  /// vuelve vacía. Es menos vistoso que un total, pero es lo que se sabe de
  /// verdad — inventar un número sería peor.
  int _ultimaConocida = 1;

  bool _trayendo = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _traer(1);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _traer(int pagina) async {
    if (_trayendo || pagina < 1) return;
    setState(() {
      _trayendo = true;
      _error = null;
      _pagina = pagina;
    });
    try {
      final runtime =
          ExtensionUtils.runtimes[UltimasActualizacionesMangaDexPage.paquete];
      if (runtime == null) throw Exception('extension.gone-uninstalled');
      final tanda =
          await runtime.latest(pagina).timeout(const Duration(seconds: 20));
      if (!mounted) return;
      // Sin repetidos DENTRO de la tanda: la extensión puede devolver la misma
      // obra dos veces, y dos tarjetas con la misma clave rompen la grilla.
      final vistas = <String>{};
      final limpios =
          tanda.where((e) => vistas.add(e.url)).toList(growable: false);
      setState(() {
        _trayendo = false;
        _items
          ..clear()
          ..addAll(limpios);
        if (limpios.isNotEmpty && pagina > _ultimaConocida) {
          _ultimaConocida = pagina;
        }
        // Una página vacía es el final: se vuelve a la anterior y ahí se corta
        // el avance. Sin esto se quedaría una pantalla en blanco con el
        // paginador ofreciendo seguir.
        if (limpios.isEmpty && pagina > 1) {
          _ultimaConocida = pagina - 1;
          _pagina = pagina - 1;
          // Y se recupera lo que había, que es lo que el usuario estaba
          // mirando antes de tocar «siguiente».
          _traer(_pagina);
        }
      });
      // Arriba de todo: cambiar de página y quedar a media pantalla se lee
      // como que no pasó nada.
      if (_scroll.hasClients) _scroll.jumpTo(0);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _trayendo = false;
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

            // Cargando: la grilla entera de bloques que brillan. No una rueda:
            // así la pantalla ya tiene la forma que va a tener y al llegar las
            // portadas nada salta de lugar. Va también al CAMBIAR de página,
            // no solo la primera vez — es una tanda nueva entera.
            if (_trayendo) {
              return EsqueletoDeGrilla(
                columnas: rejilla.columnas,
                proporcion: rejilla.ancho / alto,
                padding: const EdgeInsets.fromLTRB(margen, 8, margen, 8),
              );
            }

            if (_items.isEmpty) return _sinNada();

            return Column(
              children: [
                Expanded(
                  child: GridView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(margen, 8, margen, 8),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: rejilla.columnas,
                      childAspectRatio: rejilla.ancho / alto,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                    ),
                    itemCount: _items.length,
                    itemBuilder: (context, i) {
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
                  ),
                ),
                _paginador(),
              ],
            );
          },
        ),
      ),
    );
  }

  /// La tira de páginas de abajo: `←  1  2  3  …  →`.
  ///
  /// ── Por qué no dice cuántas hay ─────────────────────────────────────────
  ///
  /// El sitio pone «313» porque su API le dice el total. Acá no llega: la
  /// extensión devuelve una tanda y punto. Así que los números crecen a medida
  /// que se descubren páginas, y el avance se corta cuando una vuelve vacía.
  /// Inventar un total sería peor que no mostrarlo.
  ///
  /// Se muestra una ventana alrededor de la página actual y no todas: con
  /// treinta páginas, treinta números no entran en un teléfono y no ayudan a
  /// nadie.
  Widget _paginador() {
    const ventana = 2;
    final desde = (_pagina - ventana).clamp(1, 1 << 30);
    final hasta = (_pagina + ventana).clamp(1, _ultimaConocida + 1);
    final numeros = [for (var p = desde; p <= hasta; p++) p];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: HomeTheme.bg,
        border: Border(top: BorderSide(color: HomeTheme.border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        // Centrado mientras entre; si son muchas páginas, se desplaza. Sin
        // esto, en un teléfono angosto los números se desbordan.
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _flecha(Icons.arrow_back_rounded,
                _pagina > 1 ? () => _traer(_pagina - 1) : null),
            const SizedBox(width: 4),
            // La primera siempre a mano, aunque se esté en la doce.
            if (desde > 1) ...[
              _numero(1),
              if (desde > 2) _puntos(),
            ],
            for (final p in numeros) _numero(p),
            const SizedBox(width: 4),
            _flecha(Icons.arrow_forward_rounded, () => _traer(_pagina + 1)),
          ],
        ),
      ),
    );
  }

  Widget _puntos() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Text('…', style: TextStyle(color: HomeTheme.textMuted)),
      );

  Widget _numero(int p) {
    final actual = p == _pagina;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Material(
        color: actual ? HomeTheme.accentPink : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: actual ? null : () => _traer(p),
          child: Container(
            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '$p',
              style: TextStyle(
                fontSize: 14,
                fontWeight: actual ? FontWeight.w800 : FontWeight.w600,
                color:
                    actual ? HomeTheme.sobreContraste : HomeTheme.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _flecha(IconData icono, VoidCallback? alTocar) {
    final apagada = alTocar == null;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: alTocar,
        child: Container(
          constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
          alignment: Alignment.center,
          child: Icon(
            icono,
            size: 18,
            color: apagada
                ? HomeTheme.textMuted.withValues(alpha: 0.4)
                : HomeTheme.textPrimary,
          ),
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
                // La página que falló se vuelve a pedir, no la siguiente: si
                // no, ese tramo del catálogo se saltearía para siempre.
                onPressed: () => _traer(_pagina),
                child: const Text('Reintentar'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
