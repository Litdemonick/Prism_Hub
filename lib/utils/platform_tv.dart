import 'dart:io';

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
    if (!Platform.isAndroid) return;
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
          nucleos: (datos['nucleos'] as num?)?.toInt() ?? 0,
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

  /// Decide el nivel con lo que informó el sistema.
  ///
  /// Los tres datos juntos y no uno solo: `isLowRamDevice` es la respuesta
  /// oficial de Android, pero la declara el fabricante y varios sticks baratos
  /// no la ponen. La memoria total y la cantidad de núcleos los delatan igual.
  static void resolver({
    required bool esTelevision,
    required bool bajaMemoria,
    required int memoriaTotalMb,
    required int nucleos,
  }) {
    // Teléfonos y tablets siguen como hasta ahora. Este trabajo salió de que la
    // app se petaba en televisores, y no hay ninguna medición que diga que un
    // teléfono modesto necesite lo mismo — meterlo acá sin dato sería cambiar
    // el comportamiento de la mayoría de los usuarios a ciegas.
    if (!esTelevision) {
      nivel = NivelDeAparato.alto;
      return;
    }
    // memoriaTotalMb en 0 significa "no se pudo averiguar", no "no tiene
    // memoria": por eso se pregunta que sea mayor que cero antes de compararlo.
    final pocaMemoria = memoriaTotalMb > 0 && memoriaTotalMb < 1500;
    // Lo mismo con los núcleos: 0 es que no se supo.
    final pocosNucleos = nucleos > 0 && nucleos <= 2;
    nivel = (bajaMemoria || pocaMemoria || pocosNucleos)
        ? NivelDeAparato.bajo
        : NivelDeAparato.medio;
    logger.info(
      'Perfil del aparato: ${nivel.name} '
      '(bajaMemoria=$bajaMemoria, memoria=${memoriaTotalMb}MB, '
      'nucleos=$nucleos)',
    );
  }
}
