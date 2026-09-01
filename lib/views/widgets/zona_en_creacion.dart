import 'package:flutter/material.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/platform_tv.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';

/// Una zona que ya existe en la interfaz pero todavía no tiene contenido.
///
/// ── Por qué se muestra en vez de esconderse ────────────────────────────
///
/// Una entrada que no está no se puede anticipar: el usuario no sabe que
/// viene, y cuando aparezca de un día para otro va a parecer que salió de la
/// nada. A la vista y diciendo qué falta, se entiende que está en camino.
///
/// Lo que NO hace es fingir: no dibuja filas vacías ni bloques grises
/// eternos, que se leen como que algo se rompió.
///
/// Compartida por las cuatro plataformas — el texto y el tamaño se acomodan
/// solos según el ancho, así que sirve igual en un teléfono que en un
/// televisor.
class ZonaEnCreacion extends StatelessWidget {
  const ZonaEnCreacion({super.key, required this.titulo});

  final String titulo;

  @override
  Widget build(BuildContext context) {
    // ── En televisor, el recuadro punteado que ocupa el área ───────────
    //
    // Del boceto aprobado: la zona se ve como un marco punteado que llena
    // todo el espacio de contenido, con el aviso centrado adentro. Así se
    // entiende que ESE es el sitio donde va a aparecer el contenido, en vez
    // de un texto suelto flotando en el medio de una pantalla vacía.
    final esTv = PlatformTv.esTelevisionSync;
    final aviso = _aviso(context);
    if (!esTv) return aviso;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 6, 0, 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: HomeTheme.border),
        ),
        child: SizedBox.expand(child: aviso),
      ),
    );
  }

  Widget _aviso(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.construction_rounded,
              size: 52,
              color: HomeTheme.textMuted,
            ),
            const SizedBox(height: 18),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: HomeTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Text(
                'home.zona-en-camino'.i18n,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  color: HomeTheme.textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
