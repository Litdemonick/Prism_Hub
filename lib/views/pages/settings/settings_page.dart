import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:prismhub/controllers/home_controller.dart';
import 'package:prismhub/utils/copia_cifrado.dart';
import 'package:prismhub/utils/copia_seguridad.dart';
import 'package:prismhub/views/pages/settings/copia_elegir_extensiones.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:get/get.dart';
import 'package:prismhub/views/pages/nsfw18/nsfw18_age_dialog.dart';
import 'package:prismhub/views/widgets/button.dart';
import 'package:prismhub/views/widgets/messenger.dart';
import 'package:prismhub/data/providers/tmdb_provider.dart';
import 'package:prismhub/utils/log.dart';
import 'package:prismhub/utils/request.dart';
import 'package:prismhub/controllers/extension/extension_repo_controller.dart';
import 'package:prismhub/controllers/settings_controller.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/views/pages/nsfw18/nsfw18_pin_settings_tile.dart';
import 'package:prismhub/views/pages/nsfw18/nsfw18_zone_page.dart';
import 'package:prismhub/views/widgets/settings/settings_expander_tile.dart';
import 'package:prismhub/views/widgets/settings/settings_input_tile.dart';
import 'package:prismhub/views/widgets/settings/settings_radios_tile.dart';
import 'package:prismhub/views/widgets/settings/settings_switch_tile.dart';
import 'package:prismhub/views/widgets/settings/settings_numberbox_button.dart';
import 'package:prismhub/views/widgets/settings/settings_tile.dart';
import 'package:prismhub/utils/i18n.dart';
import 'package:prismhub/utils/prismhub_storage.dart';
import 'package:prismhub/utils/router.dart';
import 'package:prismhub/utils/application.dart';
import 'package:prismhub/views/widgets/home/animated_background_glow.dart';
import 'package:prismhub/views/widgets/home/home_theme.dart';
import 'package:prismhub/views/widgets/list_title.dart';
import 'package:prismhub/views/widgets/platform_widget.dart';
import 'package:share_plus/share_plus.dart';
import 'package:tmdb_api/tmdb_api.dart';
import 'package:url_launcher/url_launcher.dart';

// El repo por defecto se guarda con "https://" adelante — mostrarlo/editarlo
// así en el campo de texto era frágil (había que dejar el prefijo intacto
// para no perder el esquema, y confirmar cada tecla — ver onChanged más
// abajo — disparaba un fetch de red con el valor a medio escribir, lo que se
// veía como el programa "bugueando"). Se muestra/edita solo la parte directa
// (dominio + ruta) y se reconstruye el esquema completo al guardar.
String _stripUrlScheme(String url) =>
    url.replaceFirst(RegExp(r'^https?://'), '');
// Deja SIEMPRE una URL usable. Borrar el campo guardaba una cadena vacía, y
// con eso el app armaba "/index.json" sin host: no cargaba ninguna extensión
// y en pantalla se veía como si no hubiera internet, sin ninguna pista de que
// el problema era este ajuste. Ante cualquier valor que no sirva se vuelve al
// repositorio oficial en vez de dejar el app sin catálogo.
// Pone los controles de a dos por fila solo si el ancho alcanza; si no, uno
// debajo del otro. Un umbral por ancho real y no por plataforma: un celular
// en horizontal sí tiene lugar para dos, y una ventana angosta en escritorio
// no.
Widget _parDeControles(BuildContext context, List<Widget> hijos) {
  final ancho = MediaQuery.sizeOf(context).width;
  if (ancho < 620) {
    return Column(
      children: [
        for (var i = 0; i < hijos.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          hijos[i],
        ],
      ],
    );
  }
  return Row(
    children: [
      for (var i = 0; i < hijos.length; i++) ...[
        if (i > 0) const SizedBox(width: 30),
        Expanded(child: hijos[i]),
      ],
    ],
  );
}

String _sanitizeRepoUrl(String value) {
  final withScheme = _withUrlScheme(value);
  if (withScheme.isEmpty) return PrismHubStorage.defaultRepoUrl;
  final uri = Uri.tryParse(withScheme);
  if (uri == null || !uri.hasAuthority || uri.host.isEmpty) {
    return PrismHubStorage.defaultRepoUrl;
  }
  return withScheme;
}

