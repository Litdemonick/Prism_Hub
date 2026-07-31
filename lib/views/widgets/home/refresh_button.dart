import 'package:flutter/material.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';

// Botón de recargar para PC — el equivalente al RefreshIndicator (deslizar)
// que en Android ya existe con el dedo pero no con mouse. Gira mientras
// espera para dar feedback de que sí está haciendo algo, no solo un ícono
// estático. Compartido entre Home, Búsqueda y el catálogo de una extensión.
class RefreshButton extends StatefulWidget {
  const RefreshButton({super.key, required this.onTap});
  final Future<void> Function() onTap;

  @override
  State<RefreshButton> createState() => _RefreshButtonState();
}

class _RefreshButtonState extends State<RefreshButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spinController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  bool _isHover = false;
  bool _isRefreshing = false;

  @override
  void dispose() {
    _spinController.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    _spinController.repeat();
    try {
      await widget.onTap();
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
        _spinController
          ..stop()
          ..reset();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHover = true),
      onExit: (_) => setState(() => _isHover = false),
      child: GestureDetector(
        onTap: _handleTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: _isHover
                ? HomeTheme.accentPink.withValues(alpha: 0.18)
                : HomeTheme.cardSurface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: _isHover ? HomeTheme.accentPink : HomeTheme.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              RotationTransition(
                turns: _spinController,
                child: Icon(
                  Icons.refresh_rounded,
                  size: 16,
                  color:
                      _isHover ? HomeTheme.accentPink : HomeTheme.textPrimary,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'common.refresh'.i18n,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color:
                      _isHover ? HomeTheme.accentPink : HomeTheme.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
