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
  Widget _queSeCorta(IconData icono, String que, String detalle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 17, color: HomeTheme.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(que,
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w600)),
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
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
        children: [
          // Aclaración de alcance arriba de todo: sin esto es razonable
          // suponer que también limpia lo que se ve en el reproductor normal.
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: HomeTheme.cardSurface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: HomeTheme.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Esto solo aplica al navegador interno, que es donde se abren '
                  'los servidores que no se pueden reproducir en la app. El '
                  'reproductor normal no carga páginas, así que ahí no hay '
                  'anuncios que bloquear.',
                  style: TextStyle(fontSize: 12.5, height: 1.4),
                ),
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),
                // Qué se corta, en vez de un número suelto que no dice nada.
                // Son tres caminos distintos y el usuario los sufre distinto,
                // así que vale nombrarlos uno por uno.
                _queSeCorta(
                  Icons.block,
                  'Ventanas emergentes',
                  'Las pestañas que se abren solas al tocar reproducir.',
                ),
                _queSeCorta(
                  Icons.ondemand_video,
                  'Anuncios antes del vídeo',
                  'Los de veinte segundos que salen dentro del reproductor.',
                ),
                _queSeCorta(
                  Icons.travel_explore,
                  'Rastreo',
                  'Medición y perfilado, que viaja pegado a los anuncios.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            value: activo,
            title: const Text('Bloquear anuncios'),
            // Se dice de dónde sale cada cosa: sin esto, "N dominios" no
            // distingue entre lo que viene puesto y lo que agregó el usuario, y
            // no queda claro que funciona sin configurar nada.
            subtitle: Text(
              activo
                  ? '${BloqueadorAnuncios.cuantosDominios} dominios · '
                      '${BloqueadorAnuncios.cuantosDeFabrica} vienen puestos'
                      '${BloqueadorAnuncios.cuantosDeListas > 0 ? ' + ${BloqueadorAnuncios.cuantosDeListas} de tus listas' : ''}'
                  : 'Apagado: las listas quedan guardadas',
            ),
            onChanged: (v) async {
              await BloqueadorAnuncios.setActivo(v);
              await BloqueadorAnuncios.cargar();
              _refrescar();
            },
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
          if (_listas.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Todavía no hay ninguna lista. Tocá "Instalar lista" y pegá la '
                'dirección de la que quieras usar.',
                style: TextStyle(color: HomeTheme.textMuted, height: 1.4),
              ),
            ),
          for (final l in _listas) _FilaLista(
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
