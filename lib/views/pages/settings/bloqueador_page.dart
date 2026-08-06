import 'dart:io';

import 'package:flutter/material.dart';
import 'package:prismhub/utils/bloqueador_anuncios.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';

/// Administra las listas de bloqueo del navegador interno.
///
/// Trae una base de fábrica que protege sin configurar nada —las redes de
/// ventanas emergentes, los cargadores de anuncios de vídeo y el rastreo— y
/// encima de eso el usuario puede sumar las listas que quiera: las instala
/// desde una dirección, las prende y apaga sueltas, y las quita cuando no le
/// sirven.
///
/// Antes NO había base: si el usuario no instalaba una lista, el bloqueador
/// figuraba encendido y no cortaba absolutamente nada.
class BloqueadorPage extends StatefulWidget {
  const BloqueadorPage({super.key});

  @override
  State<BloqueadorPage> createState() => _BloqueadorPageState();
}

class _BloqueadorPageState extends State<BloqueadorPage> {
  List<ListaDeBloqueo> _listas = const [];
  List<ListaConocida> _faltan = const [];
  bool _trabajando = false;

  @override
  void initState() {
    super.initState();
    _refrescar();
  }

  void _refrescar() {
    setState(() {
      _listas = BloqueadorAnuncios.listas();
      _faltan = BloqueadorAnuncios.deFabricaQueFaltan();
    });
  }

