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
            HomeTheme.bg.withValues(alpha: scrollOffset / 255),
            HomeTheme.bg,
          ],
        ),
      ),
    );
  }
}
