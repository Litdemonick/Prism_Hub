import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:prismhub/utils/nsfw18_zone.dart';
import 'package:prismhub/views/pages/nsfw18/nsfw18_pin_settings_tile.dart';
import 'package:prismhub/utils/modo_app.dart';
import 'package:prismhub/models/index.dart';
import 'package:prismhub/utils/application.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/platform_tv.dart';
import 'package:prismhub/utils/prismhub_storage.dart';
import 'package:prismhub/utils/zonas_preferidas.dart';
import 'package:prismhub/views/pages/extension/extension_page.dart';
import 'package:prismhub/views/pages/extension/extension_repo_page.dart';
import 'package:prismhub/views/pages/nsfw18/nsfw18_zone_page.dart';
import 'package:prismhub/views/pages/settings/prismhub_mas_page.dart';
import 'package:prismhub/views/pages/settings/registro_en_vivo_page.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/tv/focusable_card.dart';

/// Los Ajustes de Android TV — pantalla propia, no la de teléfono adaptada.
///
/// ── Por qué se rehizo entera ────────────────────────────────────────────
///
/// Pedido explícito: "está hecho para Android normal o para PC, no para un
/// televisor". Y es literal: Android TV ES `Platform.isAndroid`, así que
/// caía en la misma lista de `ListTile` pensada para tocarse con el dedo a
/// treinta centímetros. En una pantalla que se mira desde el sillón eso es
/// texto chico, filas apretadas y un recorrido de mando larguísimo — hay
/// que bajar por decenas de filas para llegar a lo de abajo.
///
/// Acá el diseño es el que usan las apps de televisor: **categorías a la
/// izquierda, sus ajustes a la derecha**. El mando se mueve entre pocas
/// categorías (seis) en vez de por una lista interminable, y cada panel
/// entra casi entero sin desplazarse.
///
/// ── Y solo lo que sirve en un televisor ─────────────────────────────────
///
/// Lo que se dejó afuera, con el motivo:
///
///   · **Sugerencias, código fuente, extensiones en GitHub, contribuyentes**
///     — abren una página web. Muchas cajas de TV ni traen navegador, y
///     escribir un reporte con un control remoto no es realista. Un botón
///     que lleva a un callejón sin salida es peor que no tenerlo.
///   · **Intervalo de salto** — guarda `arrowLeft`/`arrowRight`, que usan
///     el doble toque de celular y el teclado de escritorio. El reproductor
///     de TV salta 10 segundos fijos y nunca los lee: era un ajuste que se
///     podía cambiar sin que hiciera nada.
///   · **Clave de TMDB, proxy, URL del repositorio** — son campos de texto
///     largo. Se llegan igual desde un teléfono o una PC con la misma
///     cuenta de extensiones; escribir una clave de 32 caracteres con un
///     mando no es algo que valga la pena ofrecer acá.
///   · **Copia de seguridad** — necesita el selector de archivos del
///     sistema, que en TV muchas veces no existe o no se puede navegar.
///   · **Modo claro** — un televisor se mira a oscuras; el tema claro sobre
///     una pantalla grande encandila.
class SettingsPageTv extends StatefulWidget {
  const SettingsPageTv({super.key});

  @override
  State<SettingsPageTv> createState() => _SettingsPageTvState();
}

enum _Categoria {
  general(Icons.tune_rounded),
  reproductor(Icons.play_circle_outline_rounded),
  inicio(Icons.home_rounded),
  extensiones(Icons.extension_rounded),
  adultos(Icons.lock_outline_rounded),
  acercaDe(Icons.info_outline_rounded);

  const _Categoria(this.icono);
  final IconData icono;

  String get etiqueta => switch (this) {
        _Categoria.general => 'settings.general'.i18n,
        _Categoria.reproductor => 'settings.video-player'.i18n,
        _Categoria.inicio => 'common.home'.i18n,
        _Categoria.extensiones => 'settings.extension'.i18n,
        _Categoria.adultos => 'settings.nsfw'.i18n,
        _Categoria.acercaDe => 'settings.about'.i18n,
      };
}

class _SettingsPageTvState extends State<SettingsPageTv> {
  _Categoria _categoria = _Categoria.general;

