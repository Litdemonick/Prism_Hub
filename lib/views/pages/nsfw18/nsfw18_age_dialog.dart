import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/platform_tv.dart';
import 'package:prismhub/utils/prismhub_storage.dart';
import 'package:prismhub/views/widgets/button.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/messenger.dart';

/// Confirmación de mayoría de edad al ACTIVAR el contenido +18. Una sola vez:
/// una vez declarada, no se vuelve a preguntar.
///
/// Se pide la fecha de nacimiento y no un "¿sos mayor?" con Sí/No. Ninguna de
/// las dos verifica nada de verdad —el mismo dispositivo pregunta y responde—
/// pero una fecha cuesta más de responder a la ligera que un botón, y deja
/// constancia con día y hora de lo que el usuario declaró. Eso es lo que se
/// mira si alguna vez hay que demostrar diligencia.
///
/// Verificación real necesitaría un proveedor externo con documento, servidor y
/// manejo de datos personales sensibles. Y esa obligación, hoy, recae sobre
/// quien aloja el contenido, no sobre un cliente local.
class Nsfw18AgeDialog {
  Nsfw18AgeDialog._();

  static const int _edadMinima = 18;

  /// true si ya declaró la edad antes.
  static bool get yaDeclarada {
    final v = PrismHubStorage.getSetting(SettingKey.adultDeclaredAt);
    return v is String && v.isNotEmpty;
  }

  /// Devuelve true si puede activarse el contenido +18.
  static Future<bool> confirmar(BuildContext context) async {
    if (yaDeclarada) return true;

    final hoy = DateTime.now();
    // ── En televisor, un selector propio ─────────────────────────────────
    //
    // `showDatePicker` es de Material y está pensado para dedo o mouse: la
    // grilla de días y la lista de años se recorren tocando una celda
    // puntual, algo que un control remoto no puede hacer —hay que llegar
    // saltando de casilla en casilla— y además el diálogo tiene un tamaño
    // pensado para un teléfono, así que en una pantalla de televisor con
    // margen de overscan quedaba cortado. Reportado en vivo.
    //
    // El de TV pide lo mismo (día, mes y año, ver el porqué en el doc de
    // esta clase) pero con el patrón que sí funciona con un mando: tres
    // campos que suben y bajan con ▲▼ y se cambian con ◀▶.
    final DateTime? elegida;
    if (PlatformTv.esTelevisionSync) {
      elegida = await Navigator.of(context).push<DateTime>(
        MaterialPageRoute(builder: (_) => _SelectorDeFechaTv(hoy: hoy)),
      );
    } else {
      elegida = await showDatePicker(
        context: context,
        helpText: 'nsfw18.age-help'.i18n,
        // Se abre en un año plausible para un adulto en vez de en hoy: partir
        // de la fecha actual obliga a retroceder décadas con el selector.
        initialDate: DateTime(hoy.year - 25, hoy.month, hoy.day),
        firstDate: DateTime(hoy.year - 100),
        lastDate: hoy,
        initialDatePickerMode: DatePickerMode.year,
        builder: (context, child) => Theme(
          data: ThemeData.dark(useMaterial3: true).copyWith(
            colorScheme: ColorScheme.fromSeed(
              seedColor: HomeTheme.accentRed,
              brightness: Brightness.dark,
            ),
          ),
          child: child!,
        ),
      );
    }

    if (elegida == null) return false;

    final edad = _edad(elegida, hoy);
    if (edad < _edadMinima) {
      if (context.mounted) {
        await showPlatformDialog(
          context: context,
          title: 'nsfw18.age-denied-title'.i18n,
          content: Text(
            'nsfw18.age-denied'.i18n,
            style: TextStyle(color: HomeTheme.textMuted, height: 1.45),
          ),
          actions: [
            Builder(
              builder: (ctx) => PlatformFilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text('common.confirm'.i18n),
              ),
            ),
          ],
        );
      }
      return false;
    }

