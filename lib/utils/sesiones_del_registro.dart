/// Parte el registro en las sesiones que lo componen.
///
/// ── Por qué hace falta ──────────────────────────────────────────────────────
///
/// El archivo de registro es acumulativo: cada vez que se abre la app se sigue
/// escribiendo detrás de lo anterior. Eso está bien para guardarlo, y muy mal
/// para leerlo — el visor mostraba todo junto, así que al abrirlo nunca se
/// empezaba desde cero y no había forma de saber dónde terminaba lo de ayer y
/// empezaba lo de recién.
///
/// Reportado en vivo: «veo que ya contiene cosas y nunca comienza desde cero»,
/// y «siempre al cerrar y abrir el app». Que es exactamente el corte que hace
/// falta: **una sesión es una apertura de la app**.
///
/// Con esto, la pantalla en vivo muestra solo la sesión de ahora —empezando
/// por la presentación, como si fuera nueva— y las anteriores quedan detrás de
/// un botón, ordenadas por fecha y hora.
///
/// ── Dónde se corta ──────────────────────────────────────────────────────────
///
/// En la primera línea del recuadro de presentación, que [EncabezadoDeSesion]
/// escribe una sola vez por arranque. No se inventa una marca nueva para esto:
/// esa línea ya existe, ya está en todos los archivos y no puede aparecer en
/// medio de una sesión — ninguna otra cosa de la app escribe ese carácter.
library;

/// Una apertura de la app, con sus líneas.
class SesionDelRegistro {
  const SesionDelRegistro({required this.lineas, this.cuando});

  final List<String> lineas;

  /// Cuándo arrancó, o null si esas líneas no traen ninguna hora legible.
  ///
  /// Puede pasar con el tramo suelto del principio del archivo: si el
  /// recorte por tamaño cortó a mitad de una sesión, lo que queda arriba no
  /// tiene por qué incluir su presentación.
  final DateTime? cuando;

  int get cuantasLineas => lineas.length;
}

/// El carácter con el que abre el recuadro de la presentación.
///
/// Se compara por el borde superior izquierdo y no por la línea entera: si
/// mañana el recuadro cambia de ancho, el corte sigue funcionando.
const _marcaDeArranque = '╔══';

/// La hora que escribe `logging` en cada línea: `2026-08-29 21:45:03.123456`.
final _horaDeLinea = RegExp(r'(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})');

/// Separa las líneas en sesiones, de la más vieja a la más nueva.
///
/// El tramo anterior a la primera marca —si lo hay— entra igual como una
/// sesión más: son líneas reales que pasaron, y tirarlas por no saber dónde
/// empezaron sería perder registro. Es justo lo que se está tratando de
/// evitar.
List<SesionDelRegistro> partirEnSesiones(List<String> lineas) {
  if (lineas.isEmpty) return const [];
  final cortes = <int>[];
  for (var i = 0; i < lineas.length; i++) {
    if (lineas[i].contains(_marcaDeArranque)) cortes.add(i);
  }
  if (cortes.isEmpty) {
    return [SesionDelRegistro(lineas: lineas, cuando: _primeraHora(lineas))];
  }

  final salida = <SesionDelRegistro>[];
  if (cortes.first > 0) {
    final sueltas = lineas.sublist(0, cortes.first);
    salida.add(
      SesionDelRegistro(lineas: sueltas, cuando: _primeraHora(sueltas)),
    );
  }
  for (var i = 0; i < cortes.length; i++) {
    final desde = cortes[i];
    final hasta = i + 1 < cortes.length ? cortes[i + 1] : lineas.length;
    final tramo = lineas.sublist(desde, hasta);
    salida.add(SesionDelRegistro(lineas: tramo, cuando: _primeraHora(tramo)));
  }
  return salida;
}

/// La primera hora que aparezca en el tramo.
///
/// La presentación no lleva hora —es un recuadro dibujado— así que se busca en
/// las líneas siguientes, que son las que la traen adelante.
DateTime? _primeraHora(List<String> lineas) {
  for (final l in lineas) {
    final m = _horaDeLinea.firstMatch(l);
    if (m == null) continue;
    final cuando = DateTime.tryParse(m.group(1)!);
    if (cuando != null) return cuando;
  }
  return null;
}
