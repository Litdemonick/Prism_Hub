import 'package:flutter/material.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';

// Igual API que CardTile (título/leading/trailing/child) pero con la
// paleta de HomeTheme — CardTile es compartido con la página de
// configuración de extensiones, así que se hace una copia local en vez de
// tocar ese archivo (mismo criterio que el resto de las páginas ya
// rediseñadas: no tocar widgets compartidos con páginas sin rediseñar).
class DetailCardTile extends StatelessWidget {
  const DetailCardTile({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.leading,
  });
  final String title;
  final Widget? leading;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: HomeTheme.cardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: HomeTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: HomeTheme.textPrimary,
                  ),
                ),
                const SizedBox(width: 8),
                if (leading != null) leading!,
                const Spacer(),
                if (trailing != null) trailing!,
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 13),
            child: Divider(height: 1, color: HomeTheme.border),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: child,
          ),
        ],
      ),
    );
  }
}