  @override
  void initState() {
    super.initState();
    ZonasPreferidasEnInicio.ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HomeTheme.bg,
      body: SafeArea(
        child: Padding(
          padding: HomeTheme.margenTv(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'common.settings'.i18n,
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: HomeTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 22),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 260, child: _menu()),
                    const SizedBox(width: 26),
                    Expanded(child: _panel()),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Las categorías, a la izquierda.
  Widget _menu() {
    return ListView.separated(
      itemCount: _Categoria.values.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final cat = _Categoria.values[i];
        final elegida = cat == _categoria;
        return FocusableCard(
          borderRadius: 12,
          // Arranca en la que está abierta, para que el mando entre por ahí
          // y no por la primera de la lista.
          autofocus: elegida,
          onTap: () => setState(() => _categoria = cat),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              color: elegida
                  ? HomeTheme.accentPink.withValues(alpha: 0.16)
                  : HomeTheme.cardSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: elegida ? HomeTheme.accentPink : HomeTheme.border,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  cat.icono,
                  size: 24,
                  color:
                      elegida ? HomeTheme.accentPink : HomeTheme.textPrimary,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    cat.etiqueta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight:
                          elegida ? FontWeight.w800 : FontWeight.w600,
                      color: elegida
                          ? HomeTheme.accentPink
                          : HomeTheme.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// El contenido de la categoría elegida, a la derecha.
  ///
  /// Siempre dentro de un `ListView`: con el foco moviéndose por las filas,
  /// el desplazamiento lo pide `RescateDeFoco` solo — pero necesita que HAYA
  /// un scrollable del que tirar. Sin él, la última fila de una categoría
  /// larga quedaba fuera de la pantalla sin forma de alcanzarla (pedido
  /// explícito: "scroll correcto, que se vea todo y no se corte").
  Widget _panel() {
    // La clave por categoría reinicia el desplazamiento al cambiar: sin
    // esto, pasar de una categoría larga a una corta dejaba el panel
    // desplazado y en blanco.
    return ListView(
      key: ValueKey(_categoria),
      padding: const EdgeInsets.only(right: 6, bottom: 20),
      children: switch (_categoria) {
        _Categoria.general => _general(),
        _Categoria.reproductor => _reproductor(),
        _Categoria.inicio => _inicio(),
        _Categoria.extensiones => _extensiones(),
        _Categoria.adultos => _adultos(),
        _Categoria.acercaDe => _acercaDe(),
      },
    );
  }

  // ─── Las categorías ──────────────────────────────────────────────────

  List<Widget> _general() => [
        _Interruptor(
          icono: Icons.language_rounded,
          titulo: 'settings.language'.i18n,
          // El idioma no es un interruptor: se alterna entre los dos que la
          // app tiene traducidos, que es lo mismo que hace el desplegable de
          // teléfono/PC pero sin abrir un menú que el mando tenga que
          // recorrer.
          valorTexto: _idiomaActual(),
          onTap: _alternarIdioma,
        ),
        _Interruptor(
          icono: Icons.system_update_rounded,
          titulo: 'settings.auto-check-update'.i18n,
          subtitulo: 'settings.auto-check-update-subtitle'.i18n,
          clave: SettingKey.autoCheckUpdate,
          porDefecto: true,
        ),
        _Interruptor(
          icono: Icons.notifications_active_outlined,
          titulo: 'settings.check-new-episodes'.i18n,
          subtitulo: 'settings.check-new-episodes-subtitle'.i18n,
          clave: SettingKey.checkNewEpisodes,
          porDefecto: true,
        ),
        // Sin el interruptor de "guardar registro": en televisor se escribe
        // siempre (ver PrismLog). Ahí ese archivo no es una opción, es lo
        // único que explica un cierre — y no hay dónde exportarlo ni con qué
        // abrirlo, así que se lee desde acá mismo.
        _Boton(
          icono: Icons.article_outlined,
          titulo: 'settings.view-log'.i18n,
          subtitulo: 'settings.view-log-tv-subtitle'.i18n,
          onTap: () => Get.to(() => const RegistroEnVivoPage()),
        ),
        // PrismHub+ va en General y no en Reproducción: no es un ajuste del
        // reproductor, es lo que decide cómo se comporta la app entera en este
        // aparato — el vídeo, las peticiones y las animaciones.
        _Boton(
          icono: Icons.bolt,
          titulo: 'PrismHub+',
          subtitulo: 'settings.mas-subtitulo'.i18n,
          onTap: () => Get.to(() => const PrismHubMasPage()),
        ),
      ];

  List<Widget> _reproductor() => [
        _Interruptor(
          icono: Icons.hd_outlined,
          titulo: 'settings.max-quality'.i18n,
          subtitulo: 'settings.max-quality-subtitle'.i18n,
          clave: SettingKey.empezarEnMaximaCalidad,
          porDefecto: false,
          // En un aparato modesto esto no es una preferencia: es una forma de
          // romper la reproducción. Ver PerfilDeAparato.
          bloqueadoPorque: PerfilDeAparato.puedeExigirMaximaCalidad
              ? null
              : 'settings.max-quality-bloqueada'.i18n,
        ),
        _Interruptor(
          icono: Icons.skip_next_rounded,
          titulo: 'settings.autoplay-next'.i18n,
          subtitulo: 'settings.autoplay-next-subtitle'.i18n,
          clave: SettingKey.autoPlayNext,
          porDefecto: false,
        ),
      ];

  List<Widget> _inicio() => [
        _Nota('settings.zonas-inicio-subtitle'.i18n),
        const SizedBox(height: 12),
        // Mangas queda afuera a propósito: en TV no hay lectura en ninguna
        // zona, así que ofrecer mezclarla en Inicio sería un ajuste que no
        // puede cumplirse.
        for (final zona in const [
          ZonaPrincipal.peliculas,
          ZonaPrincipal.series,
          ZonaPrincipal.anime,
        ])
          Obx(() {
            final elegidas = ZonasPreferidasEnInicio.elegidas;
            // Vacío = todas, que es el comportamiento por defecto.
            final activa = elegidas.isEmpty || elegidas.contains(zona);
            return _FilaTv(
              icono: switch (zona) {
                ZonaPrincipal.peliculas => Icons.movie_outlined,
                ZonaPrincipal.series => Icons.tv_rounded,
                _ => Icons.animation_rounded,
              },
              titulo: switch (zona) {
                ZonaPrincipal.peliculas => 'home.zona-peliculas'.i18n,
                ZonaPrincipal.series => 'home.zona-series'.i18n,
                _ => 'home.zona-anime'.i18n,
              },
              onTap: () => ZonasPreferidasEnInicio.alternar(zona),
              trailing: _Pastilla(activa: activa),
            );
          }),
      ];

  List<Widget> _extensiones() => [
        _Boton(
          icono: Icons.extension_rounded,
          titulo: 'common.extension'.i18n,
          subtitulo: 'settings.extension-subtitle'.i18n,
          onTap: () => Get.to(() => const ExtensionPage()),
        ),
        _Boton(
          icono: Icons.store_rounded,
          titulo: 'common.repo'.i18n,
          subtitulo: 'settings.extension-repo-open'.i18n,
          onTap: () => Get.to(() => const ExtensionRepoPage()),
        ),
      ];

  List<Widget> _adultos() => [
        _Nota('settings.nsfw-subtitle'.i18n),
        const SizedBox(height: 12),
        _Interruptor(
          icono: Icons.explicit_rounded,
          titulo: 'settings.nsfw'.i18n,
          clave: SettingKey.enableNSFW,
          porDefecto: false,
          acento: HomeTheme.accentRed,
          // Al encenderlo aparece el botón de entrar a la zona, que vive en
          // esta misma lista: hay que redibujarla entera, no solo la fila.
          alCambiar: () => setState(() {}),
        ),
        // ── Sin Obx acá, y es el motivo del fallo que se veía ────────────
        //
        // Reportado en vivo con foto en un televisor: en esta pantalla salía
        // el aviso rojo de GetX «improper use of a GetX has been detected».
        //
        // La causa: esto era un `Obx`, pero adentro no leía ninguna variable
        // observable — leía del almacenamiento, que es un valor común. GetX
        // detecta que no tiene nada a lo que suscribirse y protesta, con
        // razón: un `Obx` así nunca se volvería a dibujar solo.
        //
        // El botón de entrar solo aparece con el contenido +18 activado, sin
        // eso la zona no tiene nada que mostrar. Y para que aparezca al
        // encender el interruptor de arriba alcanza con que esta pantalla se
        // redibuje, que es lo que hace `alCambiar`.
        if (PrismHubStorage.getSetting(SettingKey.enableNSFW) == true) ...[
          // ── Se entra por la COMPUERTA, no por la zona ──────────────────
          //
          // Iba directo a `Nsfw18ZonePage`, que es la pantalla de adentro. O
          // sea que en televisor se entraba sin la confirmación de edad y sin
          // el PIN — la puerta estaba puesta y se pasaba por al lado.
          //
          // `Nsfw18ZoneGate` es la que pregunta y pide el PIN antes de dejar
          // ver nada, y es por donde entran PC y teléfono desde siempre.
          _Boton(
            icono: Icons.lock_open_rounded,
            titulo: 'nsfw18.title'.i18n,
            onTap: () => Get.to(() => const Nsfw18ZoneGate()),
            acento: HomeTheme.accentRed,
          ),
          // Y poder ponerlo o cambiarlo, que tampoco estaba.
          //
          // Sin esto, un televisor con el PIN sin configurar no tenía forma de
          // configurarlo: había que hacerlo desde otro aparato. Y con uno
          // puesto, tampoco de cambiarlo.
          _Boton(
            icono: Icons.password_rounded,
            titulo: Nsfw18Zone.isPinConfigured
                ? 'nsfw18.settings-pin-change'.i18n
                : 'nsfw18.settings-pin-set'.i18n,
            subtitulo: Nsfw18Zone.isPinConfigured
                ? 'nsfw18.settings-pin-configured'.i18n
                : 'nsfw18.settings-pin-none'.i18n,
            onTap: () async {
              await abrirDialogoDePin(context);
              if (mounted) setState(() {});
            },
            acento: HomeTheme.accentRed,
          ),
        ],
      ];

  List<Widget> _acercaDe() => [
        _Nota('settings.about-description'.i18n),
        const SizedBox(height: 12),
        // La versión instalada, a la vista.
        //
        // No estaba en televisor. En PC y en teléfono sale debajo de «Buscar
        // actualizaciones», pero acá la fila es de otra clase y se quedó sin
        // ella — así que la única forma de saber qué versión tenía un
        // televisor era abrir el registro y leer la cabecera.
        //
        // Es el primer dato que hace falta al reportar algo, y el primero que
        // hay que preguntar al recibirlo. Con el modo al lado cuando no es una
        // versión publicable, igual que en las otras plataformas: sirve para
        // distinguir la app instalada de una compilación de pruebas.
        _Boton(
          icono: Icons.system_update_rounded,
          titulo: 'settings.upgrade'.i18n,
          subtitulo: ModoApp.versionConModo(packageInfo.version),
          onTap: () => ApplicationUtils.checkUpdate(context, showSnackbar: true),
        ),
      ];

  // ─── Auxiliares ──────────────────────────────────────────────────────

  String _idiomaActual() {
    final v = PrismHubStorage.getSetting(SettingKey.language);
    return v == 'en' ? 'languages.en'.i18n : 'languages.es'.i18n;
  }

  Future<void> _alternarIdioma() async {
    final actual = PrismHubStorage.getSetting(SettingKey.language);
    await PrismHubStorage.setSetting(
      SettingKey.language,
      actual == 'en' ? 'es' : 'en',
    );
    if (mounted) setState(() {});
  }
}

/// Una fila de Ajustes de TV: ícono grande, título, y algo a la derecha.
///
/// Todas las filas de esta pantalla salen de acá para que se vean iguales —
/// mismo alto, mismo ícono, mismo tamaño de texto— sin importar si lo que
/// llevan a la derecha es un interruptor o nada.
class _FilaTv extends StatelessWidget {
  const _FilaTv({
    required this.icono,
    required this.titulo,
    this.subtitulo,
    this.trailing,
    this.onTap,
    this.acento,
  });

  final IconData icono;
  final String titulo;
  final String? subtitulo;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? acento;

  @override
  Widget build(BuildContext context) {
    final color = acento ?? HomeTheme.accentPink;
    final fila = Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
      decoration: BoxDecoration(
        color: HomeTheme.cardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: HomeTheme.border),
      ),
      child: Row(
        children: [
          Icon(icono, size: 26, color: color),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: HomeTheme.textPrimary,
                  ),
                ),
                if (subtitulo != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitulo!,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.35,
                      color: HomeTheme.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 16),
            trailing!,
          ],
        ],
      ),
    );
    // ── La separación entre filas va POR FUERA del marco de foco ────────
    //
    // Estaba como `margin` del Container, o sea DENTRO de lo que enfoca la
    // FocusableCard. El marco se dibujaba entonces alrededor de una caja doce
    // píxeles más alta que la tarjeta que se ve, y desde el sillón eso se lee
    // como que la selección está corrida hacia abajo. Reportado con foto.
    //
    // Con la separación afuera, el marco cae exactamente sobre la tarjeta.
    const separacion = EdgeInsets.only(bottom: 12);
    if (onTap == null) return Padding(padding: separacion, child: fila);
    return Padding(
      padding: separacion,
      child: FocusableCard(
        borderRadius: 14,
        accent: acento,
        onTap: onTap!,
        // El hijo no atiende toques por su cuenta: de eso se encarga la
        // FocusableCard de afuera, que además es la que sabe del foco del
        // mando.
        child: IgnorePointer(child: fila),
      ),
    );
  }
}

