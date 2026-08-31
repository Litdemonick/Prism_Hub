import 'package:flutter/material.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/tv/focusable_card.dart';

/// La columna de acciones al costado, para las pantallas de televisor.
///
/// ── Por qué existe ──────────────────────────────────────────────────────────
///
/// Con el dedo, los botones de la barra superior están siempre ahí. Con un
/// mando hay que LLEGAR hasta ellos, y desde el medio de una lista larga —o de
/// un registro de tres mil líneas— eso son cientos de pulsaciones hacia
/// arriba. Un botón que existe pero al que no se puede llegar es lo mismo que
/// no tenerlo.
///
/// Los mandos están hechos para moverse en cruz, así que las acciones van en
/// una columna al costado: desde cualquier punto del contenido, IZQUIERDA
/// salta directo a ellas y DERECHA vuelve. Todo a una pulsación, sin importar
/// por dónde vaya el desplazamiento.
///
/// ── Por qué es un widget aparte ─────────────────────────────────────────────
///
/// Nació dentro de la pantalla del registro y ahora la usan también las del
/// historial. Copiarla habría dejado dos columnas que se irían separando con
/// cada arreglo — y quien las usa espera que se comporten igual, porque a la
/// vista son la misma cosa.
class ColumnaDeAcciones extends StatelessWidget {
  const ColumnaDeAcciones({
    super.key,
    required this.titulo,
    required this.grupos,
    this.detalle,
  });

  final String titulo;

  /// La línea chica bajo el título: cuántas líneas, cuántas aperturas, etc.
  final String? detalle;

  final List<GrupoDeColumna> grupos;

