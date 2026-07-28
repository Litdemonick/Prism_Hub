import 'package:flutter/material.dart';
import 'package:prismhub/router/router.dart';

class LayoutUtils {
  static bool? _isTablet;

  static double get width {
    return MediaQuery.of(currentContext).size.width;
  }

  static double get height {
    return MediaQuery.of(currentContext).size.height;
  }

  static bool get isTablet {
    return _isTablet ??= width > 800;
  }
}
