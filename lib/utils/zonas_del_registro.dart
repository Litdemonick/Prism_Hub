/// Las áreas en que se divide el registro.
///
/// ── Por qué están acá y no en cada pantalla ─────────────────────────────────
///
/// Estas reglas estaban escritas tres veces: en el visor en vivo, en el
/// exportador y —al sumar el historial— iban camino de una cuarta. Las tres
/// decidían lo mismo con listas parecidas pero no idénticas, así que lo que se
/// veía en pantalla y lo que salía exportado ya no coincidían del todo.
///
/// Un registro en el que «Fallos» significa una cosa mirándolo y otra
/// mandándolo es peor que uno sin filtros: lleva a discutir sobre líneas que
/// una de las dos vistas nunca mostró.
///
/// ── Por qué áreas y no niveles de gravedad ──────────────────────────────────
///
/// La gravedad ya la dice el color. Quien abre el registro viene buscando una
/// cosa concreta —por qué falló una extensión, por qué se cerró la app, qué
/// hizo el reproductor— y son casi siempre estas cuatro.
library;

import 'package:flutter/material.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';

enum ZonaDelRegistro {
  todo('settings.log-filtro-todo', 'TODO'),

  /// Solo lo que salió mal. Es el primer sitio donde mirar.
  fallos('settings.log-filtro-fallos', 'FALLOS Y AVISOS'),

  /// Extensiones y servidores: qué resolvió, cuál falló, cuánto tardó.
  extensiones('settings.log-filtro-extensiones', 'EXTENSIONES Y SERVIDORES'),

  /// El reproductor: qué decodifica, cuadros perdidos, saltos.
  reproductor('settings.log-filtro-reproductor', 'REPRODUCTOR');

  const ZonaDelRegistro(this.clave, this.seccion);

  /// La clave de idioma del botón.
  final String clave;

  /// Cómo se titula esta área en el archivo exportado.
  ///
  /// El mismo nombre sirve para pedirle al servidor de red que sirva solo
  /// esta zona, así que hay UNA cadena y no dos que se puedan separar.
  final String seccion;

  /// El área a servir o exportar, o null si son todas.
  String? get area => this == ZonaDelRegistro.todo ? null : seccion;

  /// Si una línea pertenece a esta área.
  ///
  /// Estricto: la cabecera de sesión no entra acá. Para mostrar en pantalla se
  /// suma aparte con [esCabecera] —sin ella no se sabría de qué sesión ni de
  /// qué aparato son las líneas que quedan— pero en el archivo exportado no
  /// corresponde repetirla dentro de cada sección.
  bool acepta(String l) => switch (this) {
        ZonaDelRegistro.todo => true,
        ZonaDelRegistro.fallos => _esFallo(l),
        ZonaDelRegistro.extensiones => _tieneAlguna(l, _deExtensiones),
        ZonaDelRegistro.reproductor => _tieneAlguna(l, _deReproductor),
      };

  /// Lo que se muestra en pantalla con esta zona puesta.
  ///
  /// Igual que [acepta] pero dejando pasar la cabecera de la sesión: filtrando
  /// por «Reproductor» sin ella, lo que queda son líneas sueltas sin decir de
  /// qué arranque ni de qué aparato salieron.
  bool seVe(String l) => acepta(l) || esCabecera(l);
}

/// Si la línea es parte de la cabecera con que abre cada sesión.
///
/// ── Qué cuenta como cabecera ────────────────────────────────────────────────
///
/// Todo el recuadro, no solo el nombre. Antes se miraba `═══` y `║`, que son
/// los del marco de arriba — así que los apartados de abajo («QUÉ ES ESTO»,
/// «QUÉ NO LLEVA»), dibujados con otros caracteres, NO contaban. El efecto era
/// que al filtrar por cualquier zona se veía el nombre en grande y debajo,
/// directamente, líneas técnicas: la explicación de qué es esto y qué no
/// lleva desaparecía justo para quien está mirando una zona concreta.
///
/// Lo mismo vale para la lista de extensiones instaladas, que se dibuja igual:
/// es contexto y tiene que verse mire uno lo que mire.
bool esCabecera(String l) => esElRecuadro(l) || l.contains('═══');

