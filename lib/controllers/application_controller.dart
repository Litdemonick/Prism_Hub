import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ApplicationController extends GetxController {
  static get find => Get.find();

  // La app entera usa un solo tema oscuro con acento rosa (HomeTheme) desde
  // el rediseño — Home, Búsqueda, Detalle y el lector ya no responden al
  // selector de tema (quedaban fijos igual), así que ofrecer claro/oscuro/
  // sistema era engañoso (elegías "Claro" y la mayoría de la app seguía
  // oscura). Se saca la opción y se fuerza oscuro siempre.
  ThemeMode get theme => ThemeMode.dark;
}
