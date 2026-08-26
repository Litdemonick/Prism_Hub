import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:prismhub/views/widgets/platform_widget.dart';
import 'package:easy_refresh/easy_refresh.dart';

class InfiniteScroller extends StatefulWidget {
  const InfiniteScroller({
    super.key,
    required this.child,
    required this.onRefresh,
    required this.onLoad,
    this.refreshOnStart = true,
    this.enableInfiniteScroll = true,
    this.easyRefreshController,
  });

  final Widget child;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onLoad;
  final bool refreshOnStart;
  final bool enableInfiniteScroll;
  final EasyRefreshController? easyRefreshController;

  @override
  State<InfiniteScroller> createState() => _InfiniteScrollerState();
}

class _InfiniteScrollerState extends State<InfiniteScroller> {
  bool _isLoding = false;

  @override
  void initState() {
    if (!Platform.isAndroid && widget.refreshOnStart) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        widget.onRefresh();
      });
    }
    super.initState();
  }

  void _onScroll(ScrollMetrics metrics) {
    if (metrics.atEdge && metrics.pixels == metrics.maxScrollExtent) {
      if (_isLoding || !widget.enableInfiniteScroll) {
        return;
      }
      // Se marca ANTES de llamar, no solo al terminar. `_isLoding` nunca se
      // ponía en true acá arriba, así que este chequeo de guardia no
      // guardaba nada: cada notificación de scroll mientras se está en el
      // borde (el mouse no se mueve entero de una, manda varias seguidas)
      // volvía a llamar a `onLoad()`, una encima de la otra. El controller
      // de cada pantalla se defiende por su cuenta (`cargando`/`cargandoMas`
      // en `ZonaCatalogoController`, `isFetching` en `SearchController`), así
      // que nunca se vio contenido duplicado — pero de acá salían pedidos de
      // más que se descartaban solos, en todas las pantallas de escritorio
      // que usan este widget.
      setState(() {
        _isLoding = true;
      });
      widget.onLoad().then((_) {
        if (mounted) {
          setState(() {
            _isLoding = false;
          });
        }
      });
    }
  }

  Widget _buildAndroid(BuildContext context) {
    return EasyRefresh(
      controller: widget.easyRefreshController,
      onRefresh: widget.onRefresh,
      header: const ClassicHeader(
        processedDuration: Duration.zero,
        showMessage: false,
        showText: false,
      ),
      footer: const ClassicFooter(
        processedDuration: Duration.zero,
        showMessage: false,
        showText: false,
      ),
      refreshOnStart: widget.refreshOnStart,
      onLoad: widget.onLoad,
      child: widget.child,
    );
  }

  Widget _buildDesktop(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollUpdateNotification) {
          _onScroll(notification.metrics);
        }
        return false;
      },
      child: widget.child,
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