    // Se guarda CUÁNDO lo declaró, no la fecha de nacimiento: para el app
    // alcanza con saber que declaró ser mayor y cuándo. Guardar la fecha de
    // nacimiento sería conservar un dato personal que no hace falta para nada.
    await PrismHubStorage.setSetting(
      SettingKey.adultDeclaredAt,
      DateTime.now().toIso8601String(),
    );
    return true;
  }

  static int _edad(DateTime nacimiento, DateTime hoy) {
    var edad = hoy.year - nacimiento.year;
    final cumplioEsteAno = (hoy.month > nacimiento.month) ||
        (hoy.month == nacimiento.month && hoy.day >= nacimiento.day);
    if (!cumplioEsteAno) edad--;
    return edad;
  }
}

/// El selector de fecha de nacimiento, para televisor.
///
/// ── Por qué no es el de Material ─────────────────────────────────────────
///
/// Ver el comentario en `Nsfw18AgeDialog.confirmar`: `showDatePicker` se
/// recorre tocando una celda puntual —imposible con un mando— y su diálogo
/// se cortaba en una pantalla de televisor.
///
/// ── El patrón que sí funciona con un control remoto ─────────────────────
///
/// Tres campos (día, mes, año) que suben y bajan con ▲▼ y entre los que se
/// pasa con ◀▶ — el mismo mecanismo con el que se pone la hora en cualquier
/// decodificador, y el que ya usa el reproductor de TV de esta app para sus
/// opciones. Un solo `Focus` maneja todo: no hay foco que perseguir entre
/// treinta celdas, así que no puede quedarse en la nada (el problema
/// clásico de esta app con el mando, ver `RescateDeFoco`).
///
/// Pantalla completa y no un diálogo: con el margen de overscan de un
/// televisor, un diálogo chico con tres campos y sus ayudas quedaba
/// apretado contra los bordes.
class _SelectorDeFechaTv extends StatefulWidget {
  const _SelectorDeFechaTv({required this.hoy});

  final DateTime hoy;

  @override
  State<_SelectorDeFechaTv> createState() => _SelectorDeFechaTvState();
}

class _SelectorDeFechaTvState extends State<_SelectorDeFechaTv> {
  late int _dia = widget.hoy.day;
  late int _mes = widget.hoy.month;

  /// Arranca 25 años atrás, igual que el selector de Material: partir del
  /// año actual obliga a bajar décadas de a una.
  late int _ano = widget.hoy.year - 25;

  /// Qué campo se está cambiando: 0 día, 1 mes, 2 año.
  int _campo = 0;

  final _foco = FocusNode(debugLabel: 'fecha-nacimiento-tv');

  @override
  void dispose() {
    _foco.dispose();
    super.dispose();
  }

  int get _anoMinimo => widget.hoy.year - 100;

  /// Cuántos días tiene el mes elegido — sin esto se podía declarar un 31
  /// de febrero. El día 0 del mes siguiente ES el último del actual.
  int get _diasDelMes => DateTime(_ano, _mes + 1, 0).day;

  void _cambiar(int delta) {
    setState(() {
      switch (_campo) {
        case 0:
          // Vuelta completa: subir desde el último día lleva al primero, en
          // vez de quedarse trabado en el borde.
          final total = _diasDelMes;
          _dia = ((_dia - 1 + delta) % total + total) % total + 1;
        case 1:
          _mes = ((_mes - 1 + delta) % 12 + 12) % 12 + 1;
          // Cambiar de mes puede dejar un día que no existe (31 → febrero).
          if (_dia > _diasDelMes) _dia = _diasDelMes;
        default:
          final total = widget.hoy.year - _anoMinimo + 1;
          final base = _ano - _anoMinimo;
          _ano = _anoMinimo + ((base + delta) % total + total) % total;
          if (_dia > _diasDelMes) _dia = _diasDelMes;
      }
    });
  }

