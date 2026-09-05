import 'dart:io';

import 'package:flutter/material.dart';
import 'package:prismhub/utils/platform_tv.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/nsfw18_zone.dart';
import 'package:prismhub/utils/router.dart';
import 'package:prismhub/views/pages/nsfw18/nsfw18_lock_page.dart'
    show CampoPinTv;
import 'package:prismhub/views/widgets/button.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/messenger.dart';
import 'package:prismhub/views/widgets/settings/settings_tile.dart';
import 'package:prismhub/views/widgets/tv/pad_numerico_tv.dart';

// Entrada de Ajustes para configurar/cambiar/quitar el PIN de la Zona +18.
// Widget autocontenido (maneja su propio estado de "¿ya hay PIN?") para no
// tener que tocar el State de SettingsPage entero solo por esto.
class Nsfw18PinSettingsTile extends StatefulWidget {
  const Nsfw18PinSettingsTile({super.key});

  @override
  State<Nsfw18PinSettingsTile> createState() => _Nsfw18PinSettingsTileState();
}

class _Nsfw18PinSettingsTileState extends State<Nsfw18PinSettingsTile> {
  bool _configured = Nsfw18Zone.isPinConfigured;

  String get _pinDialogTitle => _configured
      ? 'nsfw18.settings-pin-change'.i18n
      : 'nsfw18.settings-pin-set'.i18n;

  Future<void> _openSetPinDialog() async {
    // Android comparte el diálogo con la pantalla de televisor (ver
    // abrirDialogoDePin). Escritorio se queda con el suyo, que tiene el
    // aspecto fluent del resto de la app y ahí funciona bien.
    final saved = Platform.isAndroid
        ? await abrirDialogoDePin(context)
        : await _openDesktopSetPinDialog() == true;
    if (saved && mounted) {
      setState(() => _configured = true);
    }
  }

  Future<bool?> _openDesktopSetPinDialog() async {
    final pinController = TextEditingController();
    final confirmController = TextEditingController();
    // ValueNotifier en vez de StatefulBuilder: los botones Guardar/Cancelar
    // van en el `actions:` REAL del diálogo (mismo patrón que el resto de
    // la app) en vez de metidos a mano adentro del `content` — meterlos ahí
    // duplicaba la elevación/sombra de Material sobre la propia sombra del
    // diálogo, así que se veía un recuadro con sombra rara alrededor de los
    // botones.
    final errorNotifier = ValueNotifier<String?>(null);

    Future<void> save() async {
      final pin = pinController.text.trim();
      if (pin.length < 4) {
        errorNotifier.value = 'nsfw18.pin-too-short'.i18n;
        return;
      }
      if (pin != confirmController.text.trim()) {
        errorNotifier.value = 'nsfw18.pin-mismatch'.i18n;
        return;
      }
      await Nsfw18Zone.setPin(pin);
      RouterUtils.pop(true);
    }

    final saved = await showPlatformDialog(
      context: context,
      title: _pinDialogTitle,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: pinController,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 8,
            decoration: InputDecoration(labelText: 'nsfw18.pin-label'.i18n),
          ),
          TextField(
            controller: confirmController,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 8,
            decoration:
                InputDecoration(labelText: 'nsfw18.pin-confirm-label'.i18n),
            onSubmitted: (_) => save(),
          ),
          ValueListenableBuilder<String?>(
            valueListenable: errorNotifier,
            builder: (context, error, _) {
              if (error == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  error,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              );
            },
          ),
        ],
      ),
      actions: [
        PlatformTextButton(
          onPressed: () => RouterUtils.pop(false),
          child: Text('common.cancel'.i18n),
        ),
        PlatformFilledButton(
          onPressed: save,
          child: Text('common.confirm'.i18n),
        ),
      ],
    );
    errorNotifier.dispose();
    // Los TextEditingController se creaban por diálogo y nunca se liberaban
    // (cada apertura dejaba dos colgados). Acá el diálogo ya cerró, así que sus
    // TextField están desmontados y es seguro liberarlos.
    pinController.dispose();
    confirmController.dispose();
    return saved is bool ? saved : null;
  }

  Future<void> _confirmRemovePin() async {
    final result = await showPlatformDialog(
      context: context,
      title: 'nsfw18.settings-pin-remove'.i18n,
      content: Text('nsfw18.settings-pin-remove-confirm'.i18n),
      actions: [
        PlatformTextButton(
          onPressed: () => RouterUtils.pop(false),
          child: Text('common.cancel'.i18n),
        ),
        PlatformFilledButton(
          onPressed: () => RouterUtils.pop(true),
          child: Text('common.confirm'.i18n),
        ),
      ],
    );
    if (result == true) {
      await Nsfw18Zone.clearPin();
      if (mounted) setState(() => _configured = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SettingsTile(
          icon: Icon(Icons.pin_outlined, color: HomeTheme.accentRed),
          title: 'nsfw18.settings-pin'.i18n,
          buildSubtitle: () => 'nsfw18.settings-pin-subtitle'.i18n,
          trailing: Text(
            _configured
                ? 'nsfw18.settings-pin-change'.i18n
                : 'nsfw18.settings-pin-set'.i18n,
            style: TextStyle(color: HomeTheme.accentRed),
          ),
          onTap: _openSetPinDialog,
        ),
        if (_configured)
          SettingsTile(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            title: 'nsfw18.settings-pin-remove'.i18n,
            trailing: const Icon(Icons.chevron_right, color: Colors.redAccent),
            onTap: _confirmRemovePin,
          ),
      ],
    );
  }
}

