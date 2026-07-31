import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/nsfw18_zone.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';

// Pantalla de bloqueo de la Zona +18. Dos modos según si ya hay un PIN
// guardado (ver Nsfw18Zone.isPinConfigured):
// - Primera vez: pide elegir un PIN (+ confirmación) antes de dejar entrar.
// - Ya configurado: pide el PIN existente.
// onUnlocked se llama recién después de una verificación/creación exitosa —
// quien la use (Nsfw18ZoneGate) todavía no muestra nada de la zona hasta eso.
class Nsfw18LockPage extends StatefulWidget {
  const Nsfw18LockPage({super.key, required this.onUnlocked});
  final VoidCallback onUnlocked;

  @override
  State<Nsfw18LockPage> createState() => _Nsfw18LockPageState();
}

class _Nsfw18LockPageState extends State<Nsfw18LockPage> {
  late final bool _isSetup = !Nsfw18Zone.isPinConfigured;
  final _pinController = TextEditingController();
  final _confirmController = TextEditingController();
  final _focusNode = FocusNode();
  String? _error;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pin = _pinController.text.trim();
    if (pin.length < 4) {
      setState(() => _error = 'nsfw18.pin-too-short'.i18n);
      return;
    }
    if (_isSetup) {
      if (pin != _confirmController.text.trim()) {
        setState(() => _error = 'nsfw18.pin-mismatch'.i18n);
        return;
      }
      setState(() => _submitting = true);
      await Nsfw18Zone.setPin(pin);
      widget.onUnlocked();
      return;
    }
    if (!Nsfw18Zone.verifyPin(pin)) {
      setState(() {
        _error = 'nsfw18.pin-wrong'.i18n;
        _pinController.clear();
      });
      return;
    }
    widget.onUnlocked();
  }

  InputDecoration _decoration(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: HomeTheme.textMuted),
        filled: true,
        fillColor: HomeTheme.cardSurface,
        errorText: null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: HomeTheme.accentRed, width: 1.5),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HomeTheme.bg,
      appBar: AppBar(
        backgroundColor: HomeTheme.bg,
        iconTheme: const IconThemeData(color: HomeTheme.textPrimary),
        title: Text(
          'nsfw18.title'.i18n,
          style: const TextStyle(color: HomeTheme.textPrimary),
        ),
      ),
      // Antes: Center directo, sin SingleChildScrollView — en horizontal en
      // un celular la altura disponible es chica y con el teclado abierto
      // los campos/botón de abajo quedaban tapados o directamente recortados
      // (RenderFlex overflow), sin ninguna forma de bajar a verlos
      // (confirmado en vivo). LayoutBuilder+ConstrainedBox con minHeight
      // mantiene todo centrado verticalmente cuando entra entero (como
      // antes) y deja scrollear cuando no entra.
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: HomeTheme.accentRed.withValues(alpha: 0.6),
                              width: 1.5,
                            ),
                          ),
                          child: const Icon(
                            Icons.lock_outline,
                            color: HomeTheme.accentRed,
                            size: 28,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          _isSetup
                              ? 'nsfw18.setup-title'.i18n
                              : 'nsfw18.enter-title'.i18n,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: HomeTheme.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _isSetup
                              ? 'nsfw18.setup-subtitle'.i18n
                              : 'nsfw18.enter-subtitle'.i18n,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: HomeTheme.textMuted, fontSize: 13),
                        ),
                        const SizedBox(height: 24),
                        TextField(
                          controller: _pinController,
                          focusNode: _focusNode,
                          obscureText: true,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          maxLength: 8,
                          style: const TextStyle(color: HomeTheme.textPrimary),
                          decoration: _decoration('nsfw18.pin-label'.i18n),
                          onSubmitted: (_) {
                            if (!_isSetup) _submit();
                          },
                        ),
                        if (_isSetup) ...[
                          const SizedBox(height: 8),
                          TextField(
                            controller: _confirmController,
                            obscureText: true,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly
                            ],
                            maxLength: 8,
                            style:
                                const TextStyle(color: HomeTheme.textPrimary),
                            decoration:
                                _decoration('nsfw18.pin-confirm-label'.i18n),
                            onSubmitted: (_) => _submit(),
                          ),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            _error!,
                            style: const TextStyle(
                                color: Colors.redAccent, fontSize: 13),
                          ),
                        ],
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: HomeTheme.accentRed,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            onPressed: _submitting ? null : _submit,
                            child: Text(
                              _isSetup
                                  ? 'nsfw18.setup-confirm'.i18n
                                  : 'nsfw18.unlock'.i18n,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
