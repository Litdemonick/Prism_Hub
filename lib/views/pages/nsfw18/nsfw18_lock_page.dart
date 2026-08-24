import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/nsfw18_biometric.dart';
import 'package:prismhub/utils/nsfw18_zone.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/utils/platform_tv.dart';
import 'package:prismhub/views/widgets/tv/pad_numerico_tv.dart';

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

  /// A qué campo le escribe el pad numérico de TV.
  ///
  /// Al configurar el PIN hay dos: se llena el primero y, cuando ya tiene
  /// algo, se pasa solo al de confirmación. Sin esto habría que elegir el
  /// campo a mano con el mando antes de poder escribir.
  TextEditingController _campoActivo() {
    if (!_isSetup) return _pinController;
    return _pinController.text.isEmpty ? _pinController : _confirmController;
  }
  final _focusNode = FocusNode();
  String? _error;
  bool _submitting = false;
  // Mientras se resuelve la credencial del sistema no se muestra el teclado
  // del PIN: primero la huella / Windows Hello, después el PIN.
  bool _verificandoIdentidad = true;
  bool _identidadRechazada = false;

  @override
  void initState() {
    super.initState();
    // La biometría va ACÁ y no en cada punto de entrada: esta pantalla es la
    // única puerta a la Zona +18 (la usan el acceso general, la búsqueda +18 y
    // la zona en sí), así que ponerla adentro la deja cubierta toda de una y
    // no hay forma de olvidarse en un camino nuevo.
    WidgetsBinding.instance.addPostFrameCallback((_) => _pedirIdentidad());
  }

  Future<void> _pedirIdentidad() async {
    final ok = await Nsfw18Biometric.authenticate();
    if (!mounted) return;
    setState(() {
      _verificandoIdentidad = false;
      _identidadRechazada = !ok;
    });
    if (ok) _focusNode.requestFocus();
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
    // Bloqueo por intentos fallidos: se avisa cuánto falta en vez de decir
    // "PIN incorrecto", que haría pensar que el PIN dejó de servir.
    final espera = Nsfw18Zone.lockedSeconds;
    if (espera > 0) {
      setState(() {
        _error = FlutterI18n.translate(
          context,
          'nsfw18.pin-locked',
          translationParams: {'seconds': '$espera'},
        );
        _pinController.clear();
      });
      return;
    }
    final ok = await Nsfw18Zone.verifyPinChecked(pin);
    if (!ok) {
      if (!mounted) return;
      final restante = Nsfw18Zone.lockedSeconds;
      setState(() {
        _error = restante > 0
            ? FlutterI18n.translate(
                context,
                'nsfw18.pin-locked',
                translationParams: {'seconds': '$restante'},
              )
            : 'nsfw18.pin-wrong'.i18n;
        _pinController.clear();
      });
      return;
    }
    widget.onUnlocked();
  }

  InputDecoration _decoration(String label) => InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: HomeTheme.textMuted),
        filled: true,
        fillColor: HomeTheme.cardSurface,
        errorText: null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: HomeTheme.accentRed, width: 1.5),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (_verificandoIdentidad || _identidadRechazada) {
      return Scaffold(
        backgroundColor: HomeTheme.bg,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _identidadRechazada ? Icons.lock_outline : Icons.fingerprint,
                  size: 52,
                  color: HomeTheme.accentRed,
                ),
                const SizedBox(height: 18),
                Text(
                  _identidadRechazada
                      ? 'nsfw18.biometric-denied'.i18n
                      : 'nsfw18.biometric-checking'.i18n,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: HomeTheme.textPrimary, fontSize: 14, height: 1.4),
                ),
                if (_identidadRechazada) ...[
                  const SizedBox(height: 20),
                  FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: HomeTheme.accentRed),
                    onPressed: () {
                      setState(() {
                        _verificandoIdentidad = true;
                        _identidadRechazada = false;
                      });
                      _pedirIdentidad();
                    },
                    child: Text('nsfw18.biometric-retry'.i18n),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: HomeTheme.bg,
      appBar: AppBar(
        backgroundColor: HomeTheme.bg,
        iconTheme: IconThemeData(color: HomeTheme.textPrimary),
        title: Text(
          'nsfw18.title'.i18n,
          style: TextStyle(color: HomeTheme.textPrimary),
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
                          child: Icon(
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
                          style: TextStyle(
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
                          style: TextStyle(
                              color: HomeTheme.textMuted, fontSize: 13),
                        ),
                        const SizedBox(height: 24),
                        TextField(
                          controller: _pinController,
                          focusNode: _focusNode,
                          obscureText: true,
                          // En TV no se enfoca: se escribe con el pad de
                          // abajo, y enfocarlo levantaría el teclado del
                          // sistema encima de todo.
                          readOnly: PlatformTv.esTelevisionSync,
                          canRequestFocus: !PlatformTv.esTelevisionSync,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          maxLength: 8,
                          style: TextStyle(color: HomeTheme.textPrimary),
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
                            readOnly: PlatformTv.esTelevisionSync,
                            canRequestFocus: !PlatformTv.esTelevisionSync,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly
                            ],
                            maxLength: 8,
                            style:
                                TextStyle(color: HomeTheme.textPrimary),
                            decoration:
                                _decoration('nsfw18.pin-confirm-label'.i18n),
                            onSubmitted: (_) => _submit(),
                          ),
                        ],
                        // El pad numérico, solo en TV: los campos de arriba
                        // siguen mostrando lo escrito, pero acá no se
                        // enfocan (ver más abajo) para que Android no
                        // levante su teclado encima.
                        //
                        // Al configurar el PIN hay DOS campos, así que el pad
                        // escribe en el que corresponda: primero el PIN y,
                        // cuando ese ya tiene algo, la confirmación. Es lo
                        // mismo que haría alguien con un teclado, sin tener
                        // que elegir el campo a mano.
                        if (PlatformTv.esTelevisionSync) ...[
                          const SizedBox(height: 18),
                          Center(
                            child: PadNumericoTv(
                              onDigito: (d) {
                                final campo = _campoActivo();
                                if (campo.text.length >= 8) return;
                                setState(() => campo.text += d);
                              },
                              onBorrar: () {
                                final campo = _campoActivo();
                                if (campo.text.isEmpty) return;
                                setState(() => campo.text = campo.text
                                    .substring(0, campo.text.length - 1));
                              },
                            ),
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
