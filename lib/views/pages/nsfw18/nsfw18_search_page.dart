import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:prismhub/router/router.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/prismhub_storage.dart';
import 'package:prismhub/utils/router.dart';
import 'package:prismhub/views/pages/nsfw18/nsfw18_lock_page.dart';
import 'package:prismhub/views/pages/search/search_page.dart';
import 'package:prismhub/views/widgets/button.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/messenger.dart';

// Abre la zona +18 del buscador, empujándola ENCIMA del buscador normal (no lo
// reemplaza) para que al salir se vuelva a él con sus resultados intactos.
//
// Ramifica por plataforma igual que ExtensionUtils.openExtensionDetail, y no por
// gusto: en escritorio la navegación la maneja go_router, el navegador de GetX no
// está activo (main.dart usa GetMaterialApp con home solo para Android) y por eso
// Get.to allá NO HACE NADA — confirmado en vivo, el botón no abría en Windows
// mientras en Android sí.
Future<void> openNsfw18Search(
  BuildContext context, {
  // true cuando se llama desde ADENTRO de la Zona +18, donde el usuario ya pasó
  // por la confirmación y el PIN para entrar. Volver a pedírselos para moverse
  // dentro de la misma zona es pedir la llave de una puerta que ya está
  // abierta, y encima la biometría se dispara de nuevo.
  bool yaAutorizado = false,
}) async {
  if (yaAutorizado) {
    // Navigator y no el router ni Get.to, en las tres plataformas:
    // - el router obligaría a marcar "ya autorizado" en la URL, o sea dejar
    //   publicada una ruta que entra al contenido +18 SIN compuerta;
    // - Get.to no navega en escritorio (ver el comentario de abajo).
    //
    // Además queda apilada ENCIMA de la Zona +18, así que volver atrás cae
    // siempre en el home +18, que es lo que se espera al entrar desde ahí.
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const Nsfw18SearchGate(yaAutorizado: true),
      ),
    );
    return;
  }
  if (Platform.isAndroid) {
    await Get.to(() => const Nsfw18SearchGate());
    return;
  }
  router.push('/adult-search');
}

// Compuerta de la zona +18 del buscador. Mismo criterio que Nsfw18ZoneGate:
// 1. El switch de NSFW en Ajustes tiene que estar prendido.
// 2. Confirmación "¿querés entrar?" — SIEMPRE, cada vez.
// 3. PIN (o configurarlo la primera vez) — SIEMPRE también, sin recordar el
//    desbloqueo entre entradas (ver el comentario de Nsfw18Zone).
class Nsfw18SearchGate extends StatefulWidget {
  const Nsfw18SearchGate({super.key, this.yaAutorizado = false});

  /// Se entra desde adentro de la Zona +18, donde la compuerta ya se pasó.
  /// Ver openNsfw18Search. El switch de NSFW se sigue mirando igual: si se
  /// apagó mientras tanto, esta pantalla se cierra sola.
  final bool yaAutorizado;

  @override
  State<Nsfw18SearchGate> createState() => _Nsfw18SearchGateState();
}

class _Nsfw18SearchGateState extends State<Nsfw18SearchGate> {
  late bool _confirmed = widget.yaAutorizado;
  late bool _unlocked = widget.yaAutorizado;
  bool _askedConfirm = false;

  bool get _nsfwEnabled =>
      PrismHubStorage.getSetting(SettingKey.enableNSFW) == true;

  @override
  void initState() {
    super.initState();
    if (_nsfwEnabled && !widget.yaAutorizado) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _confirmEnter());
    }
  }

  // Cerrar esta zona = volver al buscador normal. Es una ruta empujada, así que
  // alcanza con un pop; si por lo que sea ya no se puede popear, no se hace
  // nada en vez de arriesgar una navegación rara.
  void _close() {
    if (!mounted) return;
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  Future<void> _confirmEnter() async {
    if (_askedConfirm || !mounted) return;
    _askedConfirm = true;
    final result = await showPlatformDialog(
      context: context,
      title: 'nsfw18.search-enter-title'.i18n,
      content: Text('nsfw18.search-enter-content'.i18n),
      actions: [
        PlatformTextButton(
          onPressed: () => RouterUtils.pop(false),
          child: Text('nsfw18.search-enter-no'.i18n),
        ),
        PlatformFilledButton(
          onPressed: () => RouterUtils.pop(true),
          child: Text('nsfw18.search-enter-yes'.i18n),
        ),
      ],
    );
    if (!mounted) return;
    if (result == true) {
      setState(() => _confirmed = true);
    } else {
      _close();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_nsfwEnabled) {
      // No debería llegarse acá (el botón no se muestra con el switch apagado),
      // pero si se llega —por ejemplo apagándolo en otra pestaña— se sale sola
      // en vez de mostrar una pantalla vacía.
      WidgetsBinding.instance.addPostFrameCallback((_) => _close());
      return Scaffold(
          backgroundColor: HomeTheme.bg, body: SizedBox.shrink());
    }
    // Mientras el diálogo de confirmación está arriba, el fondo va en negro y
    // sin contenido: nada de contenido +18 antes de que confirme y ponga el PIN.
    if (!_confirmed) {
      return Scaffold(
          backgroundColor: HomeTheme.bg, body: SizedBox.shrink());
    }
    if (!_unlocked) {
      return Nsfw18LockPage(
        onUnlocked: () => setState(() => _unlocked = true),
      );
    }
    return const _Nsfw18SearchScaffold();
  }
}

// La zona en sí: el mismo buscador de siempre en modo nsfwOnly (acento rojo),
// más una cabecera propia para que quede claro dónde está parado y cómo salir.
// En Android SearchPage ya trae su propio Scaffold con AppBar, así que la
// cabecera extra solo se agrega en escritorio, donde no hay ninguna.
class _Nsfw18SearchScaffold extends StatelessWidget {
  const _Nsfw18SearchScaffold();

  @override
  Widget build(BuildContext context) {
    const search = SearchPage(nsfwOnly: true);
    // Android: SearchPage ya trae su propio Scaffold, y en modo +18 su AppBar
    // sale con título rojo y flecha para salir (ver search_page.dart), así que
    // no hace falta —ni conviene— apilarle otra cabecera encima.
    if (Platform.isAndroid) return search;
    return Container(
      color: HomeTheme.bg,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              gradient: HomeTheme.heroGradientRed,
            ),
            child: Row(
              children: [
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () {
                      if (Navigator.of(context).canPop()) {
                        Navigator.of(context).pop();
                      }
                    },
                    child: Padding(
                      padding: EdgeInsets.only(right: 12),
                      child: Icon(Icons.arrow_back,
                          color: HomeTheme.textPrimary, size: 20),
                    ),
                  ),
                ),
                Icon(Icons.warning_amber_rounded,
                    color: HomeTheme.textPrimary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'nsfw18.search-zone-title'.i18n,
                    style: TextStyle(
                      color: HomeTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Expanded(child: search),
        ],
      ),
    );
  }
}