  /// Ancho de la columna.
  ///
  /// Suficiente para que ninguna etiqueta se corte a la distancia de un sofá,
  /// y no más: lo que importa es el contenido, y cada píxel que se lleva la
  /// columna se lo saca a él.
  static const ancho = 250.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: ancho,
      padding: const EdgeInsets.fromLTRB(20, 20, 12, 20),
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: HomeTheme.border),
        ),
      ),
      // Se desplaza por si un televisor con poca altura útil no llega a
      // mostrarlo todo: es preferible que se pueda bajar a que la última
      // opción quede cortada contra el borde.
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              titulo,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: HomeTheme.textPrimary,
              ),
            ),
            if (detalle != null) ...[
              const SizedBox(height: 4),
              Text(
                detalle!,
                style: TextStyle(fontSize: 12, color: HomeTheme.textMuted),
              ),
            ],
            for (final grupo in grupos) ...[
              // Un grupo sin rótulo necesita MÁS aire, no menos.
              //
              // El rótulo («ZONA», «ACCIONES») venía con su propio margen
              // debajo, así que sin él la primera opción quedaba pegada a lo
              // de arriba — en el historial, donde el único grupo es «Salir»,
              // la tarjeta salía casi tocando el título de la pantalla.
              // Reportado en vivo en televisor y en PC.
              SizedBox(height: grupo.titulo != null ? 18 : 30),
              if (grupo.titulo != null)
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 8),
                  child: Text(
                    grupo.titulo!.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w700,
                      color: HomeTheme.textMuted,
                    ),
                  ),
                ),
              // ── Con clave, y no sueltas ───────────────────────────
              //
              // Sin clave, Flutter empareja los hijos de una columna por
              // POSICIÓN: el primero con el primero, el segundo con el
              // segundo. Y esta columna cambia de largo — «volver al final»
              // solo está cuando la vista se fue del fondo — así que al
              // aparecer o desaparecer, todo lo que viene detrás se corre un
              // lugar y hereda el estado interno de su vecino, marca de
              // selección incluida.
              //
              // Reportado en vivo con foto: tres botones encendidos a la vez.
              // Y con tres luces puestas no se sabe cuál se va a activar al
              // pulsar, que es el «a veces cuesta» del mismo reporte — el
              // mando respondía bien, lo que estaba mal era dónde parecía
              // estar el foco.
              //
              // Con la clave, cada opción se empareja consigo misma
              // independientemente de dónde quede. La pone acá el contenedor
              // y no cada quien la usa, para que no dependa de acordarse.
              for (final opcion in grupo.opciones)
                KeyedSubtree(
                  key: ValueKey(opcion.id ?? opcion.texto),
                  child: opcion,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Un grupo de opciones con su rótulo.
class GrupoDeColumna {
  const GrupoDeColumna({this.titulo, required this.opciones});

  final String? titulo;
  final List<OpcionDeColumna> opciones;
}

/// Una fila de la columna: se ilumina con el foco y se marca si está puesta.
///
/// Son dos señales distintas y hacen falta las dos. El resplandor dice DÓNDE
/// estás parado; el relleno dice QUÉ está activo. Con una sola no se puede
/// distinguir «el filtro Fallos está puesto» de «estoy encima de Fallos».
class OpcionDeColumna extends StatelessWidget {
  const OpcionDeColumna({
    super.key,
    required this.texto,
    required this.onTap,
    this.id,
    this.icono,
    this.elegido = false,
    this.foco,
    this.cargando = false,
  });

  /// Cómo se llama esta opción para la columna, con independencia de lo que
  /// diga en pantalla.
  ///
  /// Hace falta cuando la etiqueta cambia sola: «Pausar» pasa a «Seguir» e
  /// «Historial (9)» a «Historial (10)». Si la identidad fuera el texto, esos
  /// cambios contarían como una opción distinta y la tarjeta se reharía —
  /// perdiendo el foco justo en el momento en que la persona la está
  /// pulsando, que es cuando la etiqueta cambia.
  ///
  /// Donde la etiqueta es fija no hace falta ponerlo.
  final String? id;

  final String texto;
  final VoidCallback onTap;
  final IconData? icono;
  final bool elegido;
  final FocusNode? foco;

  /// Está corriendo una acción larga (activar/desactivar/actualizar/instalar
  /// todas) y esta es SU opción.
  ///
  /// Sin ninguna señal, tocar «Activar todas» y ver que no pasa nada visible
  /// —la tanda tarda, y con el mando no hay cursor de espera— invita a
  /// tocarlo de nuevo, que es justo lo que `AccionesMasivasDeExtensiones`
  /// bloquea con su propio candado pero sin decir por qué. El ícono pasa a un
  /// giro y la fila deja de reaccionar al mando hasta que termina.
  final bool cargando;

  @override
  Widget build(BuildContext context) {
    // Opaco a propósito: el resplandor de foco de FocusableCard se dibuja
    // DEBAJO del hijo y cuenta con que el hijo lo tape, de modo que solo se
    // vea lo que desborda. Con un relleno semitransparente el difuminado se
    // ve entero a través y parece que la luz se sale del área.
    final fondo = elegido
        ? Color.alphaBlend(
            HomeTheme.accentPink.withValues(alpha: 0.20),
            HomeTheme.bg,
          )
        : Color.alphaBlend(
            Colors.white.withValues(alpha: 0.05),
            HomeTheme.bg,
          );
    return Padding(
      // Antes eran 6 px. El halo de foco en televisor tiene un desenfoque de
      // 22 con 1,5 de extensión (ver FocusableCard) — con solo 6 px de aire,
      // el resplandor de una opción se metía contra el borde de la siguiente
      // y con varias pegadas se veía como una sola mancha rosada en vez de un
      // brillo alrededor de UNA fila. Reportado en vivo: "cuando hay muchos
      // botones pegados se ve raro, dale un poco más de espacio".
      padding: const EdgeInsets.only(bottom: 14),
      child: FocusableCard(
        borderRadius: 10,
        focusNode: foco,
        // Ocupa el ancho entero de la columna: sin margen hacia donde crecer,
        // el crecido solo la pega contra los bordes. Ver conCrecido.
        conCrecido: false,
        // Sigue siendo enfocable con `cargando`: sacarle el foco justo cuando
        // alguien lo tocó movería el marco a otra fila sin que nadie lo haya
        // pedido. Lo único que cambia es que tocar de nuevo no hace nada —
        // el candado real vive en `AccionesMasivasDeExtensiones`, esto es
        // solo la señal.
        onTap: cargando ? () {} : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: fondo,
          ),
          child: Row(
            children: [
              if (cargando) ...[
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(HomeTheme.accentPink),
                  ),
                ),
                const SizedBox(width: 12),
              ] else if (icono != null) ...[
                Icon(
                  icono,
                  size: 18,
                  color: elegido ? HomeTheme.accentPink : HomeTheme.textPrimary,
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  texto,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: elegido ? FontWeight.w700 : FontWeight.w500,
                    color: cargando
                        ? HomeTheme.textMuted
                        : elegido
                            ? HomeTheme.accentPink
                            : HomeTheme.textPrimary,
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

/// El marco del contenido, con el borde encendido cuando tiene el foco.
///
/// Va junto a la columna porque son las dos mitades de la misma idea: la
/// columna dice qué se puede hacer y esto dice si el foco está acá o allá. Un
/// bloque de texto o una lista no tienen forma de indicarlo por su cuenta.
class PanelDeTelevisor extends StatelessWidget {
  const PanelDeTelevisor({
    super.key,
    required this.child,
    required this.tieneFoco,
  });

  final Widget child;
  final bool tieneFoco;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.black.withValues(alpha: 0.22),
        border: Border.all(
          color: tieneFoco ? HomeTheme.accentPink : HomeTheme.border,
          width: tieneFoco ? 2 : 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: child,
      ),
    );
  }
}
