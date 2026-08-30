import 'dart:io';

import 'package:prismhub/utils/application.dart';

import 'package:flutter/services.dart';
import 'package:prismhub/utils/log.dart';

/// Si el proceso está corriendo en un Android TV (o una caja Google
/// TV/leanback), en vez de un teléfono o tablet.
///
/// Windows y Linux nunca preguntan al canal: no existe del otro lado, así que
/// ni se intenta.
class PlatformTv {
  static const _canal = MethodChannel('com.example.prismhub/update');

  /// Se resuelve UNA sola vez, durante el arranque (ver `_AppRootState._init`
  /// en main.dart), antes de que se construya la primera pantalla real. El
  /// resto de la app pregunta con [esTelevisionSync]: el mismo criterio
  /// síncrono que ya usa todo el código de plataforma (`Platform.isAndroid`),
  /// para no tener que reescribir cada `build()` alrededor de un `Future`.
  static bool esTelevisionSync = false;

  static Future<void> ensureInitialized() async {
    if (!Platform.isAndroid) {
      await PerfilDeAparato.resolverEnEscritorio();
      return;
    }
    try {
      // Una sola llamada trae las cuatro cosas: si es televisor y los tres
      // datos con los que se decide cuánto puede gastar la app. Antes eran dos
      // preguntas distintas al mismo canal.
      final datos = await _canal.invokeMapMethod<String, dynamic>(
        'perfilDelAparato',
      );
      if (datos != null) {
        esTelevisionSync = datos['esTelevision'] == true;
        PerfilDeAparato.resolver(
          esTelevision: esTelevisionSync,
          bajaMemoria: datos['bajaMemoria'] == true,
          memoriaTotalMb: (datos['memoriaTotalMb'] as num?)?.toInt() ?? 0,
          // Lo mismo que en escritorio: los físicos mandan. El canal nativo
          // manda los lógicos, que es lo que expone Android.
          nucleos: PerfilDeAparato._nucleosParaDecidir(),
        );
        return;
      }
      // El canal contestó vacío: se cae al método viejo, que sigue estando.
      // Pasa si alguien corre una versión de la parte nativa anterior a esta
      // (no debería, van juntas, pero no cuesta nada cubrirlo).
      esTelevisionSync =
          await _canal.invokeMethod<bool>('isTelevision') ?? false;
    } catch (e) {
      // Si el canal falla (dispositivo viejo, error de plataforma), se sigue
      // como teléfono normal. Nunca puede ser esto lo que tumbe el arranque.
      logger.warning('No se pudo detectar si el dispositivo es TV: $e');
      esTelevisionSync = false;
    }
  }
}

/// Si el aparato se maneja tocando la pantalla, en vez de con un puntero.
///
/// Va por sistema operativo a propósito y no por el ancho de la ventana: el
/// tamaño no dice si hay mouse. Estaba escrito dos veces —en `home_page.dart`
/// y en `tarjeta_de_catalogo.dart`— con el mismo cuerpo; ahora los dos apuntan
/// acá.
///
/// **Un Android TV contesta que sí**, y es correcto: es Android, y muchas
/// decisiones de tamaño y de diseño que dependen de esto le sirven igual. Lo
/// que un televisor NO tiene son los gestos — para eso está [hayGestosDeDedo].
bool get esPantallaTactil => Platform.isAndroid || Platform.isIOS;

/// Si existen los GESTOS de dedo: deslizar para refrescar, arrastrar una fila,
/// tirar hacia abajo para aplicar un filtro.
///
/// ── Por qué hace falta separarlo de [esPantallaTactil] ──────────────────
///
/// Porque un Android TV es «táctil» para el sistema operativo y no tiene ni
/// dedo ni puntero: se maneja con un control remoto. Preguntando solo por
/// [esPantallaTactil], el televisor entraba por el camino del teléfono y se
/// quedaba sin salida — el caso concreto: al marcar un filtro salía «deslizá
/// hacia abajo para aplicar» y el botón de aplicar estaba escondido porque «en
/// celular se aplica deslizando». En un televisor no hay forma de deslizar, así
/// que el filtro quedaba marcado y sin poder aplicarse nunca.
///
/// Regla simple: si lo que se está decidiendo es un GESTO, se pregunta acá. Si
/// es un tamaño o un detalle visual, [esPantallaTactil] alcanza.
bool get hayGestosDeDedo => esPantallaTactil && !PlatformTv.esTelevisionSync;

/// Cuánto puede gastar la app en este aparato.
///
/// ── Por qué no alcanza con «es TV o no» ─────────────────────────────────
///
/// Un Chromecast con Google TV 4K y un stick de 1 GB son las dos cosas «un
/// televisor», y pedirles lo mismo es lo que hacía que en el segundo la app
/// fuera a tirones y se cerrara sola: el techo de memoria de imágenes pensado
/// para un teléfono actual le come el heap entero.
///
/// Con esto, cada decisión de coste (cuánta memoria de imágenes, si vale la
/// pena un desenfoque, si el foco se anima) se toma mirando el aparato de
/// verdad en vez de castigar a todos por igual — y en escritorio y en teléfono
/// todo queda exactamente como estaba, porque ahí el nivel es [alto].
enum NivelDeAparato {
  /// Lo de siempre, sin recortes: escritorio, teléfonos y tablets, y también
  /// cualquier caso en el que no se haya podido averiguar nada. Que un
  /// televisor moderno caiga acá por error no rompe nada; al revés sí.
  alto,

