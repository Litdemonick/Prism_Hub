import 'package:flutter/material.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/platform_tv.dart';
import 'package:prismhub/utils/prismhub_mas.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/tv/focusable_card.dart';
import 'package:prismhub/views/widgets/tv/region_de_foco.dart';

// ─── El teclado en pantalla de TV ───────────────────────────────────────
//
// En un televisor no hay teclado. El de Android sale solo al enfocar un
// campo de texto, pero ocupa media pantalla y tapa justo los resultados —
// que es lo único que importa mirar mientras se escribe.
//
// Así que el teclado es PARTE de la pantalla: se escribe una letra y se ve
// al instante qué apareció, sin tapar nada ni abrir y cerrar nada.
//
// Vive acá y no dentro de una pantalla porque lo usan varias: el buscador
// general y el de cada extensión, que tienen resultados distintos pero la
// misma forma de escribir.

/// Las teclas, en filas. Con acentos y Ñ porque el catálogo está en
/// español: sin ellos, buscar "Pokémon" obliga a escribir mal a propósito.
const _filasLetras = <List<String>>[
  ['A', 'Á', 'B', 'C', 'D', 'E', 'É'],
  ['F', 'G', 'H', 'I', 'Í', 'J', 'K'],
  ['L', 'M', 'N', 'Ñ', 'O', 'Ó', 'P'],
  ['Q', 'R', 'S', 'T', 'U', 'Ú', 'Ü'],
  ['V', 'W', 'X', 'Y', 'Z'],
];

const _filasNumeros = <List<String>>[
  ['1', '2', '3', '4', '5'],
  ['6', '7', '8', '9', '0'],
  ['-', ':', '!', '?', '.'],
];

/// El lado de una tecla y el hueco entre teclas. Están acá arriba porque de
/// ellos sale también el ancho del espacio, y dos números sueltos que tienen
/// que coincidir es como se termina con un teclado desalineado.
const _anchoTecla = 44.0;
const _hueco = 8.0;

class TecladoTv extends StatefulWidget {
  const TecladoTv({
    super.key,
    required this.texto,
    required this.onCambio,
    this.accent,
    this.ancho = 380,
    this.mostrarCampo = true,
    this.alturaDisponible,
  });

  /// Cuánto alto tiene de verdad para acomodarse, si quien lo usa lo sabe.
  ///
  /// ── Por qué no alcanza con medirlo acá adentro ────────────────────────
  ///
  /// Un `LayoutBuilder` puesto en el propio `build` serviría si el teclado
  /// colgara de algo con alto acotado — pero la pantalla del buscador lo
  /// pone dentro de un `SingleChildScrollView` (para no perder teclas en un
  /// televisor de poca altura útil), y ESE widget le da a su hijo alto SIN
  /// LÍMITE a propósito: así es como puede desplazarse. Puertas adentro,
  /// el teclado nunca ve un tope real por más que pregunte.
  ///
  /// Por eso lo mide quien arma la pantalla, ANTES de entrar al scroll —
  /// ahí el alto disponible es el de verdad— y se lo pasa. Null (el valor
  /// de siempre) deja el teclado a tamaño completo, como hasta ahora.
  final double? alturaDisponible;

  /// Si dibuja arriba su propio cartel con lo escrito.
  ///
  /// En falso cuando la pantalla YA muestra el texto en otro lado (la barra
  /// de arriba del buscador de una extensión): dos carteles con lo mismo,
  /// uno al lado del otro, se leen como que hay dos búsquedas distintas.
  final bool mostrarCampo;

  /// Lo escrito hasta ahora. Lo guarda quien use el teclado, no el teclado:
  /// así la pantalla puede arrancar con algo ya escrito (una búsqueda que
  /// venía de antes) sin que el teclado tenga que enterarse.
  final String texto;

  /// Se llama con el texto NUEVO en cada tecla.
  final void Function(String texto) onCambio;

  final Color? accent;
  final double ancho;

  @override
  State<TecladoTv> createState() => _TecladoTvState();
}

class _TecladoTvState extends State<TecladoTv> {
  bool _numeros = false;

