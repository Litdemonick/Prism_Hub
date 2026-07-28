import 'dart:io';

import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  Animation<double>? _glow;

  bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  @override
  void initState() {
    super.initState();
    if (!_isDesktop) {
      final controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1800),
      );
      _controller = controller;
      _glow = CurvedAnimation(
        parent: controller,
        curve: Curves.easeInOut,
      );
      controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF08080F),
      // LayoutBuilder + logo con ancho relativo a la altura disponible: con
      // un ancho fijo de 260, en horizontal (la altura de pantalla de un
      // celular es mucho menor que en vertical) la columna no entraba y
      // tiraba overflow — confirmado en vivo al recargar en horizontal.
      // SingleChildScrollView es la red de seguridad final: aunque el cálculo
      // de tamaño no sea perfecto en algún dispositivo raro, nunca debería
      // aparecer un banner de overflow en una pantalla de splash.
      body: LayoutBuilder(
        builder: (context, constraints) {
          final logoSize = (constraints.maxHeight * 0.32).clamp(120.0, 260.0);
          final logo = Image.asset(
            'assets/icon/logo_mark.png',
            width: logoSize,
          );
          final logoWidget = _isDesktop
              ? RepaintBoundary(child: logo)
              : AnimatedBuilder(
                  animation: _glow!,
                  builder: (context, child) {
                    final t = _glow!.value;
                    return Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFD777ED)
                                .withValues(alpha: 0.18 + t * 0.14),
                            blurRadius: 60 + t * 30,
                            spreadRadius: 4 + t * 6,
                          ),
                        ],
                      ),
                      child: child,
                    );
                  },
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.9, end: 1.0),
                    duration: const Duration(milliseconds: 900),
                    curve: Curves.easeOutCubic,
                    builder: (context, scale, child) => Transform.scale(
                      scale: scale,
                      child: child,
                    ),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: const Duration(milliseconds: 700),
                      builder: (context, opacity, child) => Opacity(
                        opacity: opacity,
                        child: child,
                      ),
                      child: logo,
                    ),
                  ),
                );
          return Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  logoWidget,
                  const SizedBox(height: 36),
                  const SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Color(0xFFD777ED)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
