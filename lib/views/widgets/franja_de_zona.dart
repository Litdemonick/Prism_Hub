import 'package:flutter/material.dart';
import 'package:prismhub/utils/platform_tv.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';

/// La franja fina con el nombre de la zona, arriba de todo.
///
/// ── Por qué no es una AppBar ────────────────────────────────────────────
///
/// Una AppBar de Material mide 56 y dibuja su propia superficie con elevación.
/// Sobre el fondo con brillo de la app eso queda como una costura gris cruzando
/// la pantalla, y encima se lleva una franja fija que en un teléfono acostado
/// —donde el alto es lo único que escasea— es media fila de portadas.
///
/// El Inicio y la Biblioteca nunca la usaron: ahí el título es texto suelto en
/// una franja fina, y el contenido pasa justo por debajo y se recorta ahí. Se
/// ve mejor y se ve más. Buscar y Extensiones sí la usaban, y al pasar de una
/// pestaña a la otra se notaba el escalón.
///
/// Esto es esa franja, con lo que las dos necesitan de más: el buscador que se
/// abre en el mismo renglón y los botones de la derecha.
///
/// ── El campo se abre EN la franja ───────────────────────────────────────
///
/// No debajo, ni en una pantalla aparte: reemplaza al título en el mismo sitio.
/// Así la franja mide siempre lo mismo, abierta o cerrada, y nada de abajo se
/// mueve al buscar.
class FranjaDeZona extends StatefulWidget {
  const FranjaDeZona({
    super.key,
    required this.titulo,
    required this.controlador,
    this.acciones,
    this.alEscribir,
    this.alEnviar,
    this.ayuda,
    this.alVolver,
  });

  final String titulo;
  final TextEditingController controlador;

  /// Los botones de la derecha, después de la lupa.
  final List<Widget>? acciones;
  final ValueChanged<String>? alEscribir;
  final ValueChanged<String>? alEnviar;

  /// El texto en gris del campo mientras está vacío.
  final String? ayuda;

  /// La flecha para salir, cuando la zona es una pantalla abierta encima y no
  /// una pestaña. En las pestañas va en null: no hay a dónde volver.
  final VoidCallback? alVolver;

  /// El alto de la franja, sin contar la barra de estado.
  ///
  /// Con nombre porque lo necesita quien calcula cuánto espacio le queda al
  /// contenido. Sale de los botones: un IconButton apretado mide 40, y con 4 de
  /// aire arriba y abajo la franja da 48. El título entra de sobra —21 o 25 de
  /// letra— así que manda el botón.
  static const alto = 48.0;

  @override
  State<FranjaDeZona> createState() => _FranjaDeZonaState();
}

class _FranjaDeZonaState extends State<FranjaDeZona> {
  late bool _abierto = widget.controlador.text.isNotEmpty;