/// Una fila que enciende y apaga un ajuste guardado.
///
/// Sin un `Switch` de Material a propósito: ese widget se enfoca SOLO,
/// aparte de la fila que lo contiene, así que con un mando había que pasar
/// dos veces por cada ajuste (una por la fila, otra por el interruptor) y
/// no quedaba claro cuál de los dos respondía al OK. Acá la fila entera es
/// el control: se enfoca una vez y OK la alterna.
class _Interruptor extends StatefulWidget {
  const _Interruptor({
    required this.icono,
    required this.titulo,
    this.subtitulo,
    this.clave,
    this.porDefecto = false,
    this.valorTexto,
    this.onTap,
    this.acento,
    this.alCambiar,
    this.bloqueadoPorque,
  });

  final IconData icono;
  final String titulo;
  final String? subtitulo;

  /// Qué ajuste guarda. Si es null, la fila no alterna nada sola — usa
  /// [onTap] y muestra [valorTexto].
  final String? clave;
  final bool porDefecto;

  /// Para los que no son sí/no (el idioma): lo que se muestra a la derecha.
  final String? valorTexto;
  final VoidCallback? onTap;
  final Color? acento;

  /// Se avisa cuando el valor cambió, para que la pantalla que contiene esta
  /// fila pueda redibujar lo que dependa de él. El `setState` de acá adentro
  /// solo alcanza para la fila misma.
  final VoidCallback? alCambiar;