/// Lo que no cayó en ninguna zona concreta.
///
/// Se calcula por descarte y no con su propia lista: así ninguna línea se
/// pierde al exportar. Un registro al que le faltan líneas es peor que uno
/// largo.
bool esGeneral(String l) =>
    !ZonaDelRegistro.fallos.acepta(l) &&
    !ZonaDelRegistro.reproductor.acepta(l) &&
    !ZonaDelRegistro.extensiones.acepta(l);

bool _tieneAlguna(String l, List<String> marcas) {
  for (final m in marcas) {
    if (l.contains(m)) return true;
  }
  return false;
}

/// Lo que salió mal, mire quien lo mire.
///
/// Los tres niveles de `logging` que no son informativos, más las dos marcas
/// que deja el vigilante de arranque cuando la app no se cerró sola. Un fallo
/// entra acá ADEMÁS de en su zona: quien abre «Fallos» quiere los de todos
/// lados, no elegir primero de qué parte de la app.
bool _esFallo(String l) =>
    l.contains(' SEVERE ') ||
    l.contains(' SHOUT ') ||
    l.contains(' WARNING ') ||
    l.contains('LO ULTIMO QUE HIZO') ||
    l.contains('no se cerro normalmente');

/// El bloqueador de anuncios NO entra en «Extensiones».
///
/// Estaba ahí porque se nota sobre todo cargando páginas de extensiones, pero
/// es infraestructura de la app: sus listas se descargan al arrancar, sin que
/// haya ninguna extensión de por medio. En «Extensiones» ensuciaba la zona con
/// cuatro líneas de arranque que no tienen nada que ver con lo que se busca
/// ahí. Queda en «Todo» y en «General de la app».
///
/// La marca de los pedidos de red de la app. Ver TrazaDeRed.
///
/// No entra en ninguna zona: un pedido de red puede ser de cualquier parte de
/// la app —el aviso de versión, una portada, el seguimiento— así que meterlo
/// en «Extensiones» diría algo que no es. Queda en «Todo» y en «General de la
/// app», que es donde corresponde.
///
/// Las que fallan sí aparecen en «Fallos», porque se escriben como aviso.
const marcaDeRed = '[red]';

/// Las marcas de lo que escribe el reproductor.
///
/// ── Por qué por marca de origen y no por palabras sueltas ───────────────────
///
/// La primera versión buscaba palabras del texto («salto», «rueda»), y eso
/// clasifica por lo que dice la línea en vez de por quién la escribió. Una
/// línea de otra parte de la app que mencionara alguna de esas palabras se
/// colaba, y una del reproductor que no la usara se perdía.
///
/// Cada una de estas es el prefijo con que una parte del reproductor firma sus
/// líneas, así que la clasificación coincide con el código que las emite.
const _deReproductor = [
  'recorte fMP4:',
  'rueda',
  'media_kit',
  'exoplayer',
  'mpv',
  'play/pausa',
  'salto a ',
  'saltar dentro',
  '_safePlayerInit',
  'safePlay',
  'safePause',
  'bomba ·',
  'medición',
  'DECODIFICACIÓN',
  'FRAME LENTO',
  'Pantalla puesta',
  'Dibujado del vídeo',
  'Motor de vídeo',
  'continuar viendo',
  '[relay]',
];

/// Las marcas de lo que escriben las extensiones y la resolución de servidores.
///
/// Va junto a propósito: para quien lee el registro, «la extensión X no
/// resolvió» y «el servidor que devolvió X no dio vídeo» son el mismo
/// problema visto en dos pasos, y separarlos obligaría a mirar dos zonas para
/// entender un solo fallo.
const _deExtensiones = [
  '[extensiones]',
  '[home]',
  '[catálogo]',
  '[zona]',
  '[vista previa]',
  '[sniffer',
  '[webview-html]',
  'Page-sniff',
  'Sniffer',
  'ficha ·',
  'switchServer',
  'RESULTADO ·',
  'index.json',
  'extension',
  'Extension',
];

