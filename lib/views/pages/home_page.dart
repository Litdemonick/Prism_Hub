import 'dart:async';

import 'package:flutter/material.dart';
import 'package:prismhub/utils/breakpoints.dart';
import 'package:get/get.dart';
import 'package:prismhub/controllers/catalogo_extensiones_controller.dart';
import 'package:prismhub/models/index.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/views/widgets/cache_network_image.dart';
import 'package:prismhub/views/widgets/home/animated_background_glow.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/home/tarjeta_de_catalogo.dart';
import 'package:prismhub/views/widgets/progress.dart';

/// El Home: **descubrir, con lo que traen tus extensiones**.
///
/// ── Por qué está partido de la Biblioteca ─────────────────────────────────
///
/// Antes Home era «lo mío»: Continuar viendo y Favoritos. Eso pasó tal cual a
/// `library_page.dart`. Lo que cambió es que ahora cada pantalla tiene una
/// regla clara sobre estar vacía:
///
///   Biblioteca vacía  →  está bien. Todavía no viste nada.
///   Home vacío        →  está mal. Es la pantalla de descubrir.
///
/// Acá NO va «Seguir viendo»: eso ya vive en Biblioteca y repetirlo sería
/// gastar la mejor franja de la pantalla en algo que el usuario ya tiene a un
/// toque.
///
/// ── Cómo aguanta muchas extensiones ───────────────────────────────────────
///
/// Todo el trabajo pesado está en [CatalogoExtensionesController]: nada se
/// pide hasta que se ve, ninguna fila espera a otra, tope de tres a la vez,
/// caché en disco y una fila caída no rompe el resto. Acá solo se dibuja.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // Se reusa si ya existe: en Android, cambiar de pestaña reconstruye la
  // página entera, y crear otro tiraría el catálogo ya cargado.
  late final CatalogoExtensionesController c =
      Get.isRegistered<CatalogoExtensionesController>()
          ? Get.find<CatalogoExtensionesController>()
          : Get.put(CatalogoExtensionesController());

  @override
  Widget build(BuildContext context) {
    return Container(
      color: HomeTheme.bg,
      child: Stack(
        children: [
          const Positioned.fill(child: AnimatedBackgroundGlow()),
          // ── El carrusel llega hasta arriba de todo ──────────────────────
          //
          // `top: false` a propósito: sin eso, el SafeArea empujaba TODO hacia
          // abajo y quedaba una franja negra entre la barra de estado y la
          // imagen. Ahora el carrusel sube hasta el borde de la pantalla y
          // pasa por detrás de la hora y la batería, que es como se ve en
          // cualquier app de streaming.
          //
          // El texto del carrusel no corre peligro: va anclado ABAJO, lejos de
          // la barra. Igual se le pasa su altura como relleno superior, por si
          // alguna vez sube.
          //
          // Los costados y el borde de abajo sí se respetan — ahí viven los
          // gestos del sistema y la barra de navegación.
          SafeArea(
            top: false,
            child: Obx(() {
              if (c.filas.isEmpty) return _sinExtensiones();
              return RefreshIndicator(
                onRefresh: c.refrescarTodo,
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 36),
                  // +1 por el carrusel de arriba.
                  itemCount: c.filas.length + 1,
                  // **Acá está la carga perezosa.** ListView.builder solo
                  // construye lo que está cerca de la pantalla, y cada fila
                  // pide en su initState — así, con 30 extensiones se piden
                  // las 2 o 3 que se ven, no las 30.
                  itemBuilder: (context, i) => i == 0
                      ? _CarruselDestacados(c: c)
                      : _FilaDeExtensionVista(
                          key: ValueKey(c.filas[i - 1].package),
                          c: c,
                          fila: c.filas[i - 1],
                        ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _sinExtensiones() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.extension_outlined,
                size: 44, color: HomeTheme.textMuted),
            const SizedBox(height: 14),
            Text(
              'home.sin-extensiones'.i18n,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                height: 1.45,
                color: HomeTheme.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// El carrusel grande de arriba, que va cambiando solo.
///
/// Se alimenta de lo que van trayendo las extensiones, así que empieza vacío y
/// se llena al toque. **No se reserva su alto cuando no hay nada**: un hueco
/// negro de media pantalla al abrir se ve peor que empezar directo por las
/// filas.
class _CarruselDestacados extends StatefulWidget {
  const _CarruselDestacados({required this.c});

  final CatalogoExtensionesController c;

  @override
  State<_CarruselDestacados> createState() => _CarruselDestacadosState();
}

class _CarruselDestacadosState extends State<_CarruselDestacados> {
  Timer? _reloj;

  // La posición NO se guarda acá: vive en el controlador. Este widget se
  // reconstruye al volver a la pestaña, así que un índice propio se perdía y el
  // carrusel volvía a empezar siempre por la misma extensión. Ver
  // CatalogoExtensionesController.carruselExt.

  @override
  void initState() {
    super.initState();
    // Ocho segundos: menos alcanza a cortar la lectura del título, y más se
    // siente una imagen fija.
    _reloj = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!mounted) return;
      setState(widget.c.avanzarCarrusel);
    });
  }

  @override
  void dispose() {
    _reloj?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final grupos = widget.c.destacados;
      if (grupos.isEmpty) return const SizedBox(height: 12);
      final (package, items) = grupos[widget.c.carruselExt % grupos.length];
      if (items.isEmpty) return const SizedBox(height: 12);
      final item = items[widget.c.carruselPos % items.length];
      final a = Ancho.de(context);
      // El alto sale del ANCHO disponible, no de la altura: en una ventana
      // ancha y baja —una laptop, o el escritorio a media pantalla— reservar
      // un porcentaje del alto dejaba el carrusel aplastado. Y se acota al
      // alto real para que en horizontal de teléfono no se coma la pantalla.
      // Lo que ocupa la barra de estado. En escritorio es cero.
      final barra = MediaQuery.paddingOf(context).top;
      // El alto sale del ANCHO disponible, no de la altura: en una ventana
      // ancha y baja —una laptop, o el escritorio a media pantalla— reservar
      // un porcentaje del alto dejaba el carrusel aplastado. Y se acota al
      // alto real para que en horizontal de teléfono no se coma la pantalla.
      //
      // Se le SUMA la barra: la imagen crece para pasar por detrás de ella en
      // vez de perder esa franja, así el carrusel se sigue viendo del mismo
      // tamaño que si la barra no existiera.
      final alto = (MediaQuery.sizeOf(context).width *
                  a.elegir(compacto: 0.62, medio: 0.42, amplio: 0.30, enorme: 0.24))
              .clamp(200.0, MediaQuery.sizeOf(context).height * 0.62) +
          barra;

      return SizedBox(
        height: alto,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── La imagen se DESVANECE, no se tapa ────────────────────────
            //
            // Antes el borde de abajo se cubría con un degradado que terminaba
            // en el color de fondo, opaco. Eso dejaba una línea horizontal
            // visible cruzando toda la pantalla: arriba de esa línea el
            // degradado tapaba el fondo animado y abajo no, así que el brillo
            // aparecía de golpe.
            //
            // Con una máscara, lo que se apaga es la propia imagen: su
            // transparencia baja a cero hacia abajo y lo que hay detrás —el
            // fondo animado— se ve igual a los dos lados del borde. No hay
            // línea porque no hay borde.
            ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (rect) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.white, Colors.white, Colors.transparent],
                stops: [0.0, 0.55, 1.0],
              ).createShader(rect),
              child: Stack(
                fit: StackFit.expand,
                children: [
            // El cruce entre imágenes va por la clave: al cambiar el índice,
            // AnimatedSwitcher entiende que es otro hijo y hace el fundido.
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 600),
              child: SizedBox.expand(
                key: ValueKey(item.url),
                child: CacheNetWorkImagePic(
                  item.cover ?? '',
                  fit: BoxFit.cover,
                  headers: _cabeceras(package),
                  placeholder: const ColoredBox(color: HomeTheme.cardSurface),
                  fallback: const ColoredBox(color: HomeTheme.cardSurface),
                ),
              ),
            ),
                  // Oscurece hacia abajo y hacia la izquierda para que el
                  // texto se lea sobre cualquier portada. Los dos son
                  // TRANSLÚCIDOS: si alguno terminara en un color opaco,
                  // volvería la línea que este bloque vino a sacar.
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Color(0xD90A0A12), Color(0x000A0A12)],
                        stops: [0.0, 0.72],
                      ),
                    ),
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [Color(0xE60A0A12), Color(0x000A0A12)],
                        stops: [0.0, 0.7],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                    _margen(context), barra, _margen(context), 26),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ExtensionUtils.runtimes[package]?.extension.name ?? '',
                        style: const TextStyle(
                          fontSize: 11.5,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w700,
                          color: HomeTheme.accentPink,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize:
                              a.elegir(compacto: 21, medio: 26, amplio: 34),
                          height: 1.15,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _Indicadores(
                        cantidad: items.length,
                        actual: widget.c.carruselPos % items.length,
                        onTocar: (i) =>
                            setState(() => widget.c.carruselPos = i),
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: () => _abrir(context, item, package),
                        icon: const Icon(Icons.play_arrow_rounded, size: 22),
                        label: Text('home.view-detail'.i18n),
                        style: FilledButton.styleFrom(
                          backgroundColor: HomeTheme.accentPink,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(
                            horizontal: a.elegir(compacto: 18, amplio: 22),
                            vertical: a.elegir(compacto: 12, amplio: 14),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }
}

/// Una fila: el nombre de la extensión y lo último que tiene.
class _FilaDeExtensionVista extends StatefulWidget {
  const _FilaDeExtensionVista({
    super.key,
    required this.c,
    required this.fila,
  });

  final CatalogoExtensionesController c;
  final FilaDeExtension fila;

  @override
  State<_FilaDeExtensionVista> createState() => _FilaDeExtensionVistaState();
}

class _FilaDeExtensionVistaState extends State<_FilaDeExtensionVista> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Desplaza la fila una pantalla, sin pasarse de los extremos.
  void _correr(int signo) {
    if (!_scroll.hasClients) return;
    final salto = _scroll.position.viewportDimension * 0.8;
    _scroll.animateTo(
      (_scroll.offset + salto * signo)
          .clamp(0.0, _scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void initState() {
    super.initState();
    // **Acá se dispara la carga perezosa.** Este initState corre recién cuando
    // ListView.builder construye la fila, o sea cuando está por entrar en
    // pantalla. Lo que nunca se ve, nunca se pide.
    widget.c.pedirSiHaceFalta(widget.fila);
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final estado = widget.fila.estado.value;
      final items = widget.fila.items;

      // Ni cargando ni con contenido: no se dibuja NADA, ni siquiera el
      // título. Una fila con nombre y vacía debajo se lee como un error.
      if (estado == EstadoDeFila.fallo && items.isEmpty) {
        return _sinRespuesta();
      }

      return Padding(
        padding: const EdgeInsets.only(top: 26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _encabezado(),
            const SizedBox(height: 14),
            SizedBox(
              // Aire de más para la sombra.
              //
              // La tarjeta crece y se le dibuja una sombra al pasar el mouse, y
              // las dos cosas se salen de su caja. Con el alto justo, la fila
              // recortaba contra su borde y la sombra aparecía cortada en
              // línea recta — se veía peor que no tenerla.
              height:
                  TarjetaDeCatalogo.altoTotalPara(Ancho.de(context)) + 28,
              child: (items.isEmpty && estado == EstadoDeFila.cargando)
                  ? const Center(child: ProgressRing())
                  : ListView.separated(
                      controller: _scroll,
                      scrollDirection: Axis.horizontal,
                      // Sin esto el recorte se come la sombra igual, por más
                      // aire que se le dé: un ListView recorta en su borde
                      // por defecto.
                      clipBehavior: Clip.none,
                      padding:
                          EdgeInsets.symmetric(horizontal: _margen(context)),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 14),
                      itemBuilder: (context, i) {
                        final item = items[i];
                        return Padding(
                          // Arriba, para que la tarjeta tenga hacia dónde
                          // crecer sin pisar el título de la fila.
                          padding: const EdgeInsets.only(top: 10),
                          child: TarjetaDeCatalogo(
                          titulo: item.title,
                          portada: item.cover,
                          cabeceras: _cabeceras(widget.fila.package),
                          encabezado: widget.fila.nombre,
                          // `update` es lo único con forma de fecha que
                          // devuelve `latest()`. Cada extensión lo escribe a su
                          // manera —«hace 2 días», «Ep 12», una fecha— así que
                          // se muestra TAL CUAL: normalizarlo acá sería
                          // inventar una precisión que el dato no tiene.
                          fecha: item.update,
                            onTap: () =>
                                _abrir(context, item, widget.fila.package),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      );
    });
  }

  Widget _encabezado() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: _margen(context)),
      child: Row(
        children: [
          Expanded(
            child: Text(
              widget.fila.nombre,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: Ancho.de(context)
                    .elegir(compacto: 17, medio: 19, amplio: 22),
                fontWeight: FontWeight.w800,
                color: HomeTheme.textPrimary,
                letterSpacing: -0.2,
              ),
            ),
          ),
          // Flechas para recorrer la fila. Solo donde hay mouse: en una
          // pantalla táctil se arrastra con el dedo y las flechas solo taparían
          // portadas.
          //
          // El botón de actualizar se sacó: la fila ya se refresca sola cuando
          // vence el caché y tirando de la pantalla hacia abajo. Un ícono más
          // en cada encabezado era ruido repetido diecisiete veces.
          if (Ancho.de(context).alMenosAmplio) ...[
            _FlechaDeFila(
                icono: Icons.chevron_left_rounded,
                onTap: () => _correr(-1)),
            const SizedBox(width: 4),
            _FlechaDeFila(
                icono: Icons.chevron_right_rounded,
                onTap: () => _correr(1)),
          ],
        ],
      ),
    );
  }

  /// La extensión no respondió y no hay nada guardado que mostrar.
  ///
  /// Se deja una línea discreta con su botón: esconderla del todo haría que el
  /// usuario no entienda por qué falta una extensión que sabe que instaló.
  Widget _sinRespuesta() {
    return Padding(
      padding: EdgeInsets.fromLTRB(_margen(context), 22, _margen(context), 0),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded,
              size: 16, color: HomeTheme.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${widget.fila.nombre} · ${'home.fila-sin-respuesta'.i18n}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 12.5, color: HomeTheme.textMuted),
            ),
          ),
          TextButton(
            onPressed: () =>
                widget.c.pedirSiHaceFalta(widget.fila, forzar: true),
            child: Text('common.retry'.i18n),
          ),
        ],
      ),
    );
  }
}