  /// Si esta fila no se puede tocar en este aparato, POR QUÉ.
  ///
  /// Se muestra en vez del subtítulo y la fila queda apagada. Se prefiere esto
  /// a esconderla: quien viene buscando el ajuste tiene que encontrar la
  /// respuesta, no un hueco donde recordaba que estaba.
  final String? bloqueadoPorque;

  @override
  State<_Interruptor> createState() => _InterruptorState();
}

class _InterruptorState extends State<_Interruptor> {
  bool get _activo {
    final v = PrismHubStorage.getSetting(widget.clave!);
    return v is bool ? v : widget.porDefecto;
  }

  @override
  Widget build(BuildContext context) {
    final bloqueado = widget.bloqueadoPorque != null;
    return _FilaTv(
      icono: widget.icono,
      titulo: widget.titulo,
      subtitulo: widget.bloqueadoPorque ?? widget.subtitulo,
      acento: bloqueado ? HomeTheme.textMuted : widget.acento,
      trailing: bloqueado
          ? Text(
              'settings.no-en-este-aparato'.i18n,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: HomeTheme.textMuted,
              ),
            )
          : widget.valorTexto != null
          ? Text(
              widget.valorTexto!,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: widget.acento ?? HomeTheme.accentPink,
              ),
            )
              : _Pastilla(activa: _activo, acento: widget.acento),
      onTap: bloqueado
          ? null
          : widget.onTap ??
              () async {
                await PrismHubStorage.setSetting(widget.clave!, !_activo);
                if (mounted) setState(() {});
                widget.alCambiar?.call();
              },
    );
  }
}