  void _escribir(String letra) => widget.onCambio(widget.texto + letra);

  void _borrarUno() {
    if (widget.texto.isEmpty) return;
    widget.onCambio(widget.texto.substring(0, widget.texto.length - 1));
  }

  void _borrarTodo() {
    if (widget.texto.isEmpty) return;
    widget.onCambio('');
  }

  /// Cuánto mide el teclado a tamaño completo, para saber si entra.
  ///
  /// Suma lo mismo que arma `build`: el campo (si va), la fila de
  /// "123"/borrar y las filas de letras/números con sus huecos. No hace
  /// falta que sea exacto al píxel — es para decidir CUÁNTO achicar, y
  /// quedarse un poco corto solo dejaría un margen de sobra.
  double _altoCompleto(List<List<String>> filas) {
    const altoCampo = 50.0 + 14.0; // el cartel + su separación de abajo
    const altoAccion = _anchoTecla + 12.0; // la fila "123"/borrar + separación
    final altoFilas = filas.length * _anchoTecla + (filas.length - 1) * _hueco;
    return (widget.mostrarCampo ? altoCampo : 0.0) + altoAccion + altoFilas;
  }

  @override
  Widget build(BuildContext context) {
    final filas = _numeros ? _filasNumeros : _filasLetras;
    return LayoutBuilder(builder: (context, caja) {
      // ── Se achica para entrar, no se corta ni se desplaza ─────────────
      //
      // El teclado medía siempre lo mismo, sin mirar cuánto alto tenía de
      // verdad disponible. En un televisor con menos alto útil —o con las
      // últimas búsquedas ocupando lugar arriba— eso no entraba entero, y
      // la única salida era desplazarse para llegar a las últimas filas.
      // Pedido explícito: «adaptá el teclado que se vean todos los
      // botones».
      //
      // Con un factor sacado de cuánto sobra o falta, las teclas y los
      // huecos entre ellas se achican lo justo para que TODO el teclado
      // entre de una — nunca por debajo de un 60%, que es donde una tecla
      // deja de poder tocarse con comodidad.
      // Lo que nos pasaron gana: es una medida de verdad, tomada afuera de
      // cualquier scroll. Sin eso, lo que mida ESTE `LayoutBuilder` sirve
      // igual para quien no cuelgue de un scroll.
      final alturaDisponible = widget.alturaDisponible ?? caja.maxHeight;
      final escala = alturaDisponible.isFinite
          ? (alturaDisponible / _altoCompleto(filas)).clamp(0.6, 1.0)
          : 1.0;
      final anchoTecla = _anchoTecla * escala;
      final hueco = _hueco * escala;
      return SizedBox(
        width: widget.ancho,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // El "campo": muestra lo escrito, no se edita. Con el mando no
            // hay cursor que mover, así que un TextField de verdad solo
            // agregaría el teclado del sistema encima del nuestro.
            if (widget.mostrarCampo) ...[
              _CampoDeBusqueda(texto: widget.texto, accent: widget.accent),
              SizedBox(height: 14 * escala),
            ],
            // ── Cada fila, su propia franja fija ─────────────────────────
            //
            // Sin esto el mando la trata como un `Row` cualquiera, sin
            // tope: al llegar al final de una fila —o al querer entrar a
            // ella desde arriba o abajo— Flutter busca el foco más cercano
            // en CUALQUIER parte de la pantalla, campo de búsqueda
            // incluido. Reportado en vivo, con foto: «al navegar a la
            // derecha sube arriba solo, al campo donde se escribe». Con la
            // franja, cada fila se recorre como una unidad y el salto
            // entre filas es siempre el de al lado, nunca uno de otra
            // parte de la pantalla.
            FranjaFijaTv(
              // A la derecha del todo están los resultados, no un final de
              // recorrido — ver `FranjaHorizontalTv.escapaALaDerecha`.
              escapaALaDerecha: true,
              child: Row(
                children: [
                  _tecla(
                    _numeros ? 'ABC' : '123',
                    onTap: () => setState(() => _numeros = !_numeros),
                    ancho: 74 * escala,
                    alto: anchoTecla,
                    escala: escala,
                  ),
                  SizedBox(width: hueco),
                  _teclaIcono(Icons.delete_outline_rounded,
                      onTap: _borrarTodo, alto: anchoTecla, escala: escala),
                  SizedBox(width: hueco),
                  _teclaIcono(Icons.backspace_outlined,
                      onTap: _borrarUno, alto: anchoTecla, escala: escala),
                ],
              ),
            ),
            SizedBox(height: 12 * escala),
            // ── El espacio, al final de la última fila ─────────────────
            //
            // Estuvo de dos maneras antes de esta. Primero como una barra
            // ancha debajo del teclado: con un mando eso obliga a bajar
            // todas las filas cada vez que hace falta un espacio y a
            // volver a subir para la palabra siguiente. Después como una
            // columna alta a la derecha, alcanzable desde cualquier fila
            // con una sola pulsación — eso resolvía el recorrido pero se
            // veía mal, reportado en vivo: una torre pegada al costado de
            // las letras.
            //
            // Acá va donde queda lugar de verdad: la última fila tiene
            // cinco teclas donde las otras tienen siete, así que el
            // espacio ocupa justo el hueco que sobra. El teclado queda
            // rectangular, el espacio queda ancho y fácil de acertar, y
            // desde la fila de arriba se llega con una sola flecha abajo.
            for (final (indice, fila) in filas.indexed) ...[
              if (indice > 0) SizedBox(height: hueco),
              FranjaFijaTv(
                escapaALaDerecha: true,
                child: Row(
                  children: [
                    for (final letra in fila) ...[
                      _tecla(
                        letra,
                        onTap: () => _escribir(letra),
                        ancho: anchoTecla,
                        alto: anchoTecla,
                        escala: escala,
                        // La "A" arranca con el foco puesto — mismo
                        // criterio que el "1" del teclado numérico del
                        // PIN: sin esto, al abrir el buscador el mando no
                        // tenía dónde empezar.
                        autofocus: indice == 0 && letra == fila.first,
                      ),
                      SizedBox(width: hueco),
                    ],
                    if (indice == filas.length - 1)
                      _tecla(
                        ' ',
                        onTap: () => _escribir(' '),
                        ancho: _anchoDelEspacio(fila.length, escala),
                        alto: anchoTecla,
                        escala: escala,
                        etiqueta: '␣',
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      );
    });
  }

  /// Cuánto le queda al espacio en la última fila.
  ///
  /// El ancho del teclado lo fija la fila más larga que puede haber —siete
  /// teclas, las de letras— y no la fila más larga de lo que se está
  /// mostrando. Si no, al pasar a los números (filas de cinco) el teclado
  /// entero se encogería y todo lo de al lado saltaría de sitio.
  static double _anchoDelEspacio(int teclasEnLaFila, double escala) {
    final anchoTecla = _anchoTecla * escala;
    final hueco = _hueco * escala;
    final maximo =
        _filasLetras.map((f) => f.length).reduce((a, b) => a > b ? a : b);
    final total = maximo * anchoTecla + (maximo - 1) * hueco;
    final usado = teclasEnLaFila * _anchoTecla + teclasEnLaFila * _hueco;
    // Nunca más angosto que una tecla y media: si algún día una última fila
    // llegara a llenarse, el espacio tiene que seguir siendo alcanzable.
    final queda = total - usado;
    return queda < _anchoTecla * 1.5 ? _anchoTecla * 1.5 : queda;
  }

  Widget _tecla(
    String letra, {
    required VoidCallback onTap,
    double ancho = _anchoTecla,
    double alto = _anchoTecla,
    double escala = 1.0,
    String? etiqueta,
    bool autofocus = false,
  }) {
    return FocusableCard(
      borderRadius: 8,
      accent: widget.accent,
      autofocus: autofocus,
      onTap: onTap,
      child: Container(
        width: ancho,
        height: alto,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: HomeTheme.cardSurface,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          etiqueta ?? letra,
          style: TextStyle(
            // Nunca por debajo de 12: una letra minúscula da igual, tiene
            // que seguir leyéndose de lejos aunque el teclado se haya
            // achicado para entrar.
            fontSize: (17 * escala).clamp(12.0, 17.0),
            fontWeight: FontWeight.w600,
            color: HomeTheme.textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _teclaIcono(
    IconData icono, {
    required VoidCallback onTap,
    double alto = 44,
    double escala = 1.0,
  }) {
    return FocusableCard(
      borderRadius: 8,
      accent: widget.accent,
      onTap: onTap,
      child: Container(
        width: 52 * escala,
        height: alto,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: HomeTheme.cardSurface,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icono,
            size: (20 * escala).clamp(14.0, 20.0),
            color: HomeTheme.textPrimary),
      ),
    );
  }
}

/// El cuadro donde se ve lo que se va escribiendo.
///
/// ── Por qué tiene animación ────────────────────────────────────
///
/// Era un recuadro gris con un texto gris adentro. Sin nada escrito y sin
/// nada que se mueva, desde el sillón no se distingue de un título apagado:
/// no se lee como «acá va lo que escribas», se lee como decoración. Pedido
/// explícito de que esto se vea como un campo de verdad.
///
/// Vacío, muestra la invitación con un cursor que parpadea —la señal
/// universal de «escribí acá»— y el borde apagado. Con algo escrito, el
/// cursor sigue al texto y el borde se enciende con el color de acento, así
/// que de un vistazo se sabe si la búsqueda tiene contenido o no.
///
/// ── Y por qué se apaga sola ──────────────────────────────────
///
/// En un aparato modesto, un parpadeo es un repintado cada medio segundo
/// mientras la pantalla esté abierta, y esta pantalla además está buscando
/// en todas las extensiones a la vez. Ahí el cursor se queda quieto: se
/// sigue viendo dónde va el texto, sin gastar nada.
class _CampoDeBusqueda extends StatefulWidget {
  const _CampoDeBusqueda({required this.texto, this.accent});

  final String texto;
  final Color? accent;

  @override
  State<_CampoDeBusqueda> createState() => _CampoDeBusquedaState();
}

class _CampoDeBusquedaState extends State<_CampoDeBusqueda>
    with SingleTickerProviderStateMixin {
  late final AnimationController _latido = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  bool get _quieto => PrismHubMas.nivel == NivelDeAparato.bajo;

  @override
  void initState() {
    super.initState();
    if (!_quieto) _latido.repeat(reverse: true);
  }

  @override
  void dispose() {
    _latido.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final acento = widget.accent ?? HomeTheme.accentPink;
    final vacio = widget.texto.isEmpty;
    return AnimatedContainer(
      duration: PrismHubMas.animacion(const Duration(milliseconds: 220)),
      curve: Curves.easeOut,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: HomeTheme.cardSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: vacio ? HomeTheme.border : acento.withValues(alpha: 0.75),
          width: vacio ? 1 : 1.6,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.search_rounded,
            size: 20,
            color: vacio ? HomeTheme.textPlaceholder : acento,
          ),
          const SizedBox(width: 10),
          // Flexible y no Expanded: con poco texto, el cursor queda pegado a
          // la última letra en vez de irse al otro extremo del cuadro.
          Flexible(
            child: Text(
              vacio ? 'search.hint-text'.i18n : widget.texto,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 17,
                color:
                    vacio ? HomeTheme.textPlaceholder : HomeTheme.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 3),
          _cursor(acento),
        ],
      ),
    );
  }

  Widget _cursor(Color acento) {
    const barra = SizedBox(width: 2, height: 20);
    final pintada = DecoratedBox(
      decoration: BoxDecoration(
        color: acento,
        borderRadius: BorderRadius.circular(1),
      ),
      child: barra,
    );
    if (_quieto) return Opacity(opacity: 0.85, child: pintada);
    return FadeTransition(
      // De 1 a 0,15 y no a 0: apagándose del todo, el cuadro parece vacío la
      // mitad del tiempo. Así late sin llegar a desaparecer.
      opacity: Tween<double>(begin: 1, end: 0.15).animate(
        CurvedAnimation(parent: _latido, curve: Curves.easeInOut),
      ),
      child: pintada,
    );
  }
}