// ─── Piezas compartidas ──────────────────────────────────────────────────────

/// Las rayitas que dicen en cuál de la tanda vas.
///
/// Rayas y no puntos: con puntos, cinco posiciones se leen como cinco puntos
/// sueltos y no como una barra de avance. La raya llena ocupa lugar y se
/// entiende de un vistazo cuánto queda de la tanda.
///
/// Se pueden tocar para saltar directo. Es un objetivo chiquito, así que cada
/// una lleva un área de toque más grande que la raya que se ve.
class _Indicadores extends StatelessWidget {
  const _Indicadores({
    required this.cantidad,
    required this.actual,
    required this.onTocar,
  });

  final int cantidad;
  final int actual;
  final ValueChanged<int> onTocar;

  @override
  Widget build(BuildContext context) {
    // Con una sola no hay nada que indicar.
    if (cantidad < 2) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < cantidad; i++)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onTocar(i),
            child: Padding(
              // El aire va ADENTRO del área de toque, no entre widgets: así lo
              // que se puede tocar es más grande que la raya sin que las rayas
              // queden separadas de más.
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                width: i == actual ? 30 : 20,
                height: 3,
                decoration: BoxDecoration(
                  color: i == actual
                      ? HomeTheme.accentPink
                      : Colors.white.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Una flecha para recorrer una fila.
///
/// Discreta hasta que se la toca: sobre un fondo de portadas, un botón con
/// relleno propio compite con las tarjetas. Se enciende al pasar el mouse, que
/// es cuando el usuario la está buscando.
class _FlechaDeFila extends StatefulWidget {
  const _FlechaDeFila({required this.icono, required this.onTap});

  final IconData icono;
  final VoidCallback onTap;

  @override
  State<_FlechaDeFila> createState() => _FlechaDeFilaState();
}

class _FlechaDeFilaState extends State<_FlechaDeFila> {
  bool _encima = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _encima = true),
      onExit: (_) => setState(() => _encima = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _encima
                ? Colors.white.withValues(alpha: 0.12)
                : Colors.transparent,
          ),
          child: Icon(
            widget.icono,
            size: 20,
            color: _encima ? Colors.white : HomeTheme.textMuted,
          ),
        ),
      ),
    );
  }
}

/// El margen lateral, por ancho de pantalla.
///
/// En una ventana ancha el contenido pegado al borde se ve barato; en un
/// teléfono cada píxel cuenta. Va por ancho y no por sistema operativo para
/// que también acompañe al achicar la ventana en escritorio.
double _margen(BuildContext context) => Ancho.de(context)
    .elegir(compacto: 14, medio: 20, amplio: 32, enorme: 48);

Map<String, String>? _cabeceras(String package) {
  final sitio = ExtensionUtils.runtimes[package]?.extension.webSite;
  if (sitio == null || sitio.isEmpty) return null;
  return {'Referer': sitio};
}

void _abrir(BuildContext context, ExtensionListItem item, String package) {
  ExtensionUtils.openExtensionDetail(
    context,
    package: package,
    url: item.url,
    // La portada que la tarjeta YA está mostrando: así la ficha abre con
    // imagen en vez de con un hueco mientras la extensión contesta.
    cover: item.cover,
    coverHeaders: _cabeceras(package),
  );
}
