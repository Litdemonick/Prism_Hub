import 'package:fluent_ui/fluent_ui.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';

class DetailBackgroundColor extends StatefulWidget {
  const DetailBackgroundColor({
    super.key,
    required this.controller,
  });
  final ScrollController controller;

  @override
  State<DetailBackgroundColor> createState() => _DetailBackgroundColorState();
}

class _DetailBackgroundColorState extends State<DetailBackgroundColor> {
  double scrollOffset = 0;

  /// Hasta dónde llega a taparse la portada del fondo.
  ///
  /// Con 1 (lo de antes) la imagen desaparecía del todo al bajar y volvía al
  /// subir, y parecía que se hubiera perdido. Quedándose en 0,86 todo lo que va
  /// encima se sigue leyendo igual —el degradado termina en el fondo sólido de
  /// la app unos centímetros más abajo— pero la portada nunca deja de estar.
  static const double _velo = 0.86;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleScroll);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleScroll);
    super.dispose();
  }

  void _handleScroll() {
    final next = widget.controller.offset.clamp(0.0, 255.0);
    if ((next - scrollOffset).abs() < 1) return;
    setState(() => scrollOffset = next);
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            HomeTheme.bg.withValues(alpha: (scrollOffset / 255) * _velo),
            HomeTheme.bg,
          ],
        ),
      ),
    );
  }
}
