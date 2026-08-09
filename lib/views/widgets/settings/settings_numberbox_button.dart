import 'package:flutter/material.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';

/// Control de un valor numérico de Ajustes: el número se MUESTRA pero no se
/// escribe, y se cambia solo con los botones.
///
/// Antes esto era un `fluent.NumberBox` dentro de un `fluent.Tooltip`, y eso
/// traía dos problemas:
///
/// 1. En Android no abría la sección. La raíz de la app en Android es
///    GetMaterialApp (FluentApp solo se monta en escritorio), así que no hay
///    ni FluentTheme ni FluentLocalizations en el árbol — y NumberBox pide
///    los dos. La subpágina no llegaba a construirse y el botón parecía no
///    hacer nada. Poner un FluentTheme no alcanzaba: faltaban igual las
///    localizaciones. Con widgets de Material el problema desaparece, y de
///    paso el control se ve igual en las tres plataformas.
/// 2. Se podía escribir cualquier cosa. Letras, puntos sueltos o un 999999
///    dejaban el salto en un valor absurdo — cada toque mandaba el vídeo al
///    final— sin manera obvia de relacionarlo con este campo.
class SettingNumboxButton extends StatefulWidget {
  const SettingNumboxButton({
    super.key,
    this.icon,
    required this.title,
    required this.onChanged,
    required this.button1text,
    required this.button2text,
    required this.numberBoxvalue,
    this.min = -600,
    this.max = 600,
  });

  final Widget? icon;
  final String title;
  // Los dos textos alternan el TAMAÑO del paso (1s / 0.1s): se toca el botón
  // para cambiar con cuánta precisión suben y bajan las flechas.
  final String button1text;
  final String button2text;
  final void Function(double?)? onChanged;
  final double numberBoxvalue;
  final double min;
  final double max;

  @override
  State<SettingNumboxButton> createState() => _SettingNumboxButtonState();
}

class _SettingNumboxButtonState extends State<SettingNumboxButton> {
  // false = paso de 1s, true = paso de 0.1s.
  bool buttonSwitch = false;

  // Estado PROPIO. Antes se pintaba widget.numberBoxvalue directo, que el
  // padre lee del almacenamiento en su build: tocar + o − guardaba bien el
  // valor nuevo, pero la página de Ajustes no se reconstruye sola, así que el
  // número seguía mostrando el viejo y parecía que los botones no hacían nada.
  late double _value = widget.numberBoxvalue;

  @override
  void didUpdateWidget(covariant SettingNumboxButton old) {
    super.didUpdateWidget(old);
    // Cambios que vienen de afuera (ej. "Restablecer valores por defecto").
    if (old.numberBoxvalue != widget.numberBoxvalue &&
        widget.numberBoxvalue != _value) {
      _value = widget.numberBoxvalue;
    }
  }

  void _bump(double delta) {
    final next = (_value + delta).clamp(widget.min, widget.max);
    // Redondeo a un decimal: sumar 0.1 en coma flotante da 2.9000000000000004
    // y ese número terminaba guardado y mostrado tal cual.
    final rounded = (next * 10).roundToDouble() / 10;
    if (rounded == _value) return;
    setState(() => _value = rounded);
    widget.onChanged?.call(rounded);
  }

  Widget _stepButton({required IconData icon, required VoidCallback onTap}) {
    return Material(
      color: HomeTheme.bg,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 18, color: HomeTheme.textPrimary),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final step = buttonSwitch ? 0.1 : 1.0;
    final texto = _value == _value.roundToDouble()
        ? '${_value.round()}'
        : _value.toStringAsFixed(1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: HomeTheme.cardSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: HomeTheme.border),
      ),
      child: Row(
        children: [
          // La etiqueta manda a la izquierda y el grupo de control se arma a
          // la derecha con ancho fijo. Antes todo competía por el espacio en
          // un mismo Row flexible y en un celular el número quedaba en una
          // columna de 40px, partiendo "-10 s" en cuatro líneas.
          Expanded(
            child: widget.icon ??
                Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: HomeTheme.textPrimary),
                ),
          ),
          const SizedBox(width: 8),
          _stepButton(icon: Icons.remove, onTap: () => _bump(-step)),
          // Ancho fijo para que el número no baile al pasar de "2" a "-10".
          SizedBox(
            width: 58,
            child: Text(
              '$texto s',
              textAlign: TextAlign.center,
              maxLines: 1,
              style: TextStyle(
                color: HomeTheme.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ),
          _stepButton(icon: Icons.add, onTap: () => _bump(step)),
          const SizedBox(width: 8),
          // Alterna la precisión del paso. Muestra el tamaño que se va a
          // aplicar, no el activo, para que se entienda qué pasa al tocarlo.
          Tooltip(
            message: 'settings.skip-step-hint'.i18n,
            child: InkWell(
              onTap: () => setState(() => buttonSwitch = !buttonSwitch),
              borderRadius: BorderRadius.circular(999),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: HomeTheme.accentPink.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: HomeTheme.accentPink),
                ),
                child: Text(
                  buttonSwitch ? widget.button2text : widget.button1text,
                  style: TextStyle(
                    color: HomeTheme.accentPink,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