// Diálogo de PIN para Android. Es un Dialog armado a mano en vez de un
// AlertDialog porque el problema acá es de ALTO, no de scroll: en horizontal la
// pantalla mide ~270 puntos lógicos de alto y el teclado numérico se come más de
// la mitad, dejando ~120 para todo el diálogo. Con AlertDialog el título y los
// `actions` tienen posición fija y no hay forma de compactarlos, así que se
// dibujaban encima de los campos (confirmado en vivo).
//
// Acá, cuando el alto útil es chico: se omite el título (los propios campos ya
// dicen "PIN" y "Confirmar PIN"), los dos campos van uno al lado del otro en una
// fila, sin el contador "0/8" y densos, y los botones quedan en una sola fila
// debajo. Eso baja el alto necesario de ~5 filas a 2. En vertical se ve como un
// diálogo normal, con título y campos apilados.
class _PinDialog extends StatefulWidget {
  const _PinDialog({required this.title});

  final String title;

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final _pinController = TextEditingController();
  final _confirmController = TextEditingController();
  String? _error;

  /// A qué campo le escribe el pad numérico de TV — mismo mecanismo que
  /// `Nsfw18LockPage._campoTvSeleccionado`: acá no hay cursor que mirar, así
  /// que el usuario elige a mano cuál de los dos campos está llenando.
  bool _campoTvSeleccionado = false; // false = PIN, true = confirmación
  TextEditingController get _campoActivoTv =>
      _campoTvSeleccionado ? _confirmController : _pinController;

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final pin = _pinController.text.trim();
    if (pin.length < 4) {
      setState(() => _error = 'nsfw18.pin-too-short'.i18n);
      return;
    }
    if (pin != _confirmController.text.trim()) {
      setState(() => _error = 'nsfw18.pin-mismatch'.i18n);
      return;
    }
    await Nsfw18Zone.setPin(pin);
    if (mounted) Navigator.of(context).pop(true);
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required bool compact,
    bool autofocus = false,
    VoidCallback? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      obscureText: true,
      keyboardType: TextInputType.number,
      maxLength: 8,
      textInputAction:
          onSubmitted == null ? TextInputAction.next : TextInputAction.done,
      onSubmitted: onSubmitted == null ? null : (_) => onSubmitted(),
      decoration: InputDecoration(
        labelText: label,
        isDense: compact,
        // counterText vacío oculta el "0/8", que ocupa una fila entera debajo
        // de cada campo — en horizontal ese alto es justo el que falta.
        counterText: compact ? '' : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Con los getters acotados y no con `MediaQuery.of(context)` entero: así
    // esta fila se reconstruye cuando cambia el ALTO o el TECLADO, que es lo
    // único que mira, y no cada vez que cambia cualquier cosa del entorno.
    final alto = MediaQuery.sizeOf(context).height;
    final tecladoAbajo = MediaQuery.viewInsetsOf(context).bottom;
    // Lo que de verdad queda libre arriba del teclado. Dialog ya le suma
    // viewInsets a su padding, pero se mide igual acá para decidir el layout:
    // el umbral tiene que mirar el hueco real, no el alto de la pantalla (en
    // vertical con el teclado abierto sobra espacio; en horizontal no).
    final free = alto - tecladoAbajo;
    final compact = free < 280;

    final pinField = _field(
      controller: _pinController,
      label: 'nsfw18.pin-label'.i18n,
      compact: compact,
      autofocus: true,
    );
    final confirmField = _field(
      controller: _confirmController,
      label: 'nsfw18.pin-confirm-label'.i18n,
      compact: compact,
      onSubmitted: _save,
    );

    final actions = Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        PlatformTextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('common.cancel'.i18n),
        ),
        const SizedBox(width: 8),
        PlatformFilledButton(
          onPressed: _save,
          child: Text('common.confirm'.i18n),
        ),
      ],
    );

    // ── En televisor: el teclado propio, no el del sistema ──────────────
    //
    // Antes esto usaba los mismos `TextField` de siempre, apenas
    // reacomodados a lo ancho: título y campos a la izquierda, botones a
    // la derecha. El problema no era el acomodo, era que un `TextField`
    // real en TV levanta el teclado del PROPIO TELEVISOR al enfocarlo —
    // ese teclado no es de la app, y con el mando es tosco: en la práctica
    // no se podía navegar ni escribir. Reportado en vivo con foto, en
    // este diálogo puntual: «Cambiar PIN» desde Ajustes.
    //
    // `Nsfw18LockPage` (la pantalla de desbloqueo/configuración inicial)
    // ya había resuelto exactamente esto con su propio teclado numérico
    // (`PadNumericoTv`) y campos elegibles con el mando (`CampoPinTv`,
    // pública justo para poder compartirla acá). Este diálogo usa el
    // mismo mecanismo: no hay ningún `TextField` de por medio en TV, así
    // que no hay forma de que aparezca el teclado del sistema.
    if (PlatformTv.esTelevisionSync) {
      return Dialog(
        insetPadding: HomeTheme.margenTv(context),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                PadNumericoTv(
                  accent: HomeTheme.accentRed,
                  onDigito: (d) {
                    if (_campoActivoTv.text.length >= 8) return;
                    setState(() => _campoActivoTv.text += d);
                  },
                  onBorrar: () {
                    if (_campoActivoTv.text.isEmpty) return;
                    setState(() => _campoActivoTv.text = _campoActivoTv.text
                        .substring(0, _campoActivoTv.text.length - 1));
                  },
                ),
                const SizedBox(width: 40),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.pin_outlined,
                              color: HomeTheme.accentRed, size: 24),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              widget.title,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      CampoPinTv(
                        label: 'nsfw18.pin-label'.i18n,
                        controller: _pinController,
                        seleccionado: !_campoTvSeleccionado,
                        onTap: () =>
                            setState(() => _campoTvSeleccionado = false),
                      ),
                      const SizedBox(height: 12),
                      CampoPinTv(
                        label: 'nsfw18.pin-confirm-label'.i18n,
                        controller: _confirmController,
                        seleccionado: _campoTvSeleccionado,
                        onTap: () =>
                            setState(() => _campoTvSeleccionado = true),
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            _error!,
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: PlatformTextButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              child: Text('common.cancel'.i18n),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: PlatformFilledButton(
                              onPressed: _save,
                              child: Text('common.confirm'.i18n),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: 20,
        // Sin margen vertical en compacto: el hueco arriba del teclado es de
        // ~120 puntos y el contenido necesita ~110, así que regalar 16 de
        // margen era la diferencia entre entrar y no entrar. El Dialog está
        // centrado, así que igual no queda pegado a los bordes.
        vertical: compact ? 0 : 24,
      ),
      child: ConstrainedBox(
        // Techo de ancho para que en horizontal no se estire de borde a borde.
        // El alto NO se limita acá: Dialog ya recorta a lo que queda arriba del
        // teclado, y con eso el SingleChildScrollView de abajo tiene un viewport
        // acotado de verdad y puede desplazarse si aun así falta.
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
              compact ? 16 : 20, compact ? 10 : 20, compact ? 16 : 20, 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!compact) ...[
                Row(
                  children: [
                    Icon(Icons.pin_outlined,
                        color: HomeTheme.accentRed, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              if (compact)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: pinField),
                    const SizedBox(width: 12),
                    Expanded(child: confirmField),
                  ],
                )
              else ...[
                pinField,
                confirmField,
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _error!,
                    style: const TextStyle(
                        color: Colors.redAccent, fontSize: 12.5),
                  ),
                ),
              SizedBox(height: compact ? 4 : 8),
              actions,
            ],
          ),
        ),
      ),
    );
  }
}

