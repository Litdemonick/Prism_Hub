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
  bool _trabajando = false;

  @override
  void initState() {
    super.initState();
    _refrescar();
  }

  void _refrescar() {
    setState(() => _listas = BloqueadorAnuncios.listas());
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
          'Podés volver a encenderlo cuando quieras.',
          style: TextStyle(fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Dejarlo encendido'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red.shade300),
            child: const Text('Apagar igual'),
          ),
        ],
      ),
    );
    return r ?? false;
  }

  /// Un ejemplo de lista, con su dirección lista para copiar.
  ///
  /// Tocarlo abre el diálogo de instalar con el nombre y la dirección ya
  /// puestos: la idea es que no haya que ir a buscar nada a ningún lado.
  Widget _ejemploDeLista(String nombre, String para, String url,
      {bool ultimo = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: ultimo ? 0 : 10),
      child: Material(
        color: HomeTheme.bg,
        borderRadius: BorderRadius.circular(11),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _trabajando
              ? null
              : () => _conEspera(() async {
                    final n = await BloqueadorAnuncios.instalar(nombre, url);
                    _aviso('$nombre instalada con $n dominios');
                  }),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(nombre,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 3),
                      Text(
                        para,
                        style: TextStyle(
                            fontSize: 11.5,
                            height: 1.35,
                            color: HomeTheme.textMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Icon(Icons.download_rounded,
                    size: 19, color: HomeTheme.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _instalar() async {
    final resultado = await showDialog<List<String>>(
      context: context,
      builder: (_) => const _DialogoInstalar(),
    );
    if (resultado == null) return;
    await _conEspera(() async {
      final cuantos =
          await BloqueadorAnuncios.instalar(resultado[0], resultado[1]);
      _aviso('Lista instalada con $cuantos dominios');
    });
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
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
            children: [
              // Cabecera: qué es esto, de un vistazo.
              //
              // Antes era un párrafo plano de cuatro renglones. Nadie lee eso en
              // una pantalla de ajustes — y lo que hay que entender son dos cosas
              // sueltas: qué corta, y dónde. Así que va un escudo grande, el
              // alcance en una línea, y debajo los tres caminos que ataja.
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
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
                      'Medición y perfilado, que viaja pegado a los anuncios.',
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
                  hoverColor: Colors.white.withValues(alpha: 0.04),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
                      style:
                          TextStyle(fontSize: 12, color: HomeTheme.textMuted),
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
                    ),
                ],
              ),
              const SizedBox(height: 8),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
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
                          color: HomeTheme.textMuted.withValues(alpha: 0.75),
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Divider(height: 1),
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Algunas conocidas',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                            color: HomeTheme.textMuted,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Ejemplos de verdad, con la dirección que hay que pegar.
                      // Sin esto, "pegá la dirección de la que quieras usar" no
                      // le sirve a nadie: hay que saber ANTES que existen y
                      // dónde se consiguen.
                      _ejemploDeLista(
                        'StevenBlack',
                        'La más completa para empezar. Anuncios, rastreo y '
                            'sitios de malware, todo junto.',
                        'https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts',
                      ),
                      _ejemploDeLista(
                        'EasyList',
                        'La de toda la vida contra publicidad. Es la que usan '
                            'de base casi todos los bloqueadores.',
                        'https://easylist.to/easylist/easylist.txt',
                      ),
                      _ejemploDeLista(
                        'Phishing Army',
                        'Sitios que se hacen pasar por otros para robar datos.',
                        'https://phishing.army/download/phishing_army_blocklist_extended.txt',
                      ),
                      _ejemploDeLista(
                        'URLhaus',
                        'Direcciones que están repartiendo malware ahora mismo.',
                        'https://urlhaus.abuse.ch/downloads/hostfile/',
                        ultimo: true,
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
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: lista.activa ? HomeTheme.accentPink : HomeTheme.border,
        ),
      ),
      child: Column(
        children: [
          SwitchListTile(
            value: lista.activa,
            title: Text(lista.nombre,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              '${lista.dominios.length} dominios · '
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
                TextButton.icon(
                  onPressed: trabajando ? null : onActualizar,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Actualizar'),
                ),
                IconButton(
                  onPressed: trabajando ? null : onQuitar,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  tooltip: 'Quitar',
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

class _DialogoInstalar extends StatefulWidget {
  const _DialogoInstalar();

  @override
  State<_DialogoInstalar> createState() => _DialogoInstalarState();
}

class _DialogoInstalarState extends State<_DialogoInstalar> {
  final _nombre = TextEditingController();
  final _url = TextEditingController();

  @override
  void dispose() {
    _nombre.dispose();
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: HomeTheme.cardSurface,
      title: const Text('Instalar lista'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nombre,
            decoration: const InputDecoration(
              labelText: 'Nombre (opcional)',
              hintText: 'Se toma del sitio si lo dejás vacío',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _url,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Dirección de la lista',
              hintText: 'https://…',
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Se aceptan listas de dominios, archivos de hosts y reglas del '
            'tipo ||dominio^. Las reglas que no sean un dominio entero se '
            'ignoran.',
            style: TextStyle(fontSize: 11.5, color: HomeTheme.textMuted),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final u = _url.text.trim();
            if (u.isEmpty || !u.startsWith('http')) return;
            Navigator.pop(context, [_nombre.text, u]);
          },
          child: const Text('Instalar'),
        ),
      ],
    );
  }
}