  void _aviso(String texto, {bool malo = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texto),
        backgroundColor: malo ? Colors.red.shade900 : null,
      ),
    );
  }

  Future<void> _conEspera(Future<void> Function() accion) async {
    if (_trabajando) return;
    setState(() => _trabajando = true);
    try {
      await accion();
    } catch (e) {
      _aviso('$e'.replaceFirst('Exception: ', ''), malo: true);
    } finally {
      if (mounted) setState(() => _trabajando = false);
      _refrescar();
    }
  }

  /// Pregunta antes de apagar, diciendo qué se pierde.
  ///
  /// No es un trámite: apagarlo no se nota hasta que se nota, y para entonces
  /// ya hay una pestaña de casino encima de la película. Que lo apague quien
  /// quiera, pero sabiendo qué le espera.
  Future<bool> _confirmarApagado() async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: HomeTheme.cardSurface,
        icon: const Icon(Icons.warning_amber_rounded,
            color: Color(0xFFFFB74D), size: 32),
        title: const Text('¿Apagar el bloqueador?'),
        content: const Text(
          'En el navegador interno van a volver a aparecer:\n\n'
          '·  Pestañas que se abren solas al tocar reproducir\n'
          '·  Anuncios de veinte segundos antes de la película\n'
          '·  Rastreo de las redes de publicidad\n\n'
          'No se recomienda apagarlo: es lo único que separa al navegador '
          'interno de las redes de anuncios de estos sitios.',
          style: TextStyle(fontSize: 13, height: 1.5),
        ),
        actions: [
          _BotonDeAviso(
            texto: 'Dejarlo encendido',
            onPressed: () => Navigator.pop(ctx, false),
            recomendado: true,
          ),
          _BotonDeAviso(
            texto: 'Apagar igual',
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (r != true) return false;
    return _confirmarDeVerdad();
  }

  /// La segunda pregunta, corta y al hueso.
  ///
  /// No es por insistir: el primer aviso explica y se lee en diagonal, y tocar
  /// "Apagar igual" sin haberlo leído es lo más fácil del mundo. Esta segunda no
  /// explica nada — solo obliga a decidir otra vez, ya sabiendo qué se apaga.
  Future<bool> _confirmarDeVerdad() async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: HomeTheme.cardSurface,
        title: const Text('¿Seguro?'),
        content: const Text(
          'Quedás sin protección contra anuncios, estafas y páginas que '
          'reparten virus mientras uses el navegador interno.',
          style: TextStyle(fontSize: 13, height: 1.5),
        ),
        actions: [
          _BotonDeAviso(
            texto: 'Mejor no',
            onPressed: () => Navigator.pop(ctx, false),
            recomendado: true,
          ),
          _BotonDeAviso(
            texto: 'Sí, apagar',
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    return r == true;
  }

  Future<void> _instalar() async {
    // El panel se encarga solo de instalar y de mostrarlo: acá alcanza con
    // refrescar cuando se cierra, porque adentro se pueden haber puesto o
    // sacado varias.
    await showDialog<void>(
      context: context,
      builder: (_) => const _PanelCatalogo(),
    );
    if (mounted) _refrescar();
  }

  /// Una fila de "esto se corta": icono, qué es y por qué molesta.
  ///
  /// Se listan los tres caminos por separado en vez de mostrar solo el número
  /// de dominios. El número no le dice nada a nadie; lo que el usuario quiere
  /// saber es si se le van a dejar de abrir pestañas solas.
  Widget _queSeCorta(IconData icono, String que, String detalle,
      {bool ultimo = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: ultimo ? 0 : 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: HomeTheme.bg,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icono, size: 17, color: HomeTheme.textMuted),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(que,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  detalle,
                  style: TextStyle(
                      fontSize: 11.5, height: 1.3, color: HomeTheme.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activo = BloqueadorAnuncios.activo;
    return Scaffold(
      backgroundColor: HomeTheme.bg,
      appBar: AppBar(
        backgroundColor: HomeTheme.bg,
        title: const Text('Bloqueador de anuncios'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _trabajando ? null : _instalar,
        icon: const Icon(Icons.add),
        label: const Text('Instalar lista'),
      ),
      // Todo el contenido en una columna centrada.
      //
      // En el celular ocupa el ancho completo y se ve como siempre; en una
      // ventana de escritorio, sin esto, las filas se estiraban de punta a
      // punta y el interruptor quedaba a medio metro de su texto.
      // La lista ocupa TODO el ancho y lo que se centra es el contenido.
      //
      // Antes se centraba la lista entera con un ConstrainedBox, y con eso la
      // barra de desplazamiento quedaba pegada al borde de la columna —o sea, en
      // medio de la pantalla, contra las tarjetas—. Ahora la barra queda donde
      // corresponde, contra el borde derecho de la ventana, y el contenido se
      // sigue centrando igual.
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 90),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Cabecera: qué es esto, de un vistazo.
                    //
                    // Antes era un párrafo plano de cuatro renglones. Nadie lee eso en
                    // una pantalla de ajustes — y lo que hay que entender son dos cosas
                    // sueltas: qué corta, y dónde. Así que va un escudo grande, el
                    // alcance en una línea, y debajo los tres caminos que ataja.
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 22),
                      decoration: BoxDecoration(
                        color: HomeTheme.cardSurface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: HomeTheme.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Icon(
                            activo ? Icons.shield : Icons.shield_outlined,
                            size: 40,
                            color: activo
                                ? const Color(0xFF69F0AE)
                                : HomeTheme.textMuted,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            activo ? 'Protegido' : 'Sin protección',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Solo en el navegador interno, que es donde se abren los '
                            'servidores que no reproducen en la app.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.45,
                              color: HomeTheme.textMuted,
                            ),
                          ),
                          const SizedBox(height: 18),
                          const Divider(height: 1),
                          const SizedBox(height: 18),
                          _queSeCorta(
                            Icons.block,
                            'Ventanas emergentes',
                            'Las pestañas que se abren solas al tocar reproducir.',
                          ),
                          _queSeCorta(
                            Icons.ondemand_video,
                            'Anuncios antes del vídeo',
                            'Los de veinte segundos, dentro del reproductor.',
                          ),
                          _queSeCorta(
                            Icons.travel_explore,
                            'Rastreo',
                            'Medición y perfilado, que viaja pegado a los '
                                'anuncios y sabe desde qué dirección de red mirás.',
                          ),
                          _queSeCorta(
                            Icons.coronavirus_outlined,
                            'Virus y programas dañinos',
                            'Servidores que reparten archivos infectados, y los '
                                'que los sitios cargan sin que se vean.',
                          ),
                          _queSeCorta(
                            Icons.gpp_maybe_outlined,
                            'Estafas y suplantación',
                            'Páginas que se hacen pasar por otras para quedarse '
                                'con tu cuenta o los datos de la tarjeta.',
                          ),
                          _queSeCorta(
                            Icons.memory,
                            'Minado escondido',
                            'Sitios que usan tu equipo para minar criptomonedas. '
                                'Se nota en que todo empieza a ir lento.',
                            ultimo: true,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // El interruptor, con su propia tarjeta.
                    //
                    // Antes era un SwitchListTile pelado sobre el fondo: al pasar el
                    // puntero se pintaba de rosa y el texto encima dejaba de leerse.
                    // Ahora tiene fondo propio y el resaltado es apenas un aclarado.
                    Material(
                      color: HomeTheme.cardSurface,
                      borderRadius: BorderRadius.circular(14),
                      clipBehavior: Clip.antiAlias,
                      child: SwitchListTile(
                        value: activo,
                        activeTrackColor: const Color(0xFF69F0AE),
                        hoverColor: Colors.white.withValues(alpha: 0.04),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 6),
                        title: const Text(
                          'Bloquear anuncios',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            activo
                                ? '${BloqueadorAnuncios.cuantosDominios} dominios · '
                                    '${BloqueadorAnuncios.cuantosDeFabrica} vienen puestos'
                                    '${BloqueadorAnuncios.cuantosDeListas > 0 ? ' + ${BloqueadorAnuncios.cuantosDeListas} de tus listas' : ''}'
                                : 'Apagado. Las listas quedan guardadas.',
                            style: TextStyle(
                                fontSize: 12, color: HomeTheme.textMuted),
                          ),
                        ),
                        onChanged: (v) async {
                          // Apagarlo se pregunta; encenderlo no. Apagar es lo que puede
                          // arruinarle la tarde a alguien, y conviene que sepa qué le
                          // espera ANTES, no después con la pestaña de casino ya abierta.
                          if (!v && !await _confirmarApagado()) return;
                          await BloqueadorAnuncios.setActivo(v);
                          await BloqueadorAnuncios.cargar();
                          _refrescar();
                        },
                      ),
                    ),
                    if (!Platform.isAndroid) ...[
                      const SizedBox(height: 4),
                      // Se dice la verdad sobre lo que hace en cada sistema en vez de
                      // dar a entender que protege igual en todos.
                      Text(
                        'En esta plataforma el motor del navegador no permite frenar el '
                        'pedido antes de que salga, así que se corta la navegación a los '
                        'dominios de las listas y se limpia la página por dentro. '
                        'Funciona, pero en Android el bloqueo es más profundo.',
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.35,
                          color: HomeTheme.textMuted,
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        const Text('Listas instaladas',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        const Spacer(),
                        if (_trabajando)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else if (_listas.length > 1)
                          // Cada lista se actualiza sola desde su fila; esto es
                          // para no tener que tocarlas de a una cuando son
                          // varias.
                          TextButton.icon(
                            onPressed: () => _conEspera(() async {
                              final n =
                                  await BloqueadorAnuncios.actualizarTodas();
                              _aviso('$n de ${_listas.length} listas al día');
                            }),
                            icon: const Icon(Icons.refresh, size: 16),
                            label: const Text('Actualizar todas'),
                            style: ButtonStyle(
                              foregroundColor:
                                  WidgetStatePropertyAll(HomeTheme.textMuted),
                              overlayColor: WidgetStatePropertyAll(
                                  Colors.white.withValues(alpha: 0.05)),
                              textStyle: const WidgetStatePropertyAll(
                                TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                              shape: WidgetStatePropertyAll(
                                RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(9)),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Si alguna de las que vienen puestas no llegó a bajarse, se
                    // dice.
                    //
                    // La app promete cuatro protecciones de fábrica; si una no
                    // está —porque no había red al instalar, por ejemplo— el
                    // usuario tiene que poder verlo y ponerla, no darse cuenta
                    // solo.
                    if (_faltan.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                        decoration: BoxDecoration(
                          color: const Color(0x18FFB74D),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0x44FFB74D)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline,
                                size: 19, color: Color(0xFFFFB74D)),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Text(
                                _faltan.length == 1
                                    ? 'Falta una protección recomendada: '
                                        '${_faltan.first.nombre}.'
                                    : 'Faltan ${_faltan.length} protecciones '
                                        'recomendadas.',
                                style: const TextStyle(
                                    fontSize: 12.5, height: 1.35),
                              ),
                            ),
                            const SizedBox(width: 6),
                            TextButton(
                              onPressed: _trabajando
                                  ? null
                                  : () => _conEspera(() async {
                                        for (final c in _faltan) {
                                          await BloqueadorAnuncios.instalar(
                                              c.nombre, c.url);
                                        }
                                        _aviso('Protecciones al día');
                                      }),
                              style: ButtonStyle(
                                foregroundColor: const WidgetStatePropertyAll(
                                    Color(0xFFFFB74D)),
                                overlayColor: WidgetStatePropertyAll(
                                    const Color(0xFFFFB74D)
                                        .withValues(alpha: 0.15)),
                                shape: WidgetStatePropertyAll(
                                  RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(9)),
                                ),
                              ),
                              child: const Text('Poner',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ),
                      ),
                    // Cuando no hay ninguna, se explica QUÉ es una lista.
                    //
                    // Antes decía "todavía no hay ninguna, tocá instalar y pegá la
                    // dirección" — que da por sabido lo único que hay que explicar.
                    // El usuario no tiene por qué saber qué es una lista de bloqueo
                    // ni de dónde saca una dirección, y el texto suelto sobre el
                    // fondo tampoco se leía como algo con lo que se pueda hacer algo.
                    if (_listas.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 22),
                        decoration: BoxDecoration(
                          color: HomeTheme.cardSurface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: HomeTheme.border),
                        ),
                        child: Column(
                          children: [
                            Icon(Icons.playlist_add,
                                size: 30, color: HomeTheme.textMuted),
                            const SizedBox(height: 12),
                            const Text(
                              'Ninguna lista instalada',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 14.5, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Una lista es un archivo público de dominios de anuncios '
                              'que mantiene gente dedicada a eso. Al instalarla, sus '
                              'dominios se suman a los que la app ya bloquea.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12.5,
                                height: 1.45,
                                color: HomeTheme.textMuted,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'No hace falta ninguna: la protección de fábrica ya '
                              'funciona. Una lista suma decenas de miles de dominios '
                              'y se actualiza sola.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.45,
                                color:
                                    HomeTheme.textMuted.withValues(alpha: 0.75),
                              ),
                            ),
                            const SizedBox(height: 16),
                            // Se manda al catálogo en vez de repetir acá cuatro
                            // ejemplos sueltos: el catálogo las tiene todas,
                            // agrupadas y con buscador.
                            FilledButton.icon(
                              onPressed: _trabajando ? null : _instalar,
                              icon: const Icon(Icons.playlist_add, size: 18),
                              label: const Text('Ver las listas disponibles'),
                            ),
                          ],
                        ),
                      ),
                    for (final l in _listas)
                      _FilaLista(
                        lista: l,
                        trabajando: _trabajando,
                        onActivar: (v) async {
                          await BloqueadorAnuncios.activarLista(l.url, v);
                          _refrescar();
                        },
                        onActualizar: () => _conEspera(() async {
                          final n = await BloqueadorAnuncios.actualizar(l.url);
                          _aviso('Actualizada: $n dominios');
                        }),
                        onQuitar: () => _conEspera(() async {
                          await BloqueadorAnuncios.quitar(l.url);
                          _aviso('Lista quitada');
                        }),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Un botón de los avisos, con un resaltado que se lee.
///
/// Los `TextButton` sueltos usaban el color de acento del tema al pasar el
/// puntero: fondo rosa con el texto encima, que en el aviso de apagar quedaba
/// ilegible justo en el momento en que hay que leerlo. Acá el fondo del
/// resaltado sale del mismo color del texto, apenas insinuado, así que siempre
/// contrasta.
class _BotonDeAviso extends StatelessWidget {
  const _BotonDeAviso({
    required this.texto,
    required this.onPressed,
    this.recomendado = false,
  });

  final String texto;
  final VoidCallback onPressed;

  /// La opción segura. Va marcada para que se distinga de un vistazo cuál es
  /// la que no deja al usuario a la intemperie.
  final bool recomendado;

  @override
  Widget build(BuildContext context) {
    final color =
        recomendado ? const Color(0xFF69F0AE) : const Color(0xFFFF8A80);
    return TextButton(
      onPressed: onPressed,
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll(color),
        overlayColor: WidgetStatePropertyAll(color.withValues(alpha: 0.14)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        ),
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontWeight: recomendado ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
  }
}

class _FilaLista extends StatelessWidget {
  const _FilaLista({
    required this.lista,
    required this.trabajando,
    required this.onActivar,
    required this.onActualizar,
    required this.onQuitar,
  });

  final ListaDeBloqueo lista;
  final bool trabajando;
  final ValueChanged<bool> onActivar;
  final VoidCallback onActualizar;
  final VoidCallback onQuitar;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: HomeTheme.cardSurface,
        borderRadius: BorderRadius.circular(12),
        // Verde cuando protege, gris cuando no.
        //
        // Antes el borde de "activa" era el rosa de acento del tema, que en
        // esta pantalla no quiere decir nada: acá el color tiene que contestar
        // "¿esto me está protegiendo?", y para eso el verde es inequívoco. El
        // rosa, además, es el mismo que usaba el resaltado del interruptor al
        // pasar el puntero, así que activa o no, todo se veía igual de rosa.
        border: Border.all(
          color: lista.activa ? const Color(0x5569F0AE) : HomeTheme.border,
        ),
      ),
      child: Column(
        children: [
          SwitchListTile(
            value: lista.activa,
            activeTrackColor: const Color(0xFF69F0AE),
            hoverColor: Colors.white.withValues(alpha: 0.04),
            title: Text(lista.nombre,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              '${lista.cuantos} dominios · '
              '${_cuando(lista.actualizada)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: HomeTheme.textMuted, fontSize: 12),
            ),
            onChanged: trabajando ? null : onActivar,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    lista.url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: HomeTheme.textMuted, fontSize: 11),
                  ),
                ),
                _BotonChico(
                  icono: Icons.refresh,
                  tooltip: 'Actualizar esta lista',
                  onPressed: trabajando ? null : onActualizar,
                ),
                _BotonChico(
                  icono: Icons.delete_outline,
                  tooltip: 'Quitar',
                  color: const Color(0xFFFF8A80),
                  onPressed: trabajando ? null : onQuitar,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _cuando(DateTime d) {
    if (d.millisecondsSinceEpoch == 0) return 'sin actualizar';
    final dias = DateTime.now().difference(d).inDays;
    if (dias == 0) return 'actualizada hoy';
    if (dias == 1) return 'actualizada ayer';
    return 'actualizada hace $dias días';
  }
}

/// El catálogo: se elige de una lista y se instala sin salir.
///
/// Antes esto era un diálogo con dos campos vacíos —nombre y dirección— y un
/// texto que decía "pegá la dirección de la que quieras usar". Eso da por
/// sabido justo lo único que hay que explicar: nadie que no sepa del tema tiene
/// de dónde sacar una dirección. Y encima se cerraba al instalar una, así que
/// poner tres eran tres viajes.
///
/// Ahora se abre el catálogo entero, con buscador, y se queda abierto: se tocan
/// las que se quieran y cada una pasa a "instalada" en el momento. Para lo raro
/// sigue estando el campo de dirección a mano, abajo.
class _PanelCatalogo extends StatefulWidget {
  const _PanelCatalogo();

  @override
  State<_PanelCatalogo> createState() => _PanelCatalogoState();
}

class _PanelCatalogoState extends State<_PanelCatalogo> {
  final _busca = TextEditingController();
  final _url = TextEditingController();
  final _nombre = TextEditingController();

  /// Qué direcciones están instaladas. Se relee después de cada cambio para que
  /// las tarjetas muestren el estado de verdad y no una foto vieja.
  Set<String> _puestas = <String>{};

  /// La dirección que se está bajando ahora, si hay alguna.
  String? _bajando;

  /// El error del campo de dirección a mano, si lo escrito no sirve.
  String? _errorUrl;

  /// Si está desplegado el campo para poner una dirección cualquiera.
  bool _aMano = false;

  @override
  void initState() {
    super.initState();
    _releer();
    _busca.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _busca.dispose();
    _url.dispose();
    _nombre.dispose();
    super.dispose();
  }

  void _releer() {
    _puestas = BloqueadorAnuncios.listas().map((l) => l.url).toSet();
  }

  void _avisar(String texto, {bool malo = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(texto),
      backgroundColor: malo ? Colors.red.shade900 : null,
    ));
  }

  Future<void> _instalar(String nombre, String url) async {
    if (_bajando != null) return;
    setState(() => _bajando = url);
    try {
      final n = await BloqueadorAnuncios.instalar(nombre, url);
      _avisar('$nombre: $n dominios');
    } catch (e) {
      _avisar('$e'.replaceFirst('Exception: ', ''), malo: true);
    } finally {
      if (mounted) {
        setState(() {
          _bajando = null;
          _releer();
        });
      }
    }
  }

  Future<void> _quitar(String url) async {
    await BloqueadorAnuncios.quitar(url);
    if (mounted) setState(_releer);
  }

  /// Las del catálogo que coinciden con lo buscado, agrupadas.
  ///
  /// Se busca en el nombre Y en la descripción: quien escribe "virus" no sabe
  /// que la lista se llama Prigent-Malware, y es justo la que necesita.
  /// El rotulo del apartado de las que ya estan puestas.
  static const _yaEstan = 'Ya instaladas';

  Map<String, List<ListaConocida>> get _porGrupo {
    final q = _busca.text.trim().toLowerCase();
    // Las instaladas van TODAS JUNTAS Y ARRIBA, en su propio apartado.
    //
    // Antes quedaban cada una en el grupo que le tocaba por tema, repartidas
    // entre las demas: para actualizar una habia que acordarse de en cual
    // estaba e ir a buscarla. Y las cuatro que vienen puestas aparecian con el
    // boton de instalar como si faltaran.
    final puestas = <ListaConocida>[];
    final resto = <String, List<ListaConocida>>{};
    for (final c in BloqueadorAnuncios.catalogo) {
      if (q.isNotEmpty &&
          !c.nombre.toLowerCase().contains(q) &&
          !c.para.toLowerCase().contains(q) &&
          !c.grupo.toLowerCase().contains(q)) {
        continue;
      }
      if (_puestas.contains(c.url)) {
        puestas.add(c);
      } else {
        (resto[c.grupo] ??= <ListaConocida>[]).add(c);
      }
    }
    return {
      if (puestas.isNotEmpty) _yaEstan: puestas,
      ...resto,
    };
  }

  Future<void> _actualizar(String nombre, String url) async {
    if (_bajando != null) return;
    setState(() => _bajando = url);
    try {
      final n = await BloqueadorAnuncios.actualizar(url);
      _avisar('$nombre al día: $n dominios');
    } catch (e) {
      _avisar('$e'.replaceFirst('Exception: ', ''), malo: true);
    } finally {
      if (mounted) {
        setState(() {
          _bajando = null;
          _releer();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final grupos = _porGrupo;
    final alto = MediaQuery.of(context).size.height;
    return Dialog(
      backgroundColor: HomeTheme.cardSurface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 520, maxHeight: alto * 0.85),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 0),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Instalar lista',
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 20),
                    tooltip: 'Cerrar',
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
              child: TextField(
                controller: _busca,
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: HomeTheme.bg,
                  hintText: 'Buscar: virus, anuncios, rastreo…',
                  prefixIcon: const Icon(Icons.search, size: 19),
                  suffixIcon: _busca.text.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () => _busca.clear(),
                          icon: const Icon(Icons.clear, size: 17),
                        ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(11),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Flexible(
              child: grupos.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Text(
                        'Ninguna coincide con eso.',
                        style: TextStyle(color: HomeTheme.textMuted),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      shrinkWrap: true,
                      children: [
                        for (final g in grupos.entries) ...[
                          Padding(
                            padding: const EdgeInsets.only(top: 6, bottom: 8),
                            child: Text(
                              g.key.toUpperCase(),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.6,
                                color: HomeTheme.textMuted,
                              ),
                            ),
                          ),
                          for (final c in g.value)
                            _TarjetaDeLista(
                              lista: c,
                              instalada: _puestas.contains(c.url),
                              bajando: _bajando == c.url,
                              trabada: _bajando != null && _bajando != c.url,
                              onInstalar: () => _instalar(c.nombre, c.url),
                              onActualizar: () => _actualizar(c.nombre, c.url),
                              onQuitar: () => _quitar(c.url),
                            ),
                        ],
                      ],
                    ),
            ),
            const Divider(height: 1),
            // El camino a mano queda plegado: es para quien ya sabe lo que
            // hace, y desplegado le robaba la atención al catálogo.
            if (!_aMano)
              // Discreto a proposito: es la salida para quien ya sabe lo que
              // hace. Antes usaba el color de acento del tema y quedaba como lo
              // mas llamativo de la pantalla, compitiendo con el catalogo, que
              // es lo que casi todo el mundo va a usar.
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _aMano = true),
                    icon: const Icon(Icons.link, size: 16),
                    label: const Text('Poner otra dirección'),
                    style: ButtonStyle(
                      foregroundColor:
                          WidgetStatePropertyAll(HomeTheme.textMuted),
                      overlayColor: WidgetStatePropertyAll(
                          Colors.white.withValues(alpha: 0.05)),
                      textStyle: const WidgetStatePropertyAll(
                        TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                      ),
                      shape: WidgetStatePropertyAll(
                        RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(9)),
                      ),
                    ),
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _url,
                      autofocus: true,
                      maxLength: 2048,
                      decoration: InputDecoration(
                        isDense: true,
                        labelText: 'Dirección de la lista',
                        hintText: 'https://…',
                        counterText: '',
                        errorText: _errorUrl,
                      ),
                      onChanged: (_) {
                        if (_errorUrl != null) {
                          setState(() => _errorUrl = null);
                        }
                      },
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _nombre,
                      maxLength: 60,
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: 'Nombre (opcional)',
                        counterText: '',
                        hintText: 'Se toma del sitio si lo dejás vacío',
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Se aceptan listas de dominios, archivos de hosts y '
                      'reglas del tipo ||dominio^. Todo lo que no tenga forma '
                      'de dominio se descarta.',
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.35,
                        color: HomeTheme.textMuted,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => setState(() => _aMano = false),
                          child: const Text('Cancelar'),
                        ),
                        const SizedBox(width: 6),
                        FilledButton(
                          onPressed: _bajando != null
                              ? null
                              : () async {
                                  final u = _url.text.trim();
                                  // Se revisa ACÁ y en el bloqueador: acá para
                                  // decirlo al momento, y allá porque es la
                                  // puerta de verdad.
                                  final mal =
                                      BloqueadorAnuncios.direccionValida(u);
                                  if (mal != null) {
                                    setState(() => _errorUrl = mal);
                                    return;
                                  }
                                  await _instalar(
                                    BloqueadorAnuncios.nombreSaneado(
                                        _nombre.text),
                                    u,
                                  );
                                  if (mounted) {
                                    _url.clear();
                                    _nombre.clear();
                                    setState(() => _aMano = false);
                                  }
                                },
                          child: const Text('Instalar'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Un botón de icono chico, con el resaltado redondeado y legible.
///
/// El `IconButton` pelado se resalta con un círculo del color de acento del
/// tema, que acá quedaba rosa sobre la tarjeta y tapaba el icono.
class _BotonChico extends StatelessWidget {
  const _BotonChico({
    required this.icono,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });

  final IconData icono;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? HomeTheme.textMuted;
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 36,
        height: 36,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            hoverColor: c.withValues(alpha: 0.13),
            splashColor: c.withValues(alpha: 0.18),
            child: Icon(
              icono,
              size: 18,
              color: onPressed == null ? c.withValues(alpha: 0.35) : c,
            ),
          ),
        ),
      ),
    );
  }
}

/// Una lista del catálogo, con su estado.
class _TarjetaDeLista extends StatelessWidget {
  const _TarjetaDeLista({
    required this.lista,
    required this.instalada,
    required this.bajando,
    required this.trabada,
    required this.onInstalar,
    required this.onActualizar,
    required this.onQuitar,
  });

  final ListaConocida lista;
  final bool instalada;
  final bool bajando;
  final bool trabada;
  final VoidCallback onInstalar;
  final VoidCallback onActualizar;
  final VoidCallback onQuitar;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(13, 12, 8, 12),
      decoration: BoxDecoration(
        color: HomeTheme.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: instalada ? const Color(0x5569F0AE) : Colors.transparent,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        lista.nombre,
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w600),
                      ),
                    ),
                    // "Recomendada", y solo si NO está puesta.
                    //
                    // Antes decía "viene puesta" al lado del botón de instalar,
                    // en la misma tarjeta: o venía puesta o había que
                    // instalarla, las dos cosas a la vez no.
                    if (lista.deFabrica && !instalada) ...[
                      const SizedBox(width: 7),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0x2269F0AE),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: const Text(
                          'recomendada',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF69F0AE),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  lista.para,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.35,
                    color: HomeTheme.textMuted,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${_conPuntos(lista.cuantos)} dominios',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: HomeTheme.textMuted.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          // Los botones de la derecha.
          //
          // Cuando la lista esta puesta hacen falta DOS —volver a bajarla y
          // sacarla— y antes habia uno solo que hacia de tilde y de quitar a la
          // vez: el tilde verde parecia decir "listo" y en realidad borraba.
          if (bajando)
            const SizedBox(
              width: 38,
              height: 38,
              child: Padding(
                padding: EdgeInsets.all(10),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (instalada)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _BotonChico(
                  icono: Icons.refresh,
                  tooltip: 'Volver a bajarla',
                  onPressed: trabada ? null : onActualizar,
                ),
                _BotonChico(
                  icono: Icons.delete_outline,
                  tooltip: 'Quitar',
                  color: const Color(0xFFFF8A80),
                  onPressed: trabada ? null : onQuitar,
                ),
              ],
            )
          else
            _BotonChico(
              icono: Icons.download_rounded,
              tooltip: 'Instalar',
              onPressed: trabada ? null : onInstalar,
            ),
        ],
      ),
    );
  }

  /// 434121 → 434.121. Un número así, pelado, no se lee de un vistazo.
  static String _conPuntos(int n) {
    final t = '$n';
    final f = StringBuffer();
    for (var i = 0; i < t.length; i++) {
      if (i > 0 && (t.length - i) % 3 == 0) f.write('.');
      f.write(t[i]);
    }
    return f.toString();
  }
}