/// Abre el diálogo de poner o cambiar el PIN de la Zona +18.
///
/// ── Por qué está suelta y no dentro de la fila de Ajustes ───────────────────
///
/// Esta pantalla existe en dos formas: la de PC y teléfono, que usa
/// [Nsfw18PinSettingsTile], y la de televisor, que dibuja sus propias filas
/// grandes para el mando. La segunda no podía abrir este diálogo porque vivía
/// dentro del estado privado de la primera — y por eso en televisor no había
/// forma de poner ni de cambiar el PIN.
///
/// Devuelve true si se guardó uno nuevo.
///
/// Android va por un diálogo propio y no por `showPlatformDialog`: el
/// `AlertDialog` de Material no da control sobre dónde van título y botones, y
/// en un teléfono en HORIZONTAL el espacio útil arriba del teclado es de unos
/// 120 puntos lógicos — ahí título, dos campos y dos botones no entran, y
/// Material los terminaba dibujando encima uno del otro.
Future<bool> abrirDialogoDePin(BuildContext context) async {
  final titulo = Nsfw18Zone.isPinConfigured
      ? 'nsfw18.settings-pin-change'.i18n
      : 'nsfw18.settings-pin-set'.i18n;
  // Solo Android —televisor incluido—. En escritorio el diálogo lo abre la
  // propia fila de Ajustes, que es donde vive ese camino y donde tiene el
  // aspecto del resto de la app.
  if (!Platform.isAndroid) return false;
  final r = await showDialog<bool>(
    context: context,
    builder: (_) => _PinDialog(title: titulo),
  );
  return r == true;
}