String _withUrlScheme(String value) {
  final v = value.trim();
  if (v.isEmpty || v.startsWith('http://') || v.startsWith('https://')) {
    return v;
  }
  return 'https://$v';
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late SettingsController c;

  @override
  void initState() {
    c = Get.put(SettingsController());
    super.initState();
  }

  List<Widget> _buildSkipIntervalChildren() {
    return [
      Text("settings.skip-interval".i18n),
      const SizedBox(height: 2),
      Text(
        "settings.skip-interval-subtitle".i18n,
        style: const TextStyle(fontSize: 12),
      ),
      const SizedBox(height: 15),
      Column(
        children: [
          // Dos por fila SOLO si hay ancho. En un celular en vertical
          // cada control quedaba con ~150px y el número se partía en
          // cuatro líneas ("-", "1", "0", "s"). Se decide con el ancho
          // real disponible, así sirve igual en horizontal, donde sí
          // entran dos.
          _parDeControles(context, [
            SettingNumboxButton(
              title: "key I",
              button1text: "1s",
              button2text: "0.1s",
              onChanged: (value) {
                PrismHubStorage.setSetting(SettingKey.keyI, value ??= 10.0);
              },
              numberBoxvalue:
                  PrismHubStorage.getSetting(SettingKey.keyI) ?? 10.0,
            ),
            SettingNumboxButton(
              title: "key J",
              button1text: "1s",
              button2text: "0.1s",
              onChanged: (value) {
                PrismHubStorage.setSetting(SettingKey.keyJ, value ??= -10.0);
              },
              numberBoxvalue:
                  PrismHubStorage.getSetting(SettingKey.keyJ) ?? -10.0,
            ),
          ]),
          const SizedBox(height: 8),
          _parDeControles(context, [
            SettingNumboxButton(
              title: "arrow left",
              icon: const Icon(fluent.FluentIcons.chevron_left_med),
              button1text: "1s",
              button2text: "0.1s",
              numberBoxvalue:
                  PrismHubStorage.getSetting(SettingKey.arrowLeft) ?? -2.0,
              onChanged: (value) {
                PrismHubStorage.setSetting(
                    SettingKey.arrowLeft, value ??= -2.0);
              },
            ),
            SettingNumboxButton(
              title: "arrow right",
              icon: const Icon(fluent.FluentIcons.chevron_right_med),
              button1text: "1s",
              button2text: "0.1s",
              onChanged: (value) {
                PrismHubStorage.setSetting(SettingKey.arrowRight, value ??= 2);
              },
              numberBoxvalue:
                  PrismHubStorage.getSetting(SettingKey.arrowRight) ?? 2.0,
            ),
          ]),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: HomeTheme.accentPink,
              ),
              icon: const Icon(Icons.restart_alt, size: 18),
              label: Text('settings.restore-defaults'.i18n),
              onPressed: () async {
                // Los mismos valores con los que arranca el app (ver
                // PrismHubStorage._initSettings): dejar la lista
                // duplicada acá sería pedir que se desincronicen, pero
                // no hay un punto único todavía — al menos quedan los
                // dos lugares señalados entre sí.
                await PrismHubStorage.setSetting(SettingKey.keyI, 10.0);
                await PrismHubStorage.setSetting(SettingKey.keyJ, -10.0);
                await PrismHubStorage.setSetting(SettingKey.arrowLeft, -2.0);
                await PrismHubStorage.setSetting(SettingKey.arrowRight, 2.0);
                if (!context.mounted) return;
                setState(() {});
                showPlatformSnackbar(
                  context: context,
                  content: 'settings.restore-defaults-done'.i18n,
                );
              },
            ),
          ),
        ],
      ),
    ];
  }

  /// Pide la clave de la copia. Null si el usuario cancela.
  ///
  /// Al exportar se pide dos veces: una clave mal escrita en una copia que se
  /// guarda hoy y se usa dentro de un año es un archivo perdido para siempre,
  /// porque no hay forma de recuperarla — el archivo no la guarda, solo permite
  /// comprobar si la que se escribe es la correcta.
  Future<_DatosDeCopia?> _pedirClave(
    BuildContext context, {
    required bool alExportar,
    String? nombrePropuesto,
    int? numero,
    String? deQuien,
  }) async {
    // Se espera el resultado y se comprueba el VALOR, en vez de forzar el tipo
    // del Future.
    //
    // showPlatformDialog no declara qué devuelve, así que devuelve
    // Future<dynamic>, y `... as Future<_DatosDeCopia?>` revienta en tiempo de
    // ejecución: Future<dynamic> no es un Future<_DatosDeCopia?>. Como esta
    // llamada queda fuera del try de quien exporta, el error se perdía y el
    // botón de exportar parecía no hacer nada.
    final resultado = await showPlatformDialog(
      context: context,
      title: (alExportar
              ? 'settings.backup-key-title-export'
              : 'settings.backup-key-title-import')
          .i18n,
      maxWidth: 420,
      content: _DialogoClave(
        alExportar: alExportar,
        nombrePropuesto: nombrePropuesto,
        numero: numero,
        deQuien: deQuien,
      ),
      actions: null,
    );
    // Cerrar el diálogo por fuera (tocar afuera, Escape) devuelve null.
    return resultado is _DatosDeCopia ? resultado : null;
  }

  /// Deja el historial y la lista en un archivo que el usuario pueda guardar.
  ///
  /// Dos caminos porque son dos formas distintas de manejar archivos: en Android
  /// se comparte —que es como sale cualquier archivo de una app ahí, y deja
  /// elegir Drive, WhatsApp o la carpeta que sea— y en PC se elige dónde
  /// guardarlo. El archivo que sale es el MISMO en las tres plataformas, así que
  /// se puede exportar en el teléfono e importar en la PC o al revés.
  Future<void> _exportarCopia(BuildContext context) async {
    // Cuál copia va a ser y con qué nombre se guardó la anterior. La primera
    // vez no hay nada de esto y el diálogo lo dice de otra forma.
    final hechas = (PrismHubStorage.getSetting(SettingKey.copiasHechas) as int?) ?? 0;
    final ultimoNombre =
        PrismHubStorage.getSetting(SettingKey.nombreDeCopia) as String?;

    final datos = await _pedirClave(
      context,
      alExportar: true,
      nombrePropuesto: ultimoNombre,
      numero: hechas + 1,
    );
    if (datos == null || !context.mounted) return;

    // Qué se guarda: todo, o solo algunas extensiones.
    //
    // Misma pantalla que al importar, para que sea la misma idea en los dos
    // lados. Vienen todas marcadas, que es el caso normal —una copia de
    // respaldo se hace entera—, y el que quiere pasarle solo una parte a
    // alguien puede desmarcar.
    final resumen = await CopiaSeguridad.resumenLocal();
    if (!context.mounted) return;
    if (resumen.paquetes.isEmpty) {
      showPlatformSnackbar(
        context: context,
        title: 'settings.backup-export-failed'.i18n,
        content: 'settings.backup-nothing'.i18n,
      );
      return;
    }
    final queExportar = await showPlatformDialog(
      context: context,
      title: 'settings.backup-pick-title-export'.i18n,
      maxWidth: 520,
      content: CopiaElegirExtensiones(copia: resumen, alExportar: true),
      actions: null,
      // El contenido ya trae su propia lista desplazable.
      scrollable: false,
    );
    if (queExportar is! Set<String> || queExportar.isEmpty) return;
    if (!context.mounted) return;

    // La rueda mientras cifra.
    //
    // Cifrar tarda a propósito —150.000 vueltas de PBKDF2— y hasta ahora eso
    // pasaba sin ninguna señal: se tocaba Exportar y no se veía nada hasta que
    // aparecía el selector de carpeta. Parecía que el botón no había hecho nada
    // y se tocaba otra vez.
    var ruedaAbierta = true;
    unawaited(showPlatformDialog(
      context: context,
      title: 'settings.backup-export'.i18n,
      content: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor:
                    AlwaysStoppedAnimation<Color>(HomeTheme.accentPink),
              ),
            ),
            const SizedBox(width: 16),
            Flexible(child: Text('settings.backup-export-working'.i18n)),
          ],
        ),
      ),
      actions: null,
      maxWidth: 360,
      barrierDismissible: false,
    ));
    // Un respiro para que la rueda llegue a dibujarse antes de arrancar.
    await Future<void>.delayed(const Duration(milliseconds: 16));

    try {
      final numero = hechas + 1;
      final contenido = await CopiaSeguridad.exportar(
        datos.clave,
        nombre: datos.nombre,
        numero: numero,
        paquetes: queExportar,
      );
      // Se cierra ANTES del selector de carpeta: dos ventanas encima de la otra
      // dejan la de abajo tapando la del sistema en Windows.
      if (ruedaAbierta) {
        RouterUtils.pop();
        ruedaAbierta = false;
      }
      if (!context.mounted) return;
      // El número va en el nombre del archivo además de adentro: es lo que se
      // ve en la carpeta sin abrir nada.
      final nombreArchivo = 'PrismHub-${_paraNombreDeArchivo(datos.nombre)}'
          '-$numero-${DateTime.now().toIso8601String().substring(0, 10)}.json';

      var guardado = false;
      if (Platform.isAndroid) {
        // Por un archivo temporal: compartir necesita algo en disco, y la
        // carpeta de caché es la que el sistema deja compartir sin permisos.
        final archivo = File(
            '${(await getTemporaryDirectory()).path}${Platform.pathSeparator}$nombreArchivo');
        await archivo.writeAsString(contenido);
        final r = await Share.shareXFiles([XFile(archivo.path)]);
        // Solo cuenta si de verdad se compartió. Cerrar la hoja de compartir
        // sin elegir nada no es una copia hecha, y contarla dejaría un hueco
        // en la numeración.
        guardado = r.status != ShareResultStatus.dismissed;
      } else {
        final destino = await FilePicker.platform.saveFile(
          type: FileType.custom,
          allowedExtensions: ['json'],
          fileName: nombreArchivo,
        );
        // Sin destino es que canceló, que no es un error.
        if (destino == null) return;
        await File(destino).writeAsString(contenido);
        guardado = true;
      }

      if (!guardado) return;
      // La cuenta sube SOLO si de verdad se guardó: si cancela el selector, la
      // próxima tiene que volver a ser la misma copia y no un hueco.
      await PrismHubStorage.setSetting(SettingKey.copiasHechas, numero);
      await PrismHubStorage.setSetting(
          SettingKey.nombreDeCopia, datos.nombre);
      if (!context.mounted) return;
      showPlatformSnackbar(
        context: context,
        title: 'settings.backup-export-done'.i18n,
        content: FlutterI18n.translate(context, 'settings.backup-export-info',
            translationParams: {'nombre': datos.nombre, 'n': '$numero'}),
      );
    } catch (e) {
      logger.warning('No se pudo exportar la copia', e);
      if (!context.mounted) return;
      showPlatformSnackbar(
        context: context,
        title: 'settings.backup-export-failed'.i18n,
        content: e.toString(),
      );
    } finally {
      // Pase lo que pase. Si algo falla con la rueda abierta, queda una ventana
      // sin botones y la app trabada sin forma de salir.
      if (ruedaAbierta) RouterUtils.pop();
    }
  }

  /// Deja el nombre en algo que pueda ser parte de un nombre de archivo.
  ///
  /// Los tres sistemas prohíben caracteres distintos y Android además no deja
  /// nada que parezca una ruta. Se queda con letras, números, guiones y puntos,
  /// que es lo que acepta cualquiera de los tres.
  String _paraNombreDeArchivo(String nombre) {
    final s = nombre
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    if (s.isEmpty) return 'copia';
    return s.length > 24 ? s.substring(0, 24) : s;
  }

  /// Vuelve a leer lo que hay en pantalla después de importar.
  ///
  /// El inicio y el historial ya están dibujados con lo de ANTES: sin esto el
  /// usuario ve "listo" y abajo sus datos viejos, y parece que no pasó nada.
  /// Se refrescan los dos inicios —el normal y el de la Zona +18— porque la
  /// copia trae los dos.
  Future<void> _refrescarTrasImportar() async {
    try {
      await HomePageController.refreshAll();
    } catch (e) {
      // Que no se pueda refrescar no invalida la importación: los datos ya
      // están guardados y se van a ver igual al volver a entrar.
      logger.info('No se pudo refrescar el inicio tras importar: $e');
    }
  }

  /// Mete de vuelta lo que traiga un archivo, juntándolo con lo que ya hay.
  Future<void> _importarCopia(BuildContext context) async {
    try {
      // En Android NO se filtra por extensión.
      //
      // Ahí el selector es el del sistema y filtra por tipo MIME, no por cómo
      // termina el nombre. Un mismo .json llega como application/json desde una
      // carpeta, como text/plain desde otra y como application/octet-stream
      // desde Drive o WhatsApp: con el filtro puesto, el archivo aparece en gris
      // y no se puede elegir, y desde afuera se ve como que la copia "no está".
      //
      // Que se pueda elegir cualquier archivo no abre ningún agujero: lo que
      // decide si sirve es leerlo (ver leerSobre), que rechaza lo que no sea una
      // copia de PrismHub antes de tocar nada.
      final elegido = await FilePicker.platform.pickFiles(
        type: Platform.isAndroid ? FileType.any : FileType.custom,
        allowedExtensions: Platform.isAndroid ? null : ['json'],
        // En Android hace falta el contenido: la ruta que devuelve el selector
        // puede ser de un proveedor (Drive, Descargas) que no se puede abrir
        // como archivo normal.
        withData: Platform.isAndroid,
      );
      final archivo = elegido?.files.firstOrNull;
      if (archivo == null) return;

      // Techo de tamaño ANTES de leerlo.
      //
      // En Android el archivo se carga entero en memoria, así que elegir un
      // vídeo por error tumbaría la app antes de poder decir que no sirve. Una
      // copia de historial y favoritos son unos pocos megas incluso con miles de
      // títulos, así que 25 MB deja muchísimo margen.
      const techo = 25 * 1024 * 1024;
      if (archivo.size > techo) {
        if (!context.mounted) return;
        showPlatformSnackbar(
          context: context,
          title: 'settings.backup-import-failed'.i18n,
          content: 'settings.backup-too-big'.i18n,
        );
        return;
      }

      final datos = archivo.bytes;
      final contenido = datos != null
          ? utf8.decode(datos, allowMalformed: true)
          : await File(archivo.path!).readAsString();

      // Se mira de qué copia es ANTES de pedir nada: así el diálogo de la clave
      // puede decir de qué equipo salió y cuál número es, y un archivo que no
      // sirve se rechaza sin hacer escribir una clave para nada.
      final quienEs = CopiaSeguridad.leerSobre(contenido);

      if (!context.mounted) return;
      // La clave se pide DESPUÉS de elegir el archivo: al revés se escribiría
      // una clave para después cancelar el selector.
      final datosClave = await _pedirClave(
        context,
        alExportar: false,
        deQuien: quienEs.etiqueta,
      );
      if (datosClave == null || !context.mounted) return;

      // Se abre y se cuenta qué trae, SIN escribir nada todavía.
      //
      // Con su rueda: descifrar tarda lo mismo que cifrar, y sin señal se veía
      // como que escribir la clave no había hecho nada.
      var abriendo = true;
      unawaited(showPlatformDialog(
        context: context,
        title: 'settings.backup-import-action'.i18n,
        content: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(HomeTheme.accentPink),
                ),
              ),
              const SizedBox(width: 16),
              Flexible(child: Text('settings.backup-opening'.i18n)),
            ],
          ),
        ),
        actions: null,
        maxWidth: 360,
        barrierDismissible: false,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 16));

      final CopiaAbierta copia;
      try {
        copia = await CopiaSeguridad.abrir(contenido, datosClave.clave);
      } finally {
        // En finally: con la clave equivocada esto lanza, y sin cerrarla la
        // rueda quedaba girando para siempre sobre un error que nadie ve.
        if (abriendo) {
          RouterUtils.pop();
          abriendo = false;
        }
      }
      if (!context.mounted) return;

      if (copia.paquetes.isEmpty) {
        showPlatformSnackbar(
          context: context,
          title: 'settings.backup-import-failed'.i18n,
          content: 'settings.backup-pick-empty'.i18n,
        );
        return;
      }

      // Se elige qué extensiones pasar. Lo que no está listo en este equipo no
      // se puede elegir y se dice por qué (ver CopiaElegirExtensiones).
      final elegidas = await showPlatformDialog(
        context: context,
        title: 'settings.backup-pick-title'.i18n,
        maxWidth: 520,
        content: CopiaElegirExtensiones(copia: copia),
        actions: null,
        // El contenido ya tiene su propia lista desplazable: dos scrolls
        // anidados se pelean el gesto y el de afuera no puede pasar de largo.
        scrollable: false,
      );
      if (elegidas is! Set<String> || elegidas.isEmpty) return;
      if (!context.mounted) return;

      // Contenido +18 con la Zona +18 apagada.
      //
      // Entra igual —no se toca lo que el usuario eligió— pero no lo va a ver
      // por ningún lado hasta que la encienda. Decirlo después de importar
      // sería dejarlo buscando dónde quedó lo que acaba de recuperar.
      final cuantoNsfw = copia.nsfwDe(elegidas);
      if (cuantoNsfw > 0 &&
          PrismHubStorage.getSetting(SettingKey.enableNSFW) != true) {
        final sigue = await showPlatformDialog(
          context: context,
          title: 'settings.backup-nsfw-title'.i18n,
          maxWidth: 420,
          content: Text(
            FlutterI18n.translate(context, 'settings.backup-nsfw-body',
                translationParams: {'n': '$cuantoNsfw'}),
            style: const TextStyle(fontSize: 13, height: 1.45),
          ),
          actions: [
            PlatformTextButton(
              onPressed: () => RouterUtils.pop(false),
              child: Text('common.cancel'.i18n),
            ),
            PlatformFilledButton(
              onPressed: () => RouterUtils.pop(true),
              child: Text('settings.backup-import-action'.i18n),
            ),
          ],
        );
        if (sigue != true || !context.mounted) return;
      }

      // La barra de progreso, mientras entra. Una copia grande son cientos de
      // registros y cada uno toca la base: sin esto la pantalla se queda quieta
      // y parece colgada.
      final progreso = ValueNotifier<double>(0);
      unawaited(showPlatformDialog(
        context: context,
        title: 'settings.backup-import-working'.i18n,
        content: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: _BarraDeImportacion(progreso: progreso),
        ),
        actions: null,
        maxWidth: 380,
        barrierDismissible: false,
      ));
      await Future<void>.delayed(Duration.zero);

      ResultadoImportacion r;
      try {
        r = await CopiaSeguridad.importar(
          contenido,
          datosClave.clave,
          // Ya descifrada: volver a hacerlo serían 150.000 vueltas de PBKDF2
          // regaladas, o sea un segundo de espera de más.
          yaAbierta: copia,
          paquetes: elegidas,
          onProgreso: (p) => progreso.value = p,
        );
      } finally {
        // El diálogo se cierra pase lo que pase: con un fallo, dejarlo abierto
        // sin botones deja la app trabada sin forma de salir.
        RouterUtils.pop();
        progreso.dispose();
      }
      if (!context.mounted) return;

      // Lo que entró, en números: decir solo "listo" deja al usuario sin saber
      // si de verdad se recuperó algo o el archivo estaba vacío.
      final partes = <String>[
        // Cuántas extensiones entraron de las que traía la copia: "3 de 5".
        // Sin esto, el que dejó dos afuera por no tenerlas instaladas no tiene
        // forma de recordar después que le faltan.
        FlutterI18n.translate(context, 'settings.backup-import-exts',
            translationParams: {
              'n': '${elegidas.length}',
              'total': '${copia.paquetes.length}',
            }),
        FlutterI18n.translate(context, 'settings.backup-import-counts',
            translationParams: {
              'historial': '${r.historialNuevo + r.historialActualizado}',
              'favoritos': '${r.favoritosNuevos}',
            }),
        if (r.fallidos > 0)
          FlutterI18n.translate(context, 'settings.backup-import-failed-items',
              translationParams: {'n': '${r.fallidos}'}),
        if (r.extensionesFaltantes.isNotEmpty)
          FlutterI18n.translate(context, 'settings.backup-import-missing',
              translationParams: {
                'extensiones': r.extensionesFaltantes.join(', ')
              }),
      ];

      // Se recarga lo que está en pantalla y se avisa de dónde vino.
      //
      // El inicio y el historial ya están dibujados con lo de antes de importar:
      // sin refrescarlos, el usuario ve el mensaje de "listo" y abajo sus datos
      // viejos, y parece que no pasó nada.
      await _refrescarTrasImportar();
      if (!context.mounted) return;
      showPlatformSnackbar(
        context: context,
        title: FlutterI18n.translate(context, 'settings.backup-import-from',
            translationParams: {'nombre': r.deQuien.etiqueta}),
        content: partes.join('\n'),
      );
    } on CopiaInvalida catch (e) {
      // El archivo no sirve, y sabemos por qué: se dice tal cual en vez de
      // volcarle una excepción al usuario.
      if (!context.mounted) return;
      showPlatformSnackbar(
        context: context,
        title: 'settings.backup-import-failed'.i18n,
        content: e.motivo,
      );
    } catch (e) {
      logger.warning('No se pudo importar la copia', e);
      if (!context.mounted) return;
      showPlatformSnackbar(
        context: context,
        title: 'settings.backup-import-failed'.i18n,
        content: e.toString(),
      );
    }
  }

  Widget _buildSkipIntervalContent() {
    // En celular NO hay teclado: el unico atajo de salto es el doble toque a
    // izquierda o derecha, asi que mostrar "key I", "key J" y las flechas era
    // ofrecer cuatro ajustes de los que dos no hacen absolutamente nada. Se
    // muestran solo los dos que el doble toque usa de verdad, con nombres que
    // dicen que gesto configuran.
    if (Platform.isAndroid) return _buildSkipIntervalMobile();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _buildSkipIntervalChildren(),
    );
  }

  Widget _skipCard(String etiqueta, IconData icono, String key, double porDef) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: HomeTheme.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: HomeTheme.border),
      ),
      child: Row(
        children: [
          Icon(icono, color: HomeTheme.accentPink, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              etiqueta,
              style:
                  const TextStyle(color: HomeTheme.textPrimary, fontSize: 14),
            ),
          ),
          _MobileStepper(settingKey: key, fallback: porDef),
        ],
      ),
    );
  }

  Widget _buildSkipIntervalMobile() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // La explicacion va en su propia tarjeta, no como parrafo suelto.
        Container(
          padding: const EdgeInsets.all(14),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: HomeTheme.accentPink.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
            border:
                Border.all(color: HomeTheme.accentPink.withValues(alpha: 0.45)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.touch_app,
                  color: HomeTheme.accentPink, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'settings.skip-interval-mobile-help'.i18n,
                  style: const TextStyle(
                      color: HomeTheme.textMuted, fontSize: 13, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        _skipCard('settings.skip-back'.i18n, Icons.fast_rewind,
            SettingKey.arrowLeft, -2.0),
        _skipCard('settings.skip-forward'.i18n, Icons.fast_forward,
            SettingKey.arrowRight, 2.0),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: HomeTheme.accentPink),
            icon: const Icon(Icons.restart_alt, size: 18),
            label: Text('settings.restore-defaults'.i18n),
            onPressed: () async {
              await PrismHubStorage.setSetting(SettingKey.arrowLeft, -2.0);
              await PrismHubStorage.setSetting(SettingKey.arrowRight, 2.0);
              if (!context.mounted) return;
              setState(() {});
              showPlatformSnackbar(
                context: context,
                content: 'settings.restore-defaults-done'.i18n,
              );
            },
          ),
        ),
      ],
    );
  }

  // Navigator directo y NO Get.to: esta página se abre DESDE otra que ya se
  // empujó con Get.to (la subpágina de "Reproductor de vídeo" en Android), y
  // ahí el segundo Get.to no navegaba — mismo problema que ya habíamos visto
  // con la página del PIN de la zona +18, resuelto igual.
  void _openSkipIntervalPage(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: HomeTheme.bg,
          appBar: AppBar(
            backgroundColor: HomeTheme.bg,
            title: Text(
              'settings.skip-interval'.i18n,
              style: const TextStyle(color: HomeTheme.textPrimary),
            ),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: StatefulBuilder(
              // StatefulBuilder propio: esta página vive fuera del árbol de
              // Ajustes, así que el setState de allá no la alcanza — sin esto
              // el botón de restablecer no refrescaba los números.
              builder: (context, _) => _buildSkipIntervalContent(),
            ),
          ),
        ),
      ),
    );
  }

  void _mostrarAvisoLegal() {
    showPlatformDialog(
      context: context,
      title: 'settings.legal'.i18n,
      maxWidth: 520,
      content: Text(
        'settings.legal-body'.i18n,
        style: const TextStyle(
          color: HomeTheme.textMuted,
          fontSize: 13,
          height: 1.5,
        ),
      ),
      actions: [
        Builder(
          builder: (ctx) => PlatformFilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('common.confirm'.i18n),
          ),
        ),
      ],
    );
  }

  // Fila con botón para un enlace del proyecto. Un solo lugar para las tres,
  // que sólo cambian en icono, textos y URL.
  Widget _enlaceTile({
    required IconData androidIcon,
    required IconData desktopIcon,
    required String titulo,
    required String subtitulo,
    required String url,
  }) {
    void abrir() => launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication,
        );
    return SettingsTile(
      isCard: true,
      icon: PlatformWidget(
        androidWidget: Icon(androidIcon),
        desktopWidget: Icon(desktopIcon, size: 24),
      ),
      title: titulo,
      buildSubtitle: () => subtitulo,
      trailing: PlatformWidget(
        androidWidget: TextButton(
          onPressed: abrir,
          child: Text('settings.open'.i18n),
        ),
        desktopWidget: fluent.FilledButton(
          onPressed: abrir,
          child: Text('settings.open'.i18n),
        ),
      ),
      onTap: abrir,
    );
  }

  void _abrirSugerencias() {
    launchUrl(
      Uri.parse('https://github.com/Litdemonick/Prism_Hub/issues'),
      mode: LaunchMode.externalApplication,
    );
  }

  List<Widget> _buildContent() {
    return [
      if (!Platform.isAndroid) ...[
        Text(
          'common.settings'.i18n,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: HomeTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 16),
      ],
      // 常规设置
      SettingsExpanderTile(
        icon: fluent.FluentIcons.developer_tools,
        androidIcon: Icons.construction,
        title: 'settings.general'.i18n,
        // En celular la entrada a la Zona +18 vive DENTRO de General (en
        // escritorio está en el panel lateral), así que el subtítulo lo dice
        // solo ahí — si no, mandaría a buscar algo que en PC no está acá.
        subTitle: Platform.isAndroid
            ? 'settings.general-subtitle-android'.i18n
            : 'settings.general-subtitle'.i18n,
        content: Column(
          children: [
            // TMDB KEY 设置
            SettingsIntpuTile(
              title: 'settings.tmdb-key'.i18n,
              buildSubtitle: () {
                if (!Platform.isAndroid) {
                  return 'settings.tmdb-key-subtitle'.i18n;
                }
                final key =
                    PrismHubStorage.getSetting(SettingKey.tmdbKey) as String;
                if (key.isEmpty) {
                  return 'common.unset'.i18n;
                }
                // 替换为*号
                return key.replaceAll(RegExp(r"."), '*');
              },
              onChanged: (value) {
                PrismHubStorage.setSetting(SettingKey.tmdbKey, value);
                TmdbApi.tmdb = TMDB(
                  ApiKeys(value, ''),
                  defaultLanguage:
                      PrismHubStorage.getSetting(SettingKey.language),
                );
              },
              buildText: () {
                return PrismHubStorage.getSetting(SettingKey.tmdbKey);
              },
            ),
            // 语言设置
            SettingsRadiosTile(
              title: 'settings.language'.i18n,
              itemNameValue: {
                'languages.en'.i18n: 'en',
                'languages.es'.i18n: 'es',
              },
              buildSubtitle: () => 'settings.language-subtitle'.i18n,
              applyValue: (value) {
                PrismHubStorage.setSetting(SettingKey.language, value);
                I18nUtils.changeLanguage(value);
              },
              buildGroupValue: () {
                // Validado, no crudo: si quedó guardado un idioma que ya no
                // existe, esto devuelve el de respaldo y el selector marca
                // algo, en vez de quedar sin ninguna opción elegida.
                return I18nUtils.currentLanguageCode;
              },
            ),
            // 启动检查更新
            SettingsSwitchTile(
              title: 'settings.auto-check-update'.i18n,
              buildSubtitle: () => 'settings.auto-check-update-subtitle'.i18n,
              buildValue: () =>
                  PrismHubStorage.getSetting(SettingKey.autoCheckUpdate),
              onChanged: (value) async {
                // Encender no necesita permiso de nadie.
                if (value) {
                  await PrismHubStorage.setSetting(
                      SettingKey.autoCheckUpdate, true);
                  // `mounted` del State (no context.mounted): esto vive
                  // dentro de _SettingsPageState, y es el chequeo que
                  // corresponde despues de un await.
                  if (mounted) {
                    ApplicationUtils.iniciarChequeoPeriodico(context);
                  }
                  return;
                }
                // Apagar sí: se deja de recibir correcciones y, cuando los
                // sitios cambien, las extensiones van a fallar sin que se
                // entienda por que. Es el tipo de ajuste que conviene no
                // desactivar de un toque sin querer.
                final seguro = await showPlatformDialog(
                  context: context,
                  title: 'settings.auto-check-update-off-title'.i18n,
                  content: Text('settings.auto-check-update-off-body'.i18n),
                  actions: [
                    PlatformTextButton(
                      onPressed: () => RouterUtils.pop(false),
                      child: Text('common.cancel'.i18n),
                    ),
                    PlatformFilledButton(
                      onPressed: () => RouterUtils.pop(true),
                      child: Text('settings.auto-check-update-off-confirm'.i18n),
                    ),
                  ],
                );
                if (seguro != true) return;
                await PrismHubStorage.setSetting(
                    SettingKey.autoCheckUpdate, false);
                ApplicationUtils.detenerChequeoPeriodico();
              },
            ),
            SettingsSwitchTile(
              title: 'settings.check-new-episodes'.i18n,
              buildSubtitle: () => 'settings.check-new-episodes-subtitle'.i18n,
              buildValue: () =>
                  PrismHubStorage.getSetting(SettingKey.checkNewEpisodes) !=
                  false,
              onChanged: (value) {
                PrismHubStorage.setSetting(SettingKey.checkNewEpisodes, value);
              },
            ),
            // Apagado por defecto (== true, no != false): que el reproductor
            // siga solo es algo que se pide, no algo que deba pasar sin avisar.
            // Apagado por defecto: arranca alrededor de 1080p. No es un tope
            // — el menu de calidades del reproductor sigue ofreciendo todo.
            SettingsSwitchTile(
              title: 'settings.max-quality'.i18n,
              buildSubtitle: () => 'settings.max-quality-subtitle'.i18n,
              buildValue: () =>
                  PrismHubStorage.getSetting(
                          SettingKey.empezarEnMaximaCalidad) ==
                      true,
              onChanged: (value) {
                PrismHubStorage.setSetting(
                    SettingKey.empezarEnMaximaCalidad, value);
              },
            ),
            SettingsSwitchTile(
              title: 'settings.autoplay-next'.i18n,
              buildSubtitle: () => 'settings.autoplay-next-subtitle'.i18n,
              buildValue: () =>
                  PrismHubStorage.getSetting(SettingKey.autoPlayNext) == true,
              onChanged: (value) {
                PrismHubStorage.setSetting(SettingKey.autoPlayNext, value);
              },
            ),
            // NSFW
            SettingsSwitchTile(
              title: 'settings.nsfw'.i18n,
              buildSubtitle: () => "settings.nsfw-subtitle".i18n,
              buildValue: () {
                return PrismHubStorage.getSetting(SettingKey.enableNSFW);
              },
              onChanged: (value) async {
                // Al ACTIVAR se pide confirmar la mayoría de edad con la fecha
                // de nacimiento, una sola vez por instalación. Si cancela o no
                // llega a la edad, el interruptor no se mueve.
                if (value && !await Nsfw18AgeDialog.confirmar(context)) {
                  // mounted: el dialogo de edad espera al usuario, y en ese
                  // rato la pantalla de ajustes puede irse (atras, cambio de
                  // pestaña). setState sobre un widget ya desmontado tira
                  // "setState() called after dispose()".
                  if (!mounted) return;
                  setState(() {});
                  return;
                }
                await PrismHubStorage.setSetting(SettingKey.enableNSFW, value);
                if (!value) {
                  // Al APAGAR: cualquier extensión +18 que estuviera activa se
                  // desactiva, porque si no seguiría funcionando pese a que el
                  // ajuste que la habilitaba ya no está. Se anota CUÁLES se
                  // tocaron, para no confundirlas con las que el usuario había
                  // apagado a propósito antes.
                  final apagadas = <String>[];
                  for (final entry in ExtensionUtils.runtimes.entries) {
                    if (entry.value.extension.nsfw &&
                        ExtensionUtils.isEnabled(entry.key)) {
                      ExtensionUtils.setExtensionEnabled(entry.key, false);
                      apagadas.add(entry.key);
                    }
                  }
                  await PrismHubStorage.setSetting(
                      SettingKey.nsfw18AutoDisabled, apagadas.join(','));
                  return;
                }
                // Al ENCENDER: se devuelven a como estaban. Antes esto no se
                // hacía y había que volver a activarlas una por una desde
                // Extensiones instaladas, sin ninguna pista de por qué habían
                // quedado apagadas.
                final guardadas =
                    PrismHubStorage.getSetting(SettingKey.nsfw18AutoDisabled);
                if (guardadas is! String || guardadas.isEmpty) return;
                for (final pkg in guardadas.split(',')) {
                  if (pkg.isEmpty) continue;
                  // Solo las que siguen instaladas: una desinstalada de por
                  // medio no debe reaparecer ni dar error.
                  if (!ExtensionUtils.runtimes.containsKey(pkg)) continue;
                  ExtensionUtils.setExtensionEnabled(pkg, true);
                }
                await PrismHubStorage.setSetting(
                    SettingKey.nsfw18AutoDisabled, '');
              },
            ),
            // Desktop ya tiene su propia entrada discreta en el panel de
            // navegación (footerItems, ver main_page.dart) — acá solo hace
            // falta en Android, que no tiene ese panel.
            if (Platform.isAndroid)
              SettingsTile(
                icon: const Icon(Icons.warning_amber_rounded,
                    color: Color(0xFFE5484D)),
                title: 'nsfw18.menu-label'.i18n,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Get.to(const Nsfw18ZoneGate()),
              ),
            const Nsfw18PinSettingsTile(),
          ],
        ),
      ),
      const SizedBox(height: 10),
      // 扩展仓库
      SettingsExpanderTile(
        icon: fluent.FluentIcons.repo,
        androidIcon: Icons.extension,
        title: 'settings.extension'.i18n,
        subTitle: 'settings.extension-subtitle'.i18n,
        content: Column(
          children: [
            SettingsIntpuTile(
              title: 'settings.repo-url'.i18n,
              // Bloqueado, igual que el proxy. Vaciarlo o escribir cualquier
              // cosa dejaba al app sin catálogo y el síntoma en pantalla era
              // "no hay internet", sin ninguna pista de que el problema era
              // este campo. El repositorio oficial es el único soportado; si
              // alguna vez hace falta cambiarlo, se desbloquea acá.
              enabled: false,
              buildSubtitle: () {
                if (!Platform.isAndroid) {
                  return 'settings.repo-url-subtitle'.i18n;
                }
                return _stripUrlScheme(
                    PrismHubStorage.getSetting(SettingKey.prismhubRepoUrl));
              },
              onChanged: (value) {
                final sane = _sanitizeRepoUrl(value);
                PrismHubStorage.setSetting(SettingKey.prismhubRepoUrl, sane);
                // Si lo que escribió no servía, se avisa: cambiar el ajuste y
                // que calladamente quede otro valor sería peor que el error.
                if (sane != _withUrlScheme(value)) {
                  showPlatformSnackbar(
                    context: context,
                    content: 'settings.repo-url-restored'.i18n,
                  );
                }
                Get.find<ExtensionRepoPageController>().onRefresh();
              },
              buildText: () {
                return _stripUrlScheme(
                    PrismHubStorage.getSetting(SettingKey.prismhubRepoUrl));
              },
            ),
            const SizedBox(height: 8),
            // Solo informativo (no editable) — el repo por defecto es el
            // oficial de prism-plus; las extensiones que vienen firmadas
            // desde ahí se marcan como "PrismPlus" en el listado (ver
            // extension_card.dart).
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'settings.repo-official-note'.i18n,
                style:
                    const TextStyle(fontSize: 12, color: HomeTheme.textMuted),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
      const SizedBox(height: 10),
      // 视频播放器
      SettingsExpanderTile(
        icon: fluent.FluentIcons.play,
        androidIcon: Icons.play_arrow,
        title: 'settings.video-player'.i18n,
        subTitle: 'settings.video-player-subtitle'.i18n,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Servidor BT desactivado a pedido explícito — la entrada de
            // Ajustes se saca de la UI (el código de BTServerUtils sigue
            // existiendo, solo que ya no hay forma de instalarlo/arrancarlo
            // desde acá, y MainController tampoco lo arranca al abrir).
            // Reproductor externo bloqueado a pedido explícito: por ahora
            // toda la app (PC y celular) usa solo el reproductor
            // incorporado. Se deja la opción a la vista pero no editable —
            // el valor ya se fuerza a "built-in" al iniciar (ver
            // prismhub_storage.dart).
            SettingsRadiosTile(
              title: 'settings.external-player'.i18n,
              enabled: false,
              itemNameValue: {
                "settings.external-player-builtin".i18n: "built-in",
              },
              buildSubtitle: () =>
                  'settings.external-player-locked-subtitle'.i18n,
              applyValue: (value) {
                PrismHubStorage.setSetting(SettingKey.videoPlayer, value);
              },
              buildGroupValue: () {
                return PrismHubStorage.getSetting(SettingKey.videoPlayer);
              },
            ),
            const SizedBox(height: 10),
            const SizedBox(height: 10),
            // En celular esto va detrás de un botón: los cuatro controles más
            // su explicación ocupaban media pantalla de texto plano dentro de
            // una lista de ajustes. En escritorio hay ancho de sobra, así que
            // se deja a la vista.
            if (Platform.isAndroid)
              _SkipIntervalTile(onOpen: _openSkipIntervalPage)
            else
              ..._buildSkipIntervalChildren(),
          ],
        ),
      ),
      // Sección de sincronización (AniList) desactivada a pedido explícito
      // para esta release — se saca entera de la UI en vez de dejarla
      // visible pero rota. El código de tracking sigue intacto
      // (AniListTrackingPage, la ruta /settings/anilist, el
      // TrackingPageController), así que volver a mostrarla es solo
      // devolver este bloque.
      const SizedBox(height: 20),
      // 高级
      ListTitle(title: 'settings.advanced'.i18n),
      const SizedBox(height: 20),
      // 网络设置
      SettingsExpanderTile(
        content: Column(
          children: [
            // UA
            SettingsIntpuTile(
              title: 'settings.network-ua'.i18n,
              // Bloqueado: un User-Agent vacío o mal armado hace que los
              // sitios rechacen TODAS las peticiones de las extensiones, y el
              // usuario ve "sin conexión" sin manera de relacionarlo con este
              // campo. El valor correcto ya lo elige el app según la
              // plataforma (móvil en Android, escritorio en Windows/Linux).
              enabled: false,
              buildSubtitle: () {
                if (!Platform.isAndroid) {
                  return 'settings.network-ua-subtitle'.i18n;
                }
                return PrismHubStorage.getUASetting();
              },
              onChanged: (value) {
                PrismHubStorage.setUASetting(value);
              },
              buildText: () {
                return PrismHubStorage.getUASetting();
              },
            ),
            SettingsRadiosTile(
              title: 'settings.proxy-type'.i18n,
              itemNameValue: {
                'settings.proxy-type-direct'.i18n: 'DIRECT',
                'settings.proxy-type-socks5'.i18n: 'SOCKS5',
                'settings.proxy-type-socks4'.i18n: 'SOCKS4',
                'settings.proxy-type-http'.i18n: 'PROXY',
              },
              // Bloqueado: cambiar de "Directo" activa flutter_socks_proxy,
              // una reimplementación pura en Dart de HttpClient que enruta
              // TODAS las peticiones de la app por su parser (más lento) vía
              // HttpOverrides.global — confirmado como causa real de
              // lentitud general reportada en vivo. Se deja el valor
              // guardado a la vista (por si alguien lo configuró antes) pero
              // ya no editable.
              enabled: false,
              buildSubtitle: () => 'settings.proxy-type-locked-subtitle'.i18n,
              applyValue: (value) {
                PrismHubStorage.setSetting(SettingKey.proxyType, value);
                PrismRequest.refreshProxy();
              },
              buildGroupValue: () {
                return PrismHubStorage.getSetting(SettingKey.proxyType);
              },
            ),
            const SizedBox(height: 10),
            SettingsIntpuTile(
              title: 'settings.proxy'.i18n,
              enabled: false,
              buildSubtitle: () => 'settings.proxy-subtitle'.i18n,
              onChanged: (value) {
                PrismHubStorage.setSetting(SettingKey.proxy, value);
                PrismRequest.refreshProxy();
              },
              buildText: () {
                return PrismHubStorage.getSetting(SettingKey.proxy);
              },
            ),
          ],
        ),
        title: "settings.network".i18n,
        subTitle: "settings.network-subtitle".i18n,
        icon: fluent.FluentIcons.globe,
        androidIcon: Icons.network_wifi,
      ),
      const SizedBox(height: 10),
      // Copia de seguridad. Va antes del bloque de registro porque es de lo
      // que le importa al usuario y no de diagnóstico.
      SettingsExpanderTile(
        title: 'settings.backup'.i18n,
        subTitle: 'settings.backup-subtitle'.i18n,
        androidIcon: Icons.save_alt,
        icon: fluent.FluentIcons.save,
        content: Column(
          children: [
            SettingsTile(
              title: 'settings.backup-export'.i18n,
              // Se recalcula en cada dibujado (buildSubtitle es una función):
              // así, al volver de exportar, la línea del "último" ya está al
              // día sin tener que recargar la pantalla.
              buildSubtitle: () {
                final base = 'settings.backup-export-subtitle'.i18n;
                final hechas =
                    (PrismHubStorage.getSetting(SettingKey.copiasHechas)
                            as int?) ??
                        0;
                if (hechas == 0) return base;
                final nombre =
                    PrismHubStorage.getSetting(SettingKey.nombreDeCopia)
                            as String? ??
                        '';
                return '$base\n${FlutterI18n.translate(
                  context,
                  'settings.backup-last',
                  translationParams: {
                    'nombre': nombre.isEmpty ? '—' : nombre,
                    'n': '$hechas',
                  },
                )}';
              },
              trailing: PlatformWidget(
                androidWidget: TextButton(
                  onPressed: () => _exportarCopia(context),
                  child: Text('common.export'.i18n),
                ),
                desktopWidget: fluent.FilledButton(
                  onPressed: () => _exportarCopia(context),
                  child: Text('common.export'.i18n),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SettingsTile(
              title: 'settings.backup-import'.i18n,
              buildSubtitle: () => 'settings.backup-import-subtitle'.i18n,
              trailing: PlatformWidget(
                androidWidget: TextButton(
                  onPressed: () => _importarCopia(context),
                  child: Text('settings.backup-import-action'.i18n),
                ),
                desktopWidget: fluent.Button(
                  onPressed: () => _importarCopia(context),
                  child: Text('settings.backup-import-action'.i18n),
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      // Debug
      SettingsExpanderTile(
        title: "settings.log".i18n,
        subTitle: 'settings.log-subtitle'.i18n,
        androidIcon: Icons.report,
        icon: fluent.FluentIcons.report_alert,
        content: Column(
          children: [
            SettingsSwitchTile(
              title: 'settings.save-log'.i18n,
              buildSubtitle: () => 'settings.save-log-subtitle'.i18n,
              buildValue: () {
                return PrismHubStorage.getSetting(SettingKey.saveLog);
              },
              onChanged: (value) {
                PrismHubStorage.setSetting(SettingKey.saveLog, value);
              },
            ),
            const SizedBox(height: 10),
            // 导出日志
            SettingsTile(
              title: 'settings.export-log'.i18n,
              buildSubtitle: () => 'settings.export-log-subtitle'.i18n,
              trailing: PlatformWidget(
                androidWidget: TextButton(
                  onPressed: () {
                    Share.shareXFiles([XFile(PrismLog.logFilePath)]);
                  },
                  child: Text('common.export'.i18n),
                ),
                desktopWidget: fluent.FilledButton(
                  onPressed: () async {
                    final path = await FilePicker.platform.saveFile(
                      type: FileType.custom,
                      allowedExtensions: ['log'],
                      fileName: 'PrismHub.log',
                    );
                    if (path != null) {
                      File(PrismLog.logFilePath).copy(path);
                    }
                  },
                  child: Text('common.export'.i18n),
                ),
              ),
            ),
          ],
        ),
      ),
      if (!Platform.isAndroid) ...[
        const SizedBox(height: 10),
        Obx(
          () {
            final value = c.extensionLogWindowId.value != -1;
            return SettingsSwitchTile(
              icon: const Icon(
                fluent.FluentIcons.bug,
                size: 24,
              ),
              title: 'settings.extension-log'.i18n,
              buildSubtitle: () => 'settings.extension-log-subtitle'.i18n,
              buildValue: () => value,
              onChanged: (value) {
                c.toggleExtensionLogWindow(value);
              },
              isCard: true,
            );
          },
        )
      ],
      // 关于
      const SizedBox(height: 20),
      ListTitle(title: 'settings.about'.i18n),
      const SizedBox(height: 20),
      // Reportar fallos y proponer mejoras. Con fila y botón propios, no
      // solo como enlace suelto entre los de abajo: estando en beta es lo
      // que más conviene que el usuario encuentre.
      SettingsTile(
        isCard: true,
        icon: const PlatformWidget(
          androidWidget: Icon(Icons.feedback_outlined),
          desktopWidget: Icon(fluent.FluentIcons.feedback, size: 24),
        ),
        title: 'settings.feedback'.i18n,
        buildSubtitle: () => 'settings.feedback-subtitle'.i18n,
        trailing: PlatformWidget(
          androidWidget: TextButton(
            onPressed: _abrirSugerencias,
            child: Text('settings.feedback-button'.i18n),
          ),
          desktopWidget: fluent.FilledButton(
            onPressed: _abrirSugerencias,
            child: Text('settings.feedback-button'.i18n),
          ),
        ),
      ),
      const SizedBox(height: 10),
      // El aviso legal también acá, para poder consultarlo cuando se quiera:
      // el del arranque se acepta una vez y no vuelve a verse.
      SettingsTile(
        isCard: true,
        icon: const PlatformWidget(
          androidWidget: Icon(Icons.gavel_rounded),
          desktopWidget: Icon(fluent.FluentIcons.script, size: 24),
        ),
        title: 'settings.legal'.i18n,
        buildSubtitle: () => 'settings.legal-subtitle'.i18n,
        trailing: PlatformWidget(
          androidWidget: TextButton(
            onPressed: _mostrarAvisoLegal,
            child: Text('settings.open'.i18n),
          ),
          desktopWidget: fluent.FilledButton(
            onPressed: _mostrarAvisoLegal,
            child: Text('settings.open'.i18n),
          ),
        ),
        onTap: _mostrarAvisoLegal,
      ),
      const SizedBox(height: 10),
      // Los enlaces del proyecto dejan de ser texto suelto al final de
      // "Acerca de" y pasan a filas con botón, igual que el resto: antes
      // convivían dos formas distintas de ofrecer lo mismo.
      _enlaceTile(
        androidIcon: Icons.code,
        desktopIcon: fluent.FluentIcons.git_graph,
        titulo: 'settings.link-source'.i18n,
        subtitulo: 'settings.link-source-subtitle'.i18n,
        url: 'https://github.com/Litdemonick/Prism_Hub',
      ),
      const SizedBox(height: 10),
      _enlaceTile(
        androidIcon: Icons.extension_outlined,
        desktopIcon: fluent.FluentIcons.repo,
        titulo: 'settings.link-extensions'.i18n,
        subtitulo: 'settings.link-extensions-subtitle'.i18n,
        url: 'https://github.com/Litdemonick/prism-plus',
      ),
      const SizedBox(height: 10),
      SettingsTile(
        isCard: true,
        icon: const PlatformWidget(
          androidWidget: Icon(Icons.update),
          desktopWidget: Icon(fluent.FluentIcons.update_restore, size: 24),
        ),
        title: 'settings.upgrade'.i18n,
        buildSubtitle: () => FlutterI18n.translate(
          context,
          'settings.upgrade-subtitle',
          translationParams: {
            'version': packageInfo.version,
          },
        ),
        trailing: PlatformWidget(
          androidWidget: TextButton(
            onPressed: () {
              ApplicationUtils.checkUpdate(
                context,
                showSnackbar: true,
              );
            },
            child: Text('settings.upgrade-training'.i18n),
          ),
          desktopWidget: fluent.FilledButton(
            onPressed: () {
              ApplicationUtils.checkUpdate(
                context,
                showSnackbar: true,
              );
            },
            child: Text('settings.upgrade-training'.i18n),
          ),
        ),
      ),
      const SizedBox(height: 10),
      SettingsExpanderTile(
        leading: const Image(
          image: AssetImage('assets/icon/logo.png'),
          width: 24,
          height: 24,
        ),
        title: "PrismHub",
        subTitle: "AGPL-3.0 License",
        open: true,
        noPage: true,
        content: Column(
          // Centrado en celular: ahí el bloque ocupa el ancho completo de una
          // pantalla angosta y el badge BETA suelto contra el borde izquierdo,
          // con el párrafo largo debajo, quedaba desalineado. En escritorio se
          // deja alineado a la izquierda, que es como está el resto de Ajustes.
          crossAxisAlignment: Platform.isAndroid
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: HomeTheme.accentPink.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: HomeTheme.accentPink),
              ),
              child: const Text(
                "BETA",
                style: TextStyle(
                  color: HomeTheme.accentPink,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 10),
            SelectableText(
              'settings.about-description'.i18n,
              textAlign:
                  Platform.isAndroid ? TextAlign.center : TextAlign.start,
              style: const TextStyle(color: HomeTheme.textPrimary, height: 1.4),
            ),
            const SizedBox(height: 20),
            Text(
              'settings.contributors'.i18n,
              style: const TextStyle(color: HomeTheme.textPrimary),
            ),
            const SizedBox(height: 8),
            Obx(
              () => Wrap(
                children: [
                  if (c.contributors.isNotEmpty)
                    for (final contributor in c.contributors)
                      fluent.Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: () async {
                              await launchUrl(
                                Uri.parse(contributor['html_url']),
                                mode: LaunchMode.externalApplication,
                              );
                            },
                            child: Text(
                              contributor['login'],
                              style: const TextStyle(
                                color: HomeTheme.accentPink,
                              ),
                            ),
                          ),
                        ),
                      )
                ],
              ),
            ),
          ],
        ),
      )
    ];
  }

  Widget _buildAndroid(BuildContext context) {
    return Scaffold(
      backgroundColor: HomeTheme.bg,
      appBar: AppBar(
        backgroundColor: HomeTheme.bg,
        title: Text(
          'common.settings'.i18n,
          style: const TextStyle(color: HomeTheme.textPrimary),
        ),
      ),
      body: Container(
        color: HomeTheme.bg,
        child: Stack(
          children: [
            const Positioned.fill(child: AnimatedBackgroundGlow()),
            // ListView.builder y no ListView(children:): la segunda forma
            // MONTA todos los hijos de una, y esta página son varias secciones
            // pesadas (en escritorio, Expander de fluent). Eso trababa la
            // pantalla unos segundos la primera vez que se abría. Con builder
            // solo se montan las que se ven.
            Builder(builder: (context) {
              final items = _buildContent();
              return ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 10),
                itemCount: items.length,
                itemBuilder: (context, i) => items[i],
              );
            }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PlatformBuildWidget(
      androidBuilder: _buildAndroid,
      desktopBuilder: (context) => Container(
        color: HomeTheme.bg,
        child: Stack(
          children: [
            const Positioned.fill(child: AnimatedBackgroundGlow()),
            // Ver el mismo cambio en la versión Android.
            Builder(builder: (context) {
              final items = _buildContent();
              return ListView.builder(
                padding:
                    const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
                itemCount: items.length,
                itemBuilder: (context, i) => items[i],
              );
            }),
          ],
        ),
      ),
    );
  }
}

// Entrada a los ajustes de salto en celular: una fila con su icono, título y
// resumen, del mismo estilo que el resto de Ajustes, en vez de volcar cuatro
// controles y un párrafo en el medio de la lista.
class _SkipIntervalTile extends StatelessWidget {
  const _SkipIntervalTile({required this.onOpen});
  // Recibe el context de la FILA, no el de la página de Ajustes: es el que
  // está dentro del Navigator donde hay que empujar.
  final void Function(BuildContext) onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: HomeTheme.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: HomeTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onOpen(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                const Icon(Icons.fast_forward,
                    color: HomeTheme.accentPink, size: 22),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'settings.skip-interval'.i18n,
                        style: const TextStyle(
                          color: HomeTheme.textPrimary,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'settings.skip-interval-short'.i18n,
                        style: const TextStyle(
                          color: HomeTheme.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right,
                    color: HomeTheme.textMuted, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Paso compacto para celular: menos, valor, mas. Sin la pastilla de precision
// (con el dedo, saltos de 0,1s no tienen sentido) y con el valor SIEMPRE
// positivo: el sentido lo decide el lado de la pantalla que se toca, asi que
// mostrar "-2 s" en "Retroceder" solo confundia.
class _MobileStepper extends StatefulWidget {
  const _MobileStepper({required this.settingKey, required this.fallback});
  final String settingKey;
  final double fallback;

  @override
  State<_MobileStepper> createState() => _MobileStepperState();
}

class _MobileStepperState extends State<_MobileStepper> {
  late double _valor = _leer();

  double _leer() {
    final v = PrismHubStorage.getSetting(widget.settingKey);
    final d = v is num ? v.toDouble() : widget.fallback;
    final abs = d.abs();
    return abs == 0 ? widget.fallback.abs() : abs;
  }

  @override
  void didUpdateWidget(covariant _MobileStepper old) {
    super.didUpdateWidget(old);
    final actual = _leer();
    if (actual != _valor) _valor = actual;
  }

  void _cambiar(double delta) {
    final nuevo = (_valor + delta).clamp(1.0, 120.0);
    if (nuevo == _valor) return;
    setState(() => _valor = nuevo);
    // Se guarda con el signo que espera el reproductor: negativo para atras.
    final signo = widget.fallback < 0 ? -1 : 1;
    PrismHubStorage.setSetting(widget.settingKey, nuevo * signo);
  }

  Widget _boton(IconData icono, VoidCallback onTap) {
    return Material(
      color: HomeTheme.bg,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Icon(icono, size: 18, color: HomeTheme.textPrimary),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _boton(Icons.remove, () => _cambiar(-1)),
        SizedBox(
          width: 46,
          child: Text(
            '${_valor.round()} s',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: HomeTheme.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
        ),
        _boton(Icons.add, () => _cambiar(1)),
      ],
    );
  }
}

/// Pide la clave de una copia de seguridad.
///
/// Al exportar la pide dos veces: una clave mal escrita en una copia que se
/// guarda hoy y se usa dentro de un año es un archivo perdido para siempre. El
/// archivo NO guarda la clave —solo permite comprobar si la que se escribe es
/// la correcta— así que no hay a quién pedírsela después.
///
/// Devuelve la clave por `pop`, o null si se cancela.
/// Lo que el usuario decide sobre una copia: cómo se llama y con qué clave.
class _DatosDeCopia {
  const _DatosDeCopia({required this.clave, required this.nombre});
  final String clave;

  /// Con qué equipo se hizo. Vacío al importar, donde ya viene en el archivo.
  final String nombre;
}

class _DialogoClave extends StatefulWidget {
  const _DialogoClave({
    required this.alExportar,
    this.nombrePropuesto,
    this.numero,
    this.deQuien,
  });
  final bool alExportar;

  /// El nombre con el que se guardó la copia anterior, para no reescribirlo.
  final String? nombrePropuesto;

  /// Qué número de copia va a ser esta.
  final int? numero;

  /// De qué copia se trata, al importar: "Mi celular · copia n.º 3".
  final String? deQuien;

  @override
  State<_DialogoClave> createState() => _DialogoClaveState();
}

class _DialogoClaveState extends State<_DialogoClave> {
  final _clave = TextEditingController();
  final _repetida = TextEditingController();
  late final TextEditingController _nombre =
      TextEditingController(text: widget.nombrePropuesto ?? '');
  bool _oculta = true;
  String? _error;

  @override
  void dispose() {
    _clave.dispose();
    _repetida.dispose();
    _nombre.dispose();
    super.dispose();
  }

  void _aceptar() {
    final clave = _clave.text;
    if (clave.isEmpty) {
      setState(() => _error = 'settings.backup-key-empty'.i18n);
      return;
    }
    if (widget.alExportar) {
      // El mismo mínimo que exige el cifrado. Se comprueba acá además de allá
      // para poder decirlo en el momento, en vez de dejar escribir todo y
      // fallar al guardar.
      if (clave.length < CopiaCifrado.largoMinimo) {
        setState(() => _error = FlutterI18n.translate(
              context,
              'settings.backup-key-short',
              translationParams: {'n': '${CopiaCifrado.largoMinimo}'},
            ));
        return;
      }
      if (clave != _repetida.text) {
        setState(() => _error = 'settings.backup-key-mismatch'.i18n);
        return;
      }
      // Saneado con la MISMA función que usa el archivo, así lo que se ve acá
      // es exactamente lo que se va a guardar.
      final nombre = CopiaSeguridad.limpiarNombre(_nombre.text);
      if (nombre.isEmpty) {
        setState(() => _error = 'settings.backup-name-empty'.i18n);
        return;
      }
      Navigator.of(context).pop(_DatosDeCopia(clave: clave, nombre: nombre));
      return;
    }
    Navigator.of(context).pop(_DatosDeCopia(clave: clave, nombre: ''));
  }

  @override
  Widget build(BuildContext context) {
    final esAndroid = Platform.isAndroid;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          (widget.alExportar
                  ? 'settings.backup-key-hint-export'
                  : 'settings.backup-key-hint-import')
              .i18n,
          style: TextStyle(
            fontSize: 12.5,
            height: 1.4,
            color:
                DefaultTextStyle.of(context).style.color?.withValues(alpha: .7),
          ),
        ),
        // De qué copia se trata, al importar. Se lee del archivo SIN la clave,
        // así que se puede mostrar antes de pedirla: es lo que permite saber si
        // se eligió el archivo correcto entre varios de la misma carpeta.
        if (!widget.alExportar && (widget.deQuien?.isNotEmpty ?? false)) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: HomeTheme.accentPink.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: HomeTheme.accentPink.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                const Icon(Icons.folder_zip_outlined,
                    size: 18, color: HomeTheme.accentPink),
                const SizedBox(width: 8),
                // Flexible: un nombre largo en un teléfono angosto se sale de
                // la caja si no se le deja envolver.
                Flexible(
                  child: Text(
                    widget.deQuien!,
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ],
        // El nombre del equipo, al exportar. Es lo que después dice de dónde
        // salieron los datos al recuperarlos.
        if (widget.alExportar) ...[
          const SizedBox(height: 14),
          _campo(_nombre, 'settings.backup-name-label'.i18n, esAndroid),
          if (widget.numero != null) ...[
            const SizedBox(height: 6),
            Text(
              FlutterI18n.translate(context, 'settings.backup-name-number',
                  translationParams: {'n': '${widget.numero}'}),
              style: TextStyle(
                fontSize: 11.5,
                color: DefaultTextStyle.of(context)
                    .style
                    .color
                    ?.withValues(alpha: .55),
              ),
            ),
          ],
        ],
        const SizedBox(height: 14),
        _campo(_clave, 'settings.backup-key-label'.i18n, esAndroid,
            conOjo: true),
        if (widget.alExportar) ...[
          const SizedBox(height: 10),
          _campo(_repetida, 'settings.backup-key-repeat'.i18n, esAndroid),
        ],
        // El error ocupa sitio solo cuando lo hay: reservarlo siempre deja un
        // hueco raro, y meterlo de golpe empuja los botones.
        AnimatedSize(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: _error == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.error_outline,
                          size: 16, color: Colors.redAccent),
                      const SizedBox(width: 6),
                      // Flexible: un mensaje largo en una pantalla angosta se
                      // sale de la caja si no se le deja envolver.
                      Flexible(
                        child: Text(
                          _error!,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.redAccent),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            PlatformTextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('common.cancel'.i18n),
            ),
            const SizedBox(width: 8),
            PlatformFilledButton(
              onPressed: _aceptar,
              child: Text(
                (widget.alExportar ? 'common.export' : 'common.confirm').i18n,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// El campo de cada plataforma: en escritorio el de fluent y en el teléfono
  /// el de material, para que se vea como el resto de la app y no como un
  /// injerto.
  Widget _campo(TextEditingController c, String etiqueta, bool esAndroid,
      {bool conOjo = false}) {
    final ojo = conOjo
        ? IconButton(
            icon: Icon(_oculta ? Icons.visibility_off : Icons.visibility,
                size: 18),
            onPressed: () => setState(() => _oculta = !_oculta),
            tooltip: (_oculta ? 'common.show' : 'common.hide').i18n,
          )
        : null;
    if (esAndroid) {
      return TextField(
        controller: c,
        obscureText: _oculta,
        autofocus: conOjo,
        onSubmitted: (_) => _aceptar(),
        decoration: InputDecoration(
          labelText: etiqueta,
          isDense: true,
          border: const OutlineInputBorder(),
          suffixIcon: ojo,
        ),
      );
    }
    return fluent.TextBox(
      controller: c,
      obscureText: _oculta,
      autofocus: conOjo,
      placeholder: etiqueta,
      onSubmitted: (_) => _aceptar(),
      suffix: ojo,
    );
  }
}

/// La barra mientras entra una copia.
///
/// Una copia grande son cientos de registros y cada uno toca la base de datos.
/// Sin esto la pantalla se queda quieta varios segundos y no hay forma de
/// distinguirlo de que se colgó.
///
/// La barra va **animada hacia** cada valor nuevo en vez de saltar: el progreso
/// llega a tirones —un registro rápido, otro lento— y sin suavizarlo se ve
/// nerviosa aunque el trabajo avance parejo.
class _BarraDeImportacion extends StatelessWidget {
  const _BarraDeImportacion({required this.progreso});
  final ValueNotifier<double> progreso;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: progreso,
      builder: (context, valor, _) {
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: valor.clamp(0.0, 1.0)),
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          builder: (context, suave, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'settings.backup-import-working-hint'.i18n,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: DefaultTextStyle.of(context)
                      .style
                      .color
                      ?.withValues(alpha: .7),
                ),
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  // Indeterminada hasta el primer dato: leer y descifrar el
                  // archivo pasa antes de que haya nada que contar.
                  value: valor <= 0 ? null : suave,
                  minHeight: 8,
                  backgroundColor:
                      HomeTheme.accentPink.withValues(alpha: 0.18),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                      HomeTheme.accentPink),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  valor <= 0 ? '' : '${(suave * 100).round()}%',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: HomeTheme.accentPink,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