  void _cerrar() {
    setState(() {
      widget.controlador.clear();
      widget.alEnviar?.call('');
      _abierto = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Acostado en un teléfono, 25 de título se come alto que le hace falta al
    // contenido. Mismo criterio y mismo número que el resto de las zonas.
    final bajo = MediaQuery.sizeOf(context).height < 520;
    // En televisor, el margen de overscan a los costados — esta franja no
    // lo tenía, así que la flecha de volver, el título y los botones de la
    // derecha quedaban pegados a un borde que en un televisor viejo puede
    // estar recortado. En teléfono/escritorio da exactamente los mismos 4 y
    // 16 de siempre (por eso se sigue sumando ahí, no reemplazando).
    final esTv = PlatformTv.esTelevisionSync;
    final overscan = esTv ? HomeTheme.overscanTv(context) : 0.0;
    final izquierda =
        (_abierto || widget.alVolver != null ? 4.0 : 16.0) + overscan;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        izquierda,
        MediaQuery.paddingOf(context).top + 4,
        4 + overscan,
        4,
      ),
      child: SizedBox(
        height: FranjaDeZona.alto,
        child: Row(
          children: [
            if (_abierto)
              _boton(
                Icons.arrow_back,
                _cerrar,
                ayuda: MaterialLocalizations.of(context).backButtonTooltip,
              )
            else if (widget.alVolver != null)
              _boton(
                Icons.arrow_back,
                widget.alVolver!,
                ayuda: MaterialLocalizations.of(context).backButtonTooltip,
              ),
            Expanded(
              child: _abierto
                  ? PopScope(
                      // El atrás del sistema cierra el buscador antes que la
                      // pantalla: si cerrara la pantalla, abrir el campo sin
                      // querer te sacaría de la zona.
                      canPop: false,
                      onPopInvokedWithResult: (_, __) {
                        if (_abierto) _cerrar();
                      },
                      child: TextField(
                        controller: widget.controlador,
                        autofocus: true,
                        style: const TextStyle(fontSize: 17),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: widget.ayuda ?? widget.titulo,
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onChanged: widget.alEscribir,
                        onSubmitted: widget.alEnviar,
                      ),
                    )
                  : Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        widget.titulo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        // El mismo título que Inicio y Biblioteca, desde un
                        // solo lugar.
                        style: HomeTheme.tituloDeZona(bajo: bajo),
                      ),
                    ),
            ),
            _boton(
              _abierto ? Icons.close : Icons.search,
              () {
                if (_abierto) {
                  // Con texto escrito, la cruz limpia; vacío, cierra. Antes
                  // solo limpiaba, así que con el campo vacío el botón no
                  // hacía nada y había que usar el atrás.
                  if (widget.controlador.text.isNotEmpty) {
                    setState(() {
                      widget.controlador.clear();
                      widget.alEnviar?.call('');
                    });
                    return;
                  }
                  _cerrar();
                  return;
                }
                setState(() => _abierto = true);
              },
            ),
            ...?widget.acciones,
          ],
        ),
      ),
    );
  }

  /// Un botón de la franja.
  ///
  /// Apretado a 40 y no a los 48 de siempre: son los que mandan el alto de la
  /// franja, y a 48 la franja mide 56 — o sea, exactamente lo que se quería
  /// sacar. Cuarenta sigue estando por encima del mínimo táctil que recomienda
  /// Material para una barra.
  Widget _boton(IconData icono, VoidCallback alTocar, {String? ayuda}) {
    return SizedBox(
      width: 40,
      height: 40,
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: 22,
        tooltip: ayuda,
        onPressed: alTocar,
        icon: Icon(icono),
      ),
    );
  }
}

// ── Y cómo se esconde al desplazar ──────────────────────────────────────
//
// No se esconde sola. Se probó: un envoltorio que escuchaba el desplazamiento y
// recogía la franja. Con la franja en una columna eso cambiaba el ALTO del área
// desplazable, y el contenido está anclado a su posición de desplazamiento, no
// a la pantalla: mientras el dedo arrastraba, la lista pegaba además un salto
// por su cuenta. Flotando encima se arreglaba el salto, pero la franja
// apareciendo y desapareciendo sola se seguía sintiendo rara.
//
// Lo que hace el Inicio es más simple y es lo que se copia: el título es UN
// ELEMENTO MÁS de la lista. Se desplaza con las portadas, al bajar se va, al
// subir vuelve, y no hay ninguna animación ni ningún oyente de por medio —
// porque no está pasando nada raro, solo se está desplazando la lista.
//
// Así que cada zona mete la franja como primer elemento de SU área desplazable.
// La única que no puede es Extensiones, que dibuja sus páginas en un deslizador
// horizontal: meter el buscador adentro serían tres campos de texto vivos a la
// vez peleándose el foco. Ahí la franja se queda fija arriba, que es lo que
// hacía antes de todo esto.

/// Un botón para las [FranjaDeZona.acciones], del tamaño de la franja.
///
/// Con nombre para que las zonas no tengan que acordarse del 40: un IconButton
/// suelto viene a 48 y estira la franja justo lo que se quería sacar.
class AccionDeFranja extends StatelessWidget {
  const AccionDeFranja({
    super.key,
    required this.icono,
    required this.alTocar,
    this.ayuda,
  });

  final Widget icono;
  final VoidCallback? alTocar;
  final String? ayuda;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: 22,
        tooltip: ayuda,
        onPressed: alTocar,
        icon: icono,
      ),
    );
  }
}