/// De qué color va cada línea.
///
/// ── Por qué lo normal va en blanco ──────────────────────────────────────────
///
/// Antes lo corriente iba en gris apagado y solo lo señalado tenía color. El
/// efecto era el contrario del buscado: la mayor parte del registro —lo que
/// cuenta qué estaba haciendo la app cuando pasó el fallo— quedaba en el color
/// que se lee como «esto no importa», y en un televisor a tres metros
/// directamente no se leía.
///
/// Pedido explícito: «que se ponga en color blanco cuando es algo normal».
/// Ahora lo normal se lee bien y el color queda para lo que hay que encontrar
/// de un vistazo: fallos, avisos, el corte entre sesiones y las dos líneas que
/// se buscan a propósito.
///
/// Vive acá y no en cada pantalla porque lo usan las tres —el registro en
/// vivo, el historial y cada sesión abierta— y un rojo que signifique cosas
/// distintas según dónde se mire es peor que no tener color.
Color colorDeLinea(String linea) {
  if (linea.contains(' SEVERE ') || linea.contains(' SHOUT ')) {
    return HomeTheme.accentRed;
  }
  if (linea.contains(' WARNING ')) return const Color(0xFFE8B339);
  // La cabecera de sesión: es lo que separa una sesión de la siguiente en un
  // archivo que ya trae varias, así que tiene que encontrarse al recorrer.
  if (esCabecera(linea)) return const Color(0xFF6FCFA5);
  // El veredicto de cada servidor y el rastro del último cierre: las dos
  // líneas que se buscan a propósito, así que se despegan del resto.
  if (linea.contains('RESULTADO ·')) return const Color(0xFF62B6FF);
  if (linea.contains('LO ULTIMO QUE HIZO')) return const Color(0xFFD98CFF);
  // Lo que hizo la persona: se sigue como un hilo, así que se distingue sin
  // gritar.
  if (linea.contains('[paso]')) return const Color(0xFF9FE3C0);
  return HomeTheme.textPrimary;
}

/// Si esta línea es parte del recuadro de presentación.
///
/// Vive acá, junto al sitio que dibuja el recuadro, para que no haya dos
/// ideas distintas de qué cuenta como recuadro. Si mañana cambia el dibujo,
/// cambia en un solo archivo.
bool esElRecuadro(String linea) {
  for (final c in _caracteresDelRecuadro) {
    if (linea.contains(c)) return true;
  }
  return false;
}

/// Los caracteres con los que está dibujado. Ninguno lo escribe otra cosa de
/// la app: son de dibujo de cajas, no de texto.
const _caracteresDelRecuadro = ['╔', '╚', '║', '╗', '╝', '┌', '└', '├', '│'];

/// Junta las líneas seguidas del recuadro en una sola.
///
/// El recuadro es un dibujo, no texto: solo se entiende con todas sus líneas
/// alineadas entre sí. Mostrado línea por línea, cada una se ajusta al ancho
/// por su cuenta y en cuanto una no entra se parte en dos — que es como se
/// rompía en pantalla.
///
/// Juntándolas, quien lo dibuja puede tratarlo como un bloque: achicarlo
/// entero hasta que entre, sin que las líneas se desalineen entre sí.
///
/// El resto de las líneas pasan tal cual, una por una, porque son texto de
/// verdad y ahí ajustar al ancho es lo correcto.
List<String> agruparElRecuadro(List<String> lineas) {
  if (lineas.isEmpty) return lineas;
  var hayAlguno = false;
  for (final l in lineas) {
    if (esElRecuadro(l)) {
      hayAlguno = true;
      break;
    }
  }
  // Sin recuadro no se copia nada: es el caso de casi todos los refrescos, y
  // recorrer miles de líneas para no cambiar ninguna sería trabajo tirado.
  if (!hayAlguno) return lineas;

  final salida = <String>[];
  final bloque = <String>[];
  void cerrarBloque() {
    if (bloque.isEmpty) return;
    salida.add(bloque.join('\n'));
    bloque.clear();
  }

  for (final l in lineas) {
    if (esElRecuadro(l)) {
      bloque.add(l);
    } else {
      cerrarBloque();
      salida.add(l);
    }
  }
  cerrarBloque();
  return salida;
}
