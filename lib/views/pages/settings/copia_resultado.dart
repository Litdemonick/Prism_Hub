import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:prismhub/utils/copia_seguridad.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';

/// Qué entró al importar una copia.
///
/// Antes esto era un aviso de una sola línea con todo pegado: de dónde vino,
/// cuántas extensiones, cuántos títulos y cuáles faltaban, todo en un párrafo
/// corrido que había que leer entero para encontrar el dato que uno buscaba. Y
/// las extensiones que faltaban salían como "io.prismhub.shademanga", que no le
/// dice nada a nadie.
///
/// Acá va cada cosa en su renglón, con un icono que la identifica de un vistazo
/// y el número resaltado, que es lo que se mira primero.
class CopiaResultado extends StatelessWidget {
  const CopiaResultado({super.key, required this.resultado});
  final ResultadoImportacion resultado;

  @override
  Widget build(BuildContext context) {
    final r = resultado;
    final tenue =
        DefaultTextStyle.of(context).style.color?.withValues(alpha: .7);
    final alHistorial = r.historialNuevo + r.historialActualizado;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // De dónde vino. Va primero y destacado: con varias copias guardadas es
        // lo que confirma que se cargó la que se quería.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: HomeTheme.accentPink.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: HomeTheme.accentPink.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              const Text('📦', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  r.deQuien.etiqueta,
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Nada nuevo no es un error: significa que este equipo ya estaba al
        // día. Se dice así en vez de mostrar ceros, que se leen como que falló.
        if (r.total == 0)
          _linea('✅', 'settings.backup-import-nothing-new'.i18n, tenue)
        else ...[
          _linea(
            '🧩',
            FlutterI18n.translate(context, 'settings.backup-import-exts',
                translationParams: {'n': '${r.extensionesUsadas}'}),
            tenue,
          ),
          if (alHistorial > 0)
            _linea(
              '📺',
              FlutterI18n.translate(context, 'settings.backup-import-hist',
                  translationParams: {'n': '$alHistorial'}),
              tenue,
            ),
          if (r.favoritosNuevos > 0)
            _linea(
              '⭐',
              FlutterI18n.translate(context, 'settings.backup-import-favs',
                  translationParams: {'n': '${r.favoritosNuevos}'}),
              tenue,
            ),
        ],

        if (r.fallidos > 0)
          _linea(
            '⚠️',
            FlutterI18n.translate(
                context, 'settings.backup-import-failed-items',
                translationParams: {'n': '${r.fallidos}'}),
            tenue,
          ),

        // Las que faltan, con su nombre y no con el identificador.
        if (r.extensionesFaltantes.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('🧩', style: TextStyle(fontSize: 16)),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'settings.backup-import-missing-title'.i18n,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.orangeAccent,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  r.extensionesFaltantes
                      .map(ExtensionUtils.nombreVisible)
                      .join(' · '),
                  style: TextStyle(fontSize: 12.5, height: 1.4, color: tenue),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _linea(String emoji, String texto, Color? color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 15)),
          const SizedBox(width: 10),
          // Flexible: un texto largo en un teléfono angosto se sale de la caja
          // si no se le deja envolver.
          Flexible(
            child: Text(
              texto,
              style: TextStyle(fontSize: 13, height: 1.45, color: color),
            ),
          ),
        ],
      ),
    );
  }
}
