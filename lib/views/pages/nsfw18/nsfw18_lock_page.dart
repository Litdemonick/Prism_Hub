import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/nsfw18_biometric.dart';
import 'package:prismhub/utils/nsfw18_zone.dart';
import 'package:prismhub/views/widgets/button.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/utils/platform_tv.dart';
import 'package:prismhub/views/widgets/tv/focusable_card.dart';
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
  /// ── Por qué es distinto en TV ─────────────────────────────────────────
  ///
  /// Fuera de TV, al configurar el PIN se llena el primer campo y, cuando ya
  /// tiene algo, se pasa solo al de confirmación — ahí el teclado del
  /// sistema hace obvio en cuál se está escribiendo (el cursor parpadea
  /// donde se tocó), así que adivinar el orden alcanza.
  ///
  /// En TV no hay cursor que mirar: los dos campos son tarjetas que se
  /// recorren con el mando, y el usuario tiene que poder PARARSE en
  /// cualquiera de las dos y ver claramente cuál está eligiendo — no que la
  /// app decida sola y en silencio. Pedido explícito: «poder seleccionar el
  /// campo donde se va a escribir». `_campoTvSeleccionado` guarda cuál es,
  /// y las tarjetas de cada campo (`_CampoPinTv`) lo cambian al tocarlas.
  bool _campoTvSeleccionado = false; // false = PIN, true = confirmación
  TextEditingController _campoActivo() {
    if (!_isSetup) return _pinController;
    if (PlatformTv.esTelevisionSync) {
      return _campoTvSeleccionado ? _confirmController : _pinController;
    }
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

    // ── TV: una pantalla propia, horizontal ─────────────────────────────
    //
    // El diseño de abajo (Column angosta, campos apilados, botón ancho al
    // final) es el pensado para tocar con el dedo — en un televisor esa
    // misma disposición obliga a bajar con el mando para llegar a cada
    // cosa, y el botón de volver quedaba con el tamaño chico de fábrica de
    // un AppBar. Reportado en vivo con foto: «tosco», «no se puede dar a
    // los botones ni escribir en el campo», «botón de volver más grande».
    //
    // Ver `_buildTv` para el porqué de cada decisión puntual.
    if (PlatformTv.esTelevisionSync) return _buildTv(context);

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
                            style: TextStyle(color: HomeTheme.textPrimary),
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

  /// La pantalla del PIN en televisor: teclado a la izquierda, campos y
  /// confirmación a la derecha, todo a la vista sin desplazar nada.
  ///
  /// ── Por qué a lo ancho y no apilado ──────────────────────────────────
  ///
  /// Un televisor sobra ancho y falta paciencia para bajar con el mando.
  /// Con el teclado y los campos lado a lado se ve todo de una, y el orden
  /// natural para recorrer con las flechas es el mismo que el visual:
  /// izquierda para escribir, derecha para ver qué se escribió y confirmar.
  /// Pedido explícito, con foto de referencia del diseño actual (uno debajo
  /// del otro, campos angostos, botón "Establecer PIN" abajo de todo):
  /// «debe ser horizontal, botones a la izquierda y selección a la
  /// derecha».
  Widget _buildTv(BuildContext context) {
    return Scaffold(
      backgroundColor: HomeTheme.bg,
      body: SafeArea(
        child: Padding(
          padding: HomeTheme.margenTv(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // ── Más grande que el de Ajustes ────────────────────
                  //
                  // El de Ajustes (44px) es para una barra con más cosas
                  // al lado. Acá es lo único arriba de todo, así que puede
                  // —y con un mando, debe— ser más fácil de acertar.
                  // Pedido explícito: «botón de volver más grande, como
                  // las demás zonas que tenemos».
                  _BotonVolverTv(
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 18),
                  Text(
                    'nsfw18.title'.i18n,
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: HomeTheme.textPrimary,
                    ),
                  ),
                ],
              ),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 980),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        PadNumericoTv(
                          accent: HomeTheme.accentRed,
                          onDigito: (d) {
                            final campo = _campoActivo();
                            if (campo.text.length >= 8) return;
                            setState(() => campo.text += d);
                          },
                          onBorrar: () {
                            final campo = _campoActivo();
                            if (campo.text.isEmpty) return;
                            setState(() => campo.text =
                                campo.text.substring(0, campo.text.length - 1));
                          },
                        ),
                        const SizedBox(width: 56),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.lock_outline,
                                color: HomeTheme.accentRed,
                                size: 34,
                              ),
                              const SizedBox(height: 14),
                              Text(
                                _isSetup
                                    ? 'nsfw18.setup-title'.i18n
                                    : 'nsfw18.enter-title'.i18n,
                                style: TextStyle(
                                  color: HomeTheme.textPrimary,
                                  fontSize: 21,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _isSetup
                                    ? 'nsfw18.setup-subtitle'.i18n
                                    : 'nsfw18.enter-subtitle'.i18n,
                                style: TextStyle(
                                  color: HomeTheme.textMuted,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 26),
                              CampoPinTv(
                                label: 'nsfw18.pin-label'.i18n,
                                controller: _pinController,
                                // Sin confirmación (desbloqueo de siempre)
                                // este es el único campo: siempre
                                // "seleccionado" a los ojos del usuario,
                                // no hace falta que sea tocable para
                                // elegirlo.
                                seleccionado:
                                    !_isSetup || !_campoTvSeleccionado,
                                onTap: !_isSetup
                                    ? null
                                    : () => setState(
                                        () => _campoTvSeleccionado = false),
                              ),
                              if (_isSetup) ...[
                                const SizedBox(height: 12),
                                CampoPinTv(
                                  label: 'nsfw18.pin-confirm-label'.i18n,
                                  controller: _confirmController,
                                  seleccionado: _campoTvSeleccionado,
                                  onTap: () => setState(
                                      () => _campoTvSeleccionado = true),
                                ),
                              ],
                              if (_error != null) ...[
                                const SizedBox(height: 14),
                                Text(
                                  _error!,
                                  style: const TextStyle(
                                    color: Colors.redAccent,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 24),
                              SizedBox(
                                width: double.infinity,
                                child: PlatformFilledButton(
                                  onPressed: _submitting ? null : _submit,
                                  child: Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 6),
                                    child: Text(
                                      _isSetup
                                          ? 'nsfw18.setup-confirm'.i18n
                                          : 'nsfw18.unlock'.i18n,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// El botón de volver, grande, para pantallas de TV que no llevan barra
/// superior propia (esta es la única cosa arriba de todo).
class _BotonVolverTv extends StatelessWidget {
  const _BotonVolverTv({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FocusableCard(
      borderRadius: 999,
      accent: HomeTheme.accentRed,
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: HomeTheme.cardSurface,
          shape: BoxShape.circle,
          border: Border.all(color: HomeTheme.border),
        ),
        child: Icon(
          Icons.arrow_back_rounded,
          size: 26,
          color: HomeTheme.textPrimary,
        ),
      ),
    );
  }
}

/// Un campo de PIN, en TV: no es un `TextField` —nada que tipear con
/// teclado del sistema, se escribe con el `PadNumericoTv` de al lado—, es
/// una tarjeta que muestra cuánto se lleva escrito y se puede elegir con el
/// mando para que el pad le escriba a ESTA en vez de a la otra.
///
/// ── Por qué puntos y no el número ────────────────────────────────────
///
/// Mismo criterio que `obscureText` en el campo de siempre: es un PIN,
/// nunca se muestra en claro aunque esté mirando la pantalla desde el
/// sillón con más gente alrededor.
///
/// Público (no `_CampoPinTv`): lo comparte con el diálogo de "Cambiar PIN"
/// de Ajustes (`nsfw18_pin_settings_tile.dart`), que tenía el mismo
/// problema por su lado — ver el comentario largo ahí.
class CampoPinTv extends StatelessWidget {
  const CampoPinTv({
    super.key,
    required this.label,
    required this.controller,
    required this.seleccionado,
    required this.onTap,
  });

  final String label;
  final TextEditingController controller;

  /// Si el pad numérico le escribe a este campo ahora mismo.
  final bool seleccionado;

  /// Null cuando este es el único campo que hay (desbloqueo de siempre):
  /// no tiene sentido "elegirlo" si no hay otro.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final puntos = '•' * controller.text.length;
        final contenido = AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: HomeTheme.cardSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: seleccionado ? HomeTheme.accentRed : HomeTheme.border,
              width: seleccionado ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: HomeTheme.textMuted,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      puntos.isEmpty ? '—' : puntos,
                      style: TextStyle(
                        color: HomeTheme.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 4,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${controller.text.length}/8',
                style: TextStyle(color: HomeTheme.textMuted, fontSize: 12),
              ),
            ],
          ),
        );
        if (onTap == null) return contenido;
        return FocusableCard(
          borderRadius: 12,
          accent: HomeTheme.accentRed,
          onTap: onTap!,
          child: contenido,
        );
      },
    );
  }
}
