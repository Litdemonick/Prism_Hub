import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:prismhub/utils/platform_tv.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/platform_widget.dart';

class PlatformButton extends StatelessWidget {
  const PlatformButton({
    super.key,
    required this.child,
    this.onPressed,
  });
  final Widget child;
  final VoidCallback? onPressed;

  Widget _builaAndroidButton(BuildContext context) {
    return ElevatedButton(onPressed: onPressed, child: child);
  }

  Widget _builaDesktopButton(BuildContext context) {
    return fluent.Button(onPressed: onPressed, child: child);
  }

  @override
  Widget build(BuildContext context) {
    return PlatformBuildWidget(
      androidBuilder: _builaAndroidButton,
      desktopBuilder: _builaDesktopButton,
    );
  }
}

/// El estilo de un botón de diálogo en el televisor.
///
/// ── Por qué hace falta uno propio ────────────────────────────────────────
///
/// El resaltado de foco de Material es un velo translúcido por encima del
/// botón: pensado para ratón, donde el cursor ya dice dónde está uno parado
/// y el velo es apenas un refuerzo. Con el mando ese velo es la ÚNICA pista,
/// y acá se perdía por partida doble: el botón principal ya viene relleno
/// del color de acento, así que un velo del mismo tono encima no cambia
/// nada; y el secundario, al enfocarse, se pintaba de ESE MISMO acento, con
/// lo cual los dos terminaban rosas y no se sabía cuál estaba elegido.
/// Reportado en vivo: «es rosado el botón, el otro sí se ve pero feo».
///
/// ── La regla ─────────────────────────────────────────────────────────────
///
/// El foco NO se marca con más color: se marca INVIRTIENDO el botón. Lo
/// enfocado pasa a fondo claro con texto oscuro y un aro alrededor; lo que
/// no tiene el foco se queda como estaba (relleno de acento el principal,
/// transparente el secundario). Así los dos estados son opuestos entre sí y
/// los dos botones nunca se parecen, que es lo que hacía falta desde tres
/// metros de distancia.
///
/// [destacado] distingue al botón principal (relleno de acento en reposo)
/// del secundario (transparente).
ButtonStyle estiloDeFocoTv({required bool destacado}) {
  return ButtonStyle(
    foregroundColor: WidgetStateProperty.resolveWith((estados) {
      if (estados.contains(WidgetState.focused)) return HomeTheme.bg;
      return destacado ? Colors.white : HomeTheme.textPrimary;
    }),
    backgroundColor: WidgetStateProperty.resolveWith((estados) {
      if (estados.contains(WidgetState.focused)) return Colors.white;
      return destacado ? HomeTheme.accentPink : Colors.transparent;
    }),
    // El aro de afuera, además del relleno invertido: el relleno solo ya
    // alcanza sobre el fondo oscuro del diálogo, pero el aro es lo que hace
    // que se lea igual de claro si el diálogo alguna vez cambia de color.
    side: WidgetStateProperty.resolveWith((estados) {
      if (estados.contains(WidgetState.focused)) {
        return const BorderSide(color: Colors.white, width: 2);
      }
      return destacado
          ? BorderSide.none
          : BorderSide(color: HomeTheme.border, width: 1);
    }),
    // Sin el velo de siempre: acá el foco ya se marca de otra forma, y
    // dejarlo solo ensucia el contraste que se acaba de ganar.
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    // Más grandes que en el teléfono: se miran de lejos y se apuntan con un
    // mando, no con el dedo.
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 24, vertical: 16),
    ),
    textStyle: const WidgetStatePropertyAll(
      TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    ),
    shape: WidgetStateProperty.all(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );
}

class PlatformFilledButton extends StatelessWidget {
  const PlatformFilledButton({
    super.key,
    required this.child,
    this.onPressed,
  });
  final Widget child;
  final VoidCallback? onPressed;

  Widget _builaAndroidButton(BuildContext context) {
    if (!PlatformTv.esTelevisionSync) {
      return FilledButton(onPressed: onPressed, child: child);
    }
    // En TV este botón ya viene relleno del color de acento, así que su
    // resaltado de foco de fábrica —un velo del mismo tono por encima— no se
    // distingue de su estado normal: con el mando no había forma de saber si
    // estaba seleccionado. Ver `estiloDeFocoTv`.
    return FilledButton(
      onPressed: onPressed,
      style: estiloDeFocoTv(destacado: true),
      child: child,
    );
  }

  Widget _builaDesktopButton(BuildContext context) {
    return fluent.FilledButton(onPressed: onPressed, child: child);
  }

  @override
  Widget build(BuildContext context) {
    return PlatformBuildWidget(
      androidBuilder: _builaAndroidButton,
      desktopBuilder: _builaDesktopButton,
    );
  }
}

class PlatformTextButton extends StatelessWidget {
  const PlatformTextButton({
    super.key,
    required this.child,
    this.onPressed,
  });
  final Widget child;
  final VoidCallback? onPressed;

  Widget _builaAndroidButton(BuildContext context) {
    if (!PlatformTv.esTelevisionSync) {
      return TextButton(onPressed: onPressed, child: child);
    }
    // El foco NO se marca pintando este botón del color de acento: eso lo
    // dejaba igual que el botón principal, que ya viene relleno de ese
    // color, y no se sabía cuál de los dos estaba elegido. Se invierte, como
    // el otro — ver `estiloDeFocoTv`.
    return TextButton(
      onPressed: onPressed,
      style: estiloDeFocoTv(destacado: false),
      child: child,
    );
  }

  Widget _builaDesktopButton(BuildContext context) {
    return fluent.HyperlinkButton(onPressed: onPressed, child: child);
  }

  @override
  Widget build(BuildContext context) {
    return PlatformBuildWidget(
      androidBuilder: _builaAndroidButton,
      desktopBuilder: _builaDesktopButton,
    );
  }
}

class PlatformIconButton extends StatelessWidget {
  const PlatformIconButton({
    super.key,
    required this.icon,
    this.onPressed,
  });
  final Widget icon;
  final VoidCallback? onPressed;

  Widget _builaAndroidButton(BuildContext context) {
    return IconButton(onPressed: onPressed, icon: icon);
  }

  Widget _builaDesktopButton(BuildContext context) {
    return fluent.IconButton(onPressed: onPressed, icon: icon);
  }

  @override
  Widget build(BuildContext context) {
    return PlatformBuildWidget(
      androidBuilder: _builaAndroidButton,
      desktopBuilder: _builaDesktopButton,
    );
  }
}

class PlatformToggleButton extends fluent.StatelessWidget {
  const PlatformToggleButton({
    super.key,
    required this.checked,
    required this.onChanged,
    required this.text,
  });

  final bool checked;
  final void Function(bool)? onChanged;
  final String text;

  Widget _buildAndroid(BuildContext context) {
    return TextButton(
      onPressed: () => onChanged?.call(!checked),
      style: ButtonStyle(
        side: WidgetStateProperty.all(
          BorderSide(
            color: checked
                ? Theme.of(context).colorScheme.primary
                : Colors.transparent,
          ),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: checked
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }

  Widget _buildDesktop(BuildContext context) {
    return fluent.ToggleButton(
      checked: checked,
      onChanged: onChanged,
      child: Text(text),
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