/// El "encendido/apagado" a la derecha de una fila.
///
/// Una pastilla con texto y no un interruptor dibujado: desde el sillón, un
/// switch chico no se lee —hay que fijarse de qué lado quedó la perilla—
/// mientras que una palabra en color se entiende de un vistazo.
class _Pastilla extends StatelessWidget {
  const _Pastilla({required this.activa, this.acento});

  final bool activa;
  final Color? acento;

  @override
  Widget build(BuildContext context) {
    final color = acento ?? HomeTheme.accentPink;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: activa
            ? color.withValues(alpha: 0.20)
            : Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: activa ? color : HomeTheme.border,
        ),
      ),
      child: Text(
        activa ? 'common.on'.i18n : 'common.off'.i18n,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: activa ? color : HomeTheme.textMuted,
        ),
      ),
    );
  }
}

/// Una fila que lleva a otra pantalla.
class _Boton extends StatelessWidget {
  const _Boton({
    required this.icono,
    required this.titulo,
    this.subtitulo,
    required this.onTap,
    this.acento,
  });

  final IconData icono;
  final String titulo;
  final String? subtitulo;
  final VoidCallback onTap;
  final Color? acento;

  @override
  Widget build(BuildContext context) {
    return _FilaTv(
      icono: icono,
      titulo: titulo,
      subtitulo: subtitulo,
      acento: acento,
      onTap: onTap,
      trailing: Icon(
        Icons.chevron_right_rounded,
        size: 28,
        color: HomeTheme.textMuted,
      ),
    );
  }
}

/// Un texto explicativo, sin ser una fila enfocable.
class _Nota extends StatelessWidget {
  const _Nota(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 15,
          height: 1.4,
          color: HomeTheme.textMuted,
        ),
      ),
    );
  }
}