  /// Un televisor que anda bien. Se recorta lo que no se nota (la resolución a
  /// la que se decodifican las portadas, el techo de la caché) y se deja todo
  /// lo demás.
  medio,

  /// Un televisor viejo o un stick barato. Acá se apaga además lo que cuesta
  /// GPU aunque se note un poco: desenfoques, fundidos y la escala del foco.
  bajo;

  /// Elegir un valor por nivel, igual que `Ancho.elegir<T>()` en
  /// breakpoints.dart — pedir el valor en vez de escribir un `if` en cada
  /// sitio es lo que evita que esto se desparrame por toda la app.
  T elegir<T>({required T alto, required T medio, required T bajo}) =>
      switch (this) {
        NivelDeAparato.alto => alto,
        NivelDeAparato.medio => medio,
        NivelDeAparato.bajo => bajo,
      };
}

class PerfilDeAparato {
  PerfilDeAparato._();

  /// El nivel de ESTE aparato. Se resuelve una vez en el arranque, junto con
  /// [PlatformTv.esTelevisionSync], y no vuelve a cambiar.
  ///
  /// Arranca en [NivelDeAparato.alto] a propósito: si algo falla antes de
  /// resolverlo, la app se comporta como se comportaba hasta ahora.
  static NivelDeAparato nivel = NivelDeAparato.alto;

  /// Atajo para lo más común: «¿esto es un aparato que hay que cuidar?».
  static bool get esModesto => nivel != NivelDeAparato.alto;

  /// Si en este aparato tiene sentido ofrecer «pedir siempre la máxima
  /// calidad».
  ///
  /// ── Por qué es un ajuste que se puede bloquear ──────────────────────────
  ///
  /// Ese interruptor le dice a la app que apunte siempre a la variante más
  /// alta que publique la fuente: 1080p, 4K, la que haya. En un aparato capaz
  /// es lo que quiere quien tiene con qué.
  ///
  /// En uno modesto no es una preferencia, es una forma de romper la
  /// reproducción: medido en un televisor de 0,9 GB con pantalla de 720p,
  /// pidiendo 1080p el colchón se vaciaba a cero y el vídeo se paraba solo. Con
  /// 4K ni arrancaría. Dejar el interruptor a la vista ahí es ofrecer un botón
  /// que solo puede empeorar las cosas, sin decirlo.
  ///
  /// Se bloquea en el nivel bajo y se explica por qué, en vez de esconderlo:
  /// alguien que lo busca tiene que encontrar la respuesta, no un hueco.
  ///
  /// **Y también se ignora si quedó encendido de antes**, porque el aparato
  /// puede haber cambiado de nivel al actualizar la app.
  static bool get puedeExigirMaximaCalidad => nivel != NivelDeAparato.bajo;

  /// Decide el nivel con lo que informó el sistema.
  ///
  /// ── Qué se mira, y por qué no alcanza con un dato ───────────────────────
  ///
  /// `isLowRamDevice` es la respuesta oficial de Android, pero la declara el
  /// fabricante y varios sticks baratos no la ponen. La memoria total y los
  /// núcleos los delatan igual, así que se miran los tres.
  ///
  /// ── Y por qué el listón no es el mismo en un televisor ──────────────────
  ///
  /// Porque no hacen lo mismo. Un televisor con 2 GB dedica casi todo a la
  /// interfaz del sistema y al decodificador, y comparte el procesador con él;
  /// un teléfono con 2 GB es un teléfono modesto pero entero para la app. El
  /// mismo número significa cosas distintas, así que los cortes son distintos.
  ///
  /// Un televisor SÍ puede llegar al nivel alto: un Fire TV 4K con 3 GB y ocho
  /// núcleos no tiene por qué recibir el mismo trato que un stick de 1 GB, y
  /// tratarlo así sería desperdiciarlo.
  static void resolver({
    required bool esTelevision,
    required bool bajaMemoria,
    required int memoriaTotalMb,
    required int nucleos,
  }) {
    nivel = _decidir(
      esTelevision: esTelevision,
      bajaMemoria: bajaMemoria,
      memoriaTotalMb: memoriaTotalMb,
      nucleos: nucleos,
    );
    logger.info(
      'Perfil del aparato: ${nivel.name} '
      '(televisor=$esTelevision, bajaMemoria=$bajaMemoria, '
      'memoria=${memoriaTotalMb}MB, nucleos=$nucleos)',
    );
  }

