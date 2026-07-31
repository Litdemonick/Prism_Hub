import 'package:prismhub/models/history.dart';

/// Se da por terminado al llegar al 90%: los videos cierran con ending y
/// créditos que casi nadie mira enteros, y en lectura la última página o el
/// último tramo de scroll rara vez se completa del todo. Exigir el 100% dejaba
/// obras terminadas marcadas como pendientes para siempre.
const double _umbralFinal = 0.9;

/// Decide si una obra quedó "al día" después de ver o leer algo.
///
/// Antes cada controller repetía `index >= playList.length - 1`, o sea que la
/// decisión se tomaba SOLO por la posición en la lista, sin mirar si el
/// usuario había terminado. Y como el historial se escribe apenas ARRANCA la
/// reproducción (ver VideoController._touchHistory, atado al stream `playing`),
/// abrir el último episodio alcanzaba para marcarlo completado y sacarlo de
/// "Continuar viendo" mientras todavía se estaba mirando.
///
/// El caso peor era una película: `playList` tiene un solo elemento, así que
/// `0 >= 0` daba completado en el segundo uno y la película NUNCA llegaba a
/// "Continuar". Por eso el síntoma se veía en video y casi no en lectura: un
/// manga se abre por un capítulo del medio de una lista larga, no por el
/// último.
///
/// Ahora "al día" pide las dos cosas: estar en el último capítulo o episodio
/// **y** haberlo terminado de verdad.
///
/// - [index] posición actual dentro de la lista (base 0).
/// - [total] cuántos capítulos/episodios tiene la lista.
/// - [progreso] segundos vistos (video) o página/scroll actual (lectura).
/// - [progresoTotal] duración total o cantidad de páginas. Puede ser 0 cuando
///   no se conoce.
WatchState calcularWatchState({
  required int index,
  required int total,
  required num progreso,
  required num progresoTotal,
}) {
  // Quedan capítulos por delante: sigue en curso, sin importar el progreso
  // dentro de este.
  if (total <= 0 || index < total - 1) return WatchState.pending;
  // Sin duración conocida no hay forma de saber si terminó. Pasa con el
  // fallback de WebView, que no puede leer la duración real del video del
  // sitio. Ante la duda se deja en curso: que algo sobre en "Continuar" es
  // molesto, pero esconder algo a medias hace perder el progreso de vista, que
  // es justamente lo que esa fila existe para evitar.
  if (progresoTotal <= 0) return WatchState.pending;
  return progreso >= progresoTotal * _umbralFinal
      ? WatchState.completed
      : WatchState.pending;
}

/// Igual que [calcularWatchState] pero tomando el progreso como viene del
/// lector, que lo maneja en texto. Un valor no numérico se trata como 0, o sea
/// "no se sabe si terminó" → en curso.
WatchState calcularWatchStateDesdeTexto({
  required int index,
  required int total,
  required String progreso,
  required String progresoTotal,
}) {
  return calcularWatchState(
    index: index,
    total: total,
    progreso: num.tryParse(progreso) ?? 0,
    progresoTotal: num.tryParse(progresoTotal) ?? 0,
  );
}
