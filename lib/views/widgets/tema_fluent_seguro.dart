import 'package:fluent_ui/fluent_ui.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';

/// El tema de escritorio, sin reventar cuando no hay ninguno arriba.
///
/// ── El fallo que esto evita ─────────────────────────────────────────────────
///
/// `FluentTheme.of(context)` termina en un `!`: si no encuentra un `FluentTheme`
/// entre sus ancestros, no devuelve null — lanza. Y en PC eso no puede pasar,
/// porque la app entera vive bajo un `FluentApp`.
///
/// En Android sí pasa. Hay widgets pensados para escritorio que se montan igual
/// dentro del árbol Material —el reproductor arma sus controles de escritorio
/// en modo «solo lógica» para reutilizar su motor, y varias tarjetas se
/// comparten entre plataformas— y ahí no hay ningún `FluentTheme` arriba.
///
/// Visto en el registro de un televisor Onn con Android 14, dos veces
/// reproduciendo:
///
///     SEVERE: Null check operator used on a null value
///       #0 FluentTheme.of (package:fluent_ui/src/styles/theme.dart:21)
///     SEVERE: ErrorWidget Null check operator used on a null value
///
/// El `ErrorWidget` detrás es la consecuencia: Flutter reemplaza ese trozo del
/// árbol por su pantalla de error. En un televisor eso es un rectángulo roto en
/// medio del reproductor.
///
/// ── Por qué un acceso propio y no arreglar cada sitio ───────────────────────
///
/// Porque el problema no es un widget: es que cualquiera de ellos puede acabar
/// montado del lado de Android sin que quien lo escribió lo previera, y el
/// fallo aparece en producción y en el aparato de otro. Pasando siempre por
/// acá, un ancestro que falte deja de ser un cierre y pasa a ser un tema por
/// defecto — que en el peor caso se ve distinto, y eso se arregla mirando.
///
/// En escritorio no cambia nada: ahí el ancestro está y se devuelve el de
/// verdad.
FluentThemeData temaFluent(BuildContext context) =>
    FluentTheme.maybeOf(context) ?? _porDefecto;

/// El de reserva: oscuro y con el acento de la app, que es lo más parecido a lo
/// que se vería si el ancestro estuviera.
final _porDefecto = FluentThemeData.dark().copyWith(
  accentColor: AccentColor.swatch(const {'normal': HomeTheme.oscuroAcento}),
);
