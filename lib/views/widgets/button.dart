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

class PlatformFilledButton extends StatelessWidget {
  const PlatformFilledButton({
    super.key,
    required this.child,
    this.onPressed,
  });
  final Widget child;
  final VoidCallback? onPressed;

  Widget _builaAndroidButton(BuildContext context) {
    return FilledButton(onPressed: onPressed, child: child);
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
    // ── En TV, foco con fondo sólido ─────────────────────────────────────
    //
    // El resaltado de foco de un TextButton de Material es un velo MUY
    // sutil, pensado para mouse —ahí el cursor ya dice dónde está parado el
    // usuario, y el velo es solo un refuerzo—. Con el mando esa marca es la
    // ÚNICA pista de dónde se está parado, y contra el texto en
    // HomeTheme.accentPink (rosa) el velo casi del mismo tono se perdía por
    // completo. Reportado en vivo, en la pantalla de actualizar: «esos
    // botones al seleccionar con el control remoto no se ve por el color
    // rosado».
    //
    // Mismo criterio que ya se probó y funciona en el resto de la app (ver
    // FocusableCard / _ItemSidebarTV): en foco, un fondo OPACO y de
    // contraste alto, no un tinte translúcido del mismo color que ya hay
    // alrededor.
    return TextButton(
      onPressed: onPressed,
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.focused)) return Colors.white;
          return HomeTheme.accentPink;
        }),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.focused)) return HomeTheme.accentPink;
          return Colors.transparent;
        }),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
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
