import 'package:flutter/material.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/tv/focusable_card.dart';

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

class TecladoTv extends StatefulWidget {
  const TecladoTv({
    super.key,
    required this.texto,
    required this.onCambio,
    this.accent,
    this.ancho = 380,
    this.mostrarCampo = true,
  });

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

  @override
  Widget build(BuildContext context) {
    final filas = _numeros ? _filasNumeros : _filasLetras;
    return SizedBox(
      width: widget.ancho,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // El "campo": muestra lo escrito, no se edita. Con el mando no hay
          // cursor que mover, así que un TextField de verdad solo agregaría
          // el teclado del sistema encima del nuestro.
          if (widget.mostrarCampo) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: HomeTheme.cardSurface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: HomeTheme.border),
              ),
              child: Text(
                widget.texto.isEmpty ? 'search.hint-text'.i18n : widget.texto,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 17,
                  color: widget.texto.isEmpty
                      ? HomeTheme.textPlaceholder
                      : HomeTheme.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],
          Row(
            children: [
              _tecla(
                _numeros ? 'ABC' : '123',
                onTap: () => setState(() => _numeros = !_numeros),
                ancho: 74,
              ),
              const SizedBox(width: 8),
              _teclaIcono(Icons.delete_outline_rounded, onTap: _borrarTodo),
              const SizedBox(width: 8),
              _teclaIcono(Icons.backspace_outlined, onTap: _borrarUno),
            ],
          ),
          const SizedBox(height: 12),
          // ── El espacio va A LA DERECHA, no debajo del teclado ────────
          //
          // Estaba como una barra ancha al pie. Con un mando eso obliga a
          // bajar todas las filas de letras cada vez que hace falta un
          // espacio, y a volver a subir para la palabra siguiente — en una
          // búsqueda de tres palabras son un montón de pulsaciones.
          //
          // A la derecha se llega desde CUALQUIER fila con la flecha derecha,
          // que es un movimiento y siempre el mismo. Alta como el teclado
          // entero para que sea el blanco más fácil de acertar.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final fila in filas) ...[
                    Row(
                      children: [
                        for (final letra in fila) ...[
                          _tecla(letra, onTap: () => _escribir(letra)),
                          const SizedBox(width: 8),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
              _tecla(
                ' ',
                onTap: () => _escribir(' '),
                ancho: 74,
                // Tres filas de 44 más los dos huecos de 8 que las separan.
                alto: 44 * filas.length + 8 * (filas.length - 1),
                etiqueta: '␣',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tecla(
    String letra, {
    required VoidCallback onTap,
    double ancho = 44,
    double alto = 44,
    String? etiqueta,
  }) {
    return FocusableCard(
      borderRadius: 8,
      accent: widget.accent,
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
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: HomeTheme.textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _teclaIcono(IconData icono, {required VoidCallback onTap}) {
    return FocusableCard(
      borderRadius: 8,
      accent: widget.accent,
      onTap: onTap,
      child: Container(
        width: 52,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: HomeTheme.cardSurface,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icono, size: 20, color: HomeTheme.textPrimary),
      ),
    );
  }
}
