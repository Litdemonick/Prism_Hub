import 'package:flutter/material.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/platform_widget.dart';

class ListTitle extends StatelessWidget {
  const ListTitle({super.key, required this.title});

  final String title;

  Widget _buildAndroid(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16),
      child: Text(
        title,
        style: TextStyle(
          color: HomeTheme.accentPink,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildDesktop(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontWeight: FontWeight.bold,
        color: HomeTheme.textPrimary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PlatformBuildWidget(
      androidBuilder: _buildAndroid,
      desktopBuilder: _buildDesktop,
    );
  }
}
