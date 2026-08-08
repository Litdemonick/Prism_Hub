import 'package:flutter/material.dart';
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

    return Padding(
      padding: EdgeInsets.fromLTRB(
        _abierto || widget.alVolver != null ? 4 : 16,
        MediaQuery.paddingOf(context).top + 4,
        4,
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

/// La franja, pero que se va al bajar y vuelve al llegar arriba.
///
/// ── Por qué no alcanzaba con que fuera fina ─────────────────────────────
///
/// Se le sacó la AppBar y quedó en la mitad de alto, pero seguía CLAVADA:
/// acostado, esa franja se lleva una fila de portadas para siempre, y ahí el
/// alto es lo único que escasea.
///
/// En el Inicio esto no pasa porque el nombre de la app es un elemento más de
/// la lista: se desplaza con las portadas y al bajar desaparece. Buscar,
/// Extensiones e Historial no lo pueden copiar tal cual —una de ellas dibuja
/// sus páginas en un deslizador horizontal, y meter el buscador adentro serían
/// tres campos de texto vivos a la vez peleándose el foco— así que se hace por
/// afuera: se escucha el desplazamiento y la franja se recoge.
///
/// ── Vuelve arriba, no al primer tirón para arriba ───────────────────────
///
/// A propósito. Volviendo con cualquier movimiento hacia arriba, la franja
/// aparece y desaparece sola mientras uno busca algo en el medio de la lista, y
/// eso se lee como un parpadeo. Volviendo solo al llegar al principio se ve
/// exactamente como en el Inicio: se fue con el contenido y está de vuelta
/// cuando el contenido está de vuelta.
class FranjaQueSeVa extends StatefulWidget {
  const FranjaQueSeVa({
    super.key,
    required this.franja,
    required this.constructor,
    this.altoExtra = 0,
  });

  final Widget franja;

  /// Lo que mide [franja] de más allá de la franja en sí.
  ///
  /// Buscar cuelga su barrita de progreso debajo del título para que se vaya
  /// con él —si se quedara sola arriba, flotaría sin nada a qué pertenecer— y
  /// eso son unos puntos más de alto que el contenido tiene que descontar.
  final double altoExtra;

  /// El contenido que se desplaza.
  ///
  /// Recibe cuánto mide la franja: ese valor va como relleno ARRIBA de su área
  /// desplazable, para que el primer elemento arranque debajo de la franja y no
  /// tapado por ella. Es un contrato explícito y no una cuenta escondida
  /// justamente para que cada zona lo sume donde corresponde —cada una arma su
  /// lista distinto— en vez de adivinarlo desde acá.
  final Widget Function(double arriba) constructor;

  @override
  State<FranjaQueSeVa> createState() => _FranjaQueSeVaState();
}

class _FranjaQueSeVaState extends State<FranjaQueSeVa>
    with SingleTickerProviderStateMixin {
  late final AnimationController _control = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    value: 0,
  );

  @override
  void dispose() {
    _control.dispose();
    super.dispose();
  }

  bool _mirar(ScrollNotification aviso) {
    // Solo el desplazamiento vertical. El deslizador de páginas de Extensiones
    // es horizontal y también avisa: sin este filtro, cambiar de página
    // escondía la franja.
    if (aviso.metrics.axis != Axis.vertical) return false;

    if (aviso is ScrollUpdateNotification) {
      // Vuelve al llegar arriba y no al primer tirón hacia arriba, a propósito.
      // Volviendo con cualquier movimiento, la franja aparece y desaparece sola
      // mientras uno busca algo en el medio de la lista, y eso se lee como un
      // parpadeo. Volviendo solo al principio se ve como en el Inicio: se fue
      // con el contenido y está de vuelta cuando el contenido está de vuelta.
      if (aviso.metrics.pixels <= 0) {
        _control.reverse();
      } else if ((aviso.scrollDelta ?? 0) > 0) {
        _control.forward();
      }
    }
    // false: el aviso sigue subiendo. Cortarlo rompería a cualquier otro que
    // esté escuchando más arriba —el refresco, por ejemplo—.
    return false;
  }

  @override
  Widget build(BuildContext context) {
    // Lo que mide la franja entera, barra de estado incluida. Sale de los
    // mismos números que usa FranjaDeZona para su relleno.
    final alto = MediaQuery.paddingOf(context).top +
        8 +
        FranjaDeZona.alto +
        widget.altoExtra;

    return Stack(
      children: [
        // ── El contenido ocupa la pantalla ENTERA ─────────────────────────
        //
        // Y la franja va encima, no arriba en una columna. Esto es un arreglo
        // de algo que se sentía muy mal: puesta en una columna, esconderla
        // cambiaba el ALTO del área desplazable, y el contenido de adentro está
        // anclado a su posición de desplazamiento, no a la pantalla. O sea que
        // mientras el dedo arrastraba hacia arriba, la lista pegaba además un
        // salto de cuarenta y pico de puntos hacia arriba por su cuenta. Dos
        // movimientos a la vez para un solo gesto.
        //
        // Flotando encima, el área desplazable mide siempre lo mismo y el
        // contenido solo hace lo que el dedo le pide. Lo que se gana es real
        // igual: el contenido pasa POR DEBAJO de la franja, así que al
        // esconderse aparece lo que había detrás.
        Positioned.fill(
          child: NotificationListener<ScrollNotification>(
            onNotification: _mirar,
            child: widget.constructor(alto),
          ),
        ),
        // La franja se corre hacia arriba hasta salir. Sin ClipRect ni cambio
        // de tamaño: solo se mueve, y moverse no obliga a nadie a rehacer su
        // distribución.
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: AnimatedBuilder(
            animation: _control,
            child: widget.franja,
            builder: (context, franja) => Transform.translate(
              offset: Offset(
                  0,
                  -alto *
                      Curves.easeOutCubic.transform(
                        _control.value,
                      )),
              child: franja,
            ),
          ),
        ),
      ],
    );
  }
}

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
