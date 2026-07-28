import 'package:flutter/material.dart';

class DetailAppbarTitle extends StatefulWidget {
  const DetailAppbarTitle(
    this.text, {
    super.key,
    required this.controller,
  });
  final String text;
  final ScrollController controller;

  @override
  State<DetailAppbarTitle> createState() => _DetailAppbarTitleState();
}

class _DetailAppbarTitleState extends State<DetailAppbarTitle> {
  bool _visible = false;

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
    final visible = widget.controller.offset > 300;
    if (visible == _visible) return;
    setState(() => _visible = visible);
  }

  double _scrollListener() {
    return _visible ? 1 : 0;
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      widget.text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      softWrap: false,
      style: TextStyle(
        color: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.color!
            .withValues(alpha: _scrollListener()),
      ),
    );
  }
}