  KeyEventResult _tecla(FocusNode node, KeyEvent evento) {
    if (evento is! KeyDownEvent) return KeyEventResult.ignored;
    final tecla = evento.logicalKey;
    if (tecla == LogicalKeyboardKey.arrowUp) {
      _cambiar(1);
      return KeyEventResult.handled;
    }
    if (tecla == LogicalKeyboardKey.arrowDown) {
      _cambiar(-1);
      return KeyEventResult.handled;
    }
    if (tecla == LogicalKeyboardKey.arrowLeft) {
      setState(() => _campo = (_campo + 2) % 3);
      return KeyEventResult.handled;
    }
    if (tecla == LogicalKeyboardKey.arrowRight) {
      setState(() => _campo = (_campo + 1) % 3);
      return KeyEventResult.handled;
    }
    if (tecla == LogicalKeyboardKey.select ||
        tecla == LogicalKeyboardKey.enter ||
        tecla == LogicalKeyboardKey.numpadEnter) {
      // Una fecha futura no es una fecha de nacimiento — se corta acá en vez
      // de dejar que la cuenta de edad dé un número negativo.
      final elegida = DateTime(_ano, _mes, _dia);
      Navigator.of(context).pop(
        elegida.isAfter(widget.hoy) ? null : elegida,
      );
      return KeyEventResult.handled;
    }
    if (tecla == LogicalKeyboardKey.escape ||
        tecla == LogicalKeyboardKey.goBack) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HomeTheme.bg,
      body: Focus(
        focusNode: _foco,
        autofocus: true,
        onKeyEvent: _tecla,
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(HomeTheme.overscanTv(context)),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cake_rounded,
                      size: 44, color: HomeTheme.accentRed),
                  const SizedBox(height: 20),
                  Text(
                    'nsfw18.age-help'.i18n,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 34),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _campoFecha(
                        valor: _dia.toString().padLeft(2, '0'),
                        etiqueta: 'nsfw18.age-dia'.i18n,
                        activo: _campo == 0,
                      ),
                      const SizedBox(width: 16),
                      _campoFecha(
                        valor: _mes.toString().padLeft(2, '0'),
                        etiqueta: 'nsfw18.age-mes'.i18n,
                        activo: _campo == 1,
                      ),
                      const SizedBox(width: 16),
                      _campoFecha(
                        valor: _ano.toString(),
                        etiqueta: 'nsfw18.age-ano'.i18n,
                        activo: _campo == 2,
                        ancho: 150,
                      ),
                    ],
                  ),
                  const SizedBox(height: 34),
                  // Las ayudas de teclas, mismo criterio que el reproductor
                  // de TV: con un mando no hay nada que descubrir tocando,
                  // si no está escrito no se sabe.
                  Wrap(
                    spacing: 26,
                    runSpacing: 10,
                    alignment: WrapAlignment.center,
                    children: [
                      _ayuda('▲ ▼', 'nsfw18.age-cambiar'.i18n),
                      _ayuda('◀ ▶', 'nsfw18.age-mover'.i18n),
                      _ayuda('OK', 'common.confirm'.i18n),
                      _ayuda('EXIT', 'common.cancel'.i18n),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _campoFecha({
    required String valor,
    required String etiqueta,
    required bool activo,
    double ancho = 110,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Las flechitas solo sobre el campo activo: dicen dónde va a pasar
        // algo si se aprieta arriba o abajo.
        Icon(
          Icons.keyboard_arrow_up_rounded,
          size: 26,
          color: activo ? HomeTheme.accentRed : Colors.transparent,
        ),
        AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: ancho,
          padding: const EdgeInsets.symmetric(vertical: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: activo
                ? HomeTheme.accentRed.withValues(alpha: 0.18)
                : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: activo ? HomeTheme.accentRed : Colors.transparent,
              width: 2.5,
            ),
          ),
          child: Text(
            valor,
            style: const TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
        Icon(
          Icons.keyboard_arrow_down_rounded,
          size: 26,
          color: activo ? HomeTheme.accentRed : Colors.transparent,
        ),
        const SizedBox(height: 4),
        Text(
          etiqueta,
          style: TextStyle(fontSize: 14, color: HomeTheme.textMuted),
        ),
      ],
    );
  }

  Widget _ayuda(String tecla, String que) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              tecla,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(que, style: TextStyle(color: HomeTheme.textMuted, fontSize: 14)),
        ],
      );
}