  /// La decisión sola, sin tocar nada y sin escribir en el registro.
  ///
  /// Va aparte para poder probarla: lo demás depende del sistema.
  ///
  /// Un 0 en memoria o núcleos significa «no se pudo averiguar», no «no
  /// tiene»: por eso se pregunta que sean mayores que cero antes de comparar.
  /// Sin datos, se queda en alto, que es como se comportaba la app hasta que
  /// esto existió.
  static NivelDeAparato _decidir({
    required bool esTelevision,
    required bool bajaMemoria,
    required int memoriaTotalMb,
    required int nucleos,
  }) {
    // Lo que dice el propio sistema manda por encima de cualquier número.
    if (bajaMemoria) return NivelDeAparato.bajo;

    // (memoria para ser modesto, memoria para ser capaz, núcleos para capaz)
    final (topeBajo, pisoAlto, nucleosAlto) =
        esTelevision ? (1500, 3000, 4) : (2000, 4000, 4);

    if (memoriaTotalMb > 0 && memoriaTotalMb < topeBajo) {
      return NivelDeAparato.bajo;
    }
    if (nucleos > 0 && nucleos <= 2) return NivelDeAparato.bajo;
    if (memoriaTotalMb >= pisoAlto && nucleos >= nucleosAlto) {
      return NivelDeAparato.alto;
    }
    // Sin ningún dato creíble no se recorta nada: es como venía siendo.
    if (memoriaTotalMb <= 0 && nucleos <= 0) return NivelDeAparato.alto;
    return NivelDeAparato.medio;
  }

  /// Cuántos núcleos FÍSICOS tiene el procesador, o 0 si no se pudo saber.
  ///
  /// Se usa además de los lógicos para decidir el nivel del aparato: un
  /// procesador de dos núcleos con cuatro hilos no rinde como uno de cuatro
  /// núcleos, y contarlo como cuatro sería tratarlo mejor de lo que puede.
  static int nucleosFisicos() {
    try {
      if (Platform.isWindows) {
        final n = windowsDeviceInfo.numberOfCores;
        return n > 0 ? n : 0;
      }
      if (Platform.isAndroid || Platform.isLinux) {
        // Cada núcleo físico aparece como un par «physical id + core id». Los
        // hilos del mismo núcleo repiten ese par, así que contando los pares
        // distintos salen los físicos.
        final pares = <String>{};
        String fisico = '0';
        String core = '';
        for (final l in File('/proc/cpuinfo').readAsLinesSync()) {
          if (l.startsWith('physical id')) {
            fisico = l.split(':').last.trim();
          } else if (l.startsWith('core id')) {
            core = l.split(':').last.trim();
            pares.add('$fisico/$core');
          }
        }
        if (pares.isNotEmpty) return pares.length;
      }
    } catch (_) {
      // Sin ese archivo, sin permiso, o con un formato que no trae esos
      // campos —pasa en varios ARM—: se contesta 0 y decide el resto.
    }
    return 0;
  }

  /// El perfil en Windows, Linux y macOS.
  ///
  /// ── Por qué hacía falta ─────────────────────────────────────────────────
  ///
  /// Hasta ahora esto solo se calculaba en Android: en escritorio el nivel era
  /// siempre alto, sin haber medido nada. O sea que un portátil viejo de dos
  /// núcleos recibía exactamente el mismo trato que una máquina nueva, y la
  /// app pedía 1080p y treinta peticiones a la vez en los dos.
  ///
  /// Los datos son los mismos que ya se anotan en la cabecera del registro, así
  /// que no hace falta nada nuevo: la memoria física y los núcleos.
  static Future<void> resolverEnEscritorio() async {
    try {
      final memoria = await _memoriaDeEscritorioMb();
      resolver(
        esTelevision: false,
        // No existe en escritorio: es una marca que pone el fabricante en
        // Android. Acá deciden la memoria y los núcleos.
        bajaMemoria: false,
        memoriaTotalMb: memoria,
        // Los físicos si se pueden saber: dos hilos del mismo núcleo no
        // decodifican vídeo en paralelo, así que contar los lógicos haría
        // parecer capaz a un procesador que no lo es.
        nucleos: _nucleosParaDecidir(),
      );
    } catch (e) {
      // Sin el dato se queda en alto, que es como venía siendo. Esto no puede
      // ser lo que impida arrancar.
      logger.info('No se pudo medir el aparato: $e');
    }
  }

  /// Con cuántos núcleos se decide: los físicos si se conocen, y si no los
  /// lógicos, que es lo único que hay.
  static int _nucleosParaDecidir() {
    final fisicos = nucleosFisicos();
    return fisicos > 0 ? fisicos : Platform.numberOfProcessors;
  }

  /// La memoria física en MB, o 0 si no se pudo saber.
  static Future<int> _memoriaDeEscritorioMb() async {
    try {
      if (Platform.isWindows) {
        return windowsDeviceInfo.systemMemoryInMegabytes;
      }
      if (Platform.isLinux) {
        // De donde la saca el propio sistema.
        final linea = File('/proc/meminfo')
            .readAsLinesSync()
            .firstWhere((l) => l.startsWith('MemTotal'), orElse: () => '');
        final kb = int.tryParse(
          RegExp(r'(\d+)').firstMatch(linea)?.group(1) ?? '',
        );
        if (kb != null) return kb ~/ 1024;
      }
    } catch (_) {
      // Sin permiso, sin ese archivo, o la info del sistema todavía sin
      // cargar: se sigue sin el dato.
    }
    return 0;
  }
}
