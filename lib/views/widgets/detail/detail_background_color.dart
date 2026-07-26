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
    widget.controller.addListener(() {
      setState(() {
        scrollOffset = widget.controller.offset;
        if (scrollOffset >= 255) {
          scrollOffset = 255;
        }
      });
    });
    super.initState();
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
