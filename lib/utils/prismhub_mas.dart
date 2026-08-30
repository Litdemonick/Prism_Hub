import 'dart:io';

import 'package:flutter/rendering.dart';

import 'package:prismhub/utils/log.dart';
import 'package:prismhub/utils/platform_tv.dart';
import 'package:prismhub/utils/prismhub_directory.dart';

/// **PrismHub+**: mira en qué aparato está corriendo la app y la ajusta a él.
///
/// ── Por qué existe ──────────────────────────────────────────────────────────
///
/// PrismHub corre en un televisor de 0,9 GB con Android 9, en un teléfono con
/// ocho núcleos y 7 GB, y en un PC. Los mismos valores no pueden servir para
/// los tres: lo que en el teléfono es holgura, en el televisor es la diferencia
/// entre navegar fluido y que la app se atragante al abrirse.
///
/// Y hasta ahora esos ajustes estaban repartidos: cuánta calidad de vídeo pedir
/// vivía en el reproductor, cuántas peticiones a la vez en el cliente de las
/// extensiones, el techo de imágenes en el alivio de memoria. Cada uno decidía
/// por su cuenta, y no había un sitio donde mirar «qué está haciendo la app
/// distinto en ESTE aparato».
///
/// Acá está todo junto. Lo que se detecta lo resuelve [PerfilDeAparato] al
/// arrancar; lo que se hace con eso se decide en este archivo y en ninguno más.
///
/// ── Y por qué NO se puede apagar ────────────────────────────────────────────
///
/// Llegó a tener un interruptor y se sacó. Apagarlo no era una preferencia: era
/// dejar que la app pidiera 220 MB de imágenes y ciento treinta peticiones a la
/// vez en un televisor de 0,9 GB, o sea pedirle al sistema que la cerrara.
///
/// Lo que sí es una preferencia —pedir siempre la máxima calidad de vídeo—
/// tiene su propio ajuste en Reproducción, que es donde corresponde. Esto no es
/// una opción de gusto: es cómo la app se entera de con qué cuenta.
///
/// Lo que queda para quien lo necesite es **volver a medir el aparato**, por si
/// alguna vez lo clasificara peor de lo que es. Eso no apaga nada.
class PrismHubMas {
  PrismHubMas._();

  /// El nivel con el que se decide todo.
  static NivelDeAparato get nivel => PerfilDeAparato.nivel;

  /// Si este aparato recibe algún recorte ahora mismo.
  static bool get estaAjustando =>
      PerfilDeAparato.nivel != NivelDeAparato.alto;

  // ── Lo que se ajusta ──────────────────────────────────────────────────────

  /// Hasta qué altura de vídeo se pide.
  ///
  /// Es un TECHO, no un objetivo: si la fuente solo publica 720p, se ve 720p.
  /// Lo que evita es pedir 1080p a un aparato que no puede mostrarlo ni
  /// sostenerlo, que es como se llega a un vídeo que se corta solo.
  static int get techoDeCalidad => switch (nivel) {
        NivelDeAparato.bajo => 720,
        NivelDeAparato.medio => 1080,
        NivelDeAparato.alto => 2160,
      };

  /// Cuántas peticiones de extensiones corren a la vez. 0 es sin límite.
  ///
  /// Al abrir la app todas las zonas piden sus carruseles a la vez. Medido en
  /// un televisor de 0,9 GB: unas ciento treinta peticiones en catorce
  /// segundos, con el sistema pidiendo memoria cuatro veces en esa ventana.
  static int get peticionesALaVez => switch (nivel) {
        NivelDeAparato.bajo => 4,
        NivelDeAparato.medio => 8,
        NivelDeAparato.alto => 0,
      };

  /// Cuánto dura una animación de la interfaz.
  ///
  /// ── Por qué se acortan y no se apagan ───────────────────────────────────
  ///
  /// Una animación de 300 ms en un aparato que tarda 250 ms en construir la
  /// pantalla no se ve como una animación: se ve como un tirón. Pero quitarlas
  /// del todo deja la navegación seca y desorienta —no se entiende de dónde
  /// salió lo que apareció—.
  ///
  /// Acortarlas conserva la pista de a dónde fue cada cosa y le da al aparato
  /// la mitad del trabajo.
  static Duration animacion(Duration normal) => switch (nivel) {
        NivelDeAparato.bajo =>
          Duration(milliseconds: (normal.inMilliseconds * 0.5).round()),
        NivelDeAparato.medio =>
          Duration(milliseconds: (normal.inMilliseconds * 0.75).round()),
        NivelDeAparato.alto => normal,
      };

  /// Cuánto se construye por fuera de lo que se ve, en píxeles.
  ///
  /// Flutter construye de más a los lados de una lista para que al desplazarse
  /// ya esté listo. En un aparato capaz eso es lo que hace que un carrusel vaya
  /// suave; en uno modesto es trabajo que no llega a tiempo y que además ocupa
  /// memoria con portadas que quizá no se miren nunca.
  ///
  /// Null es «lo que decida Flutter», que es lo de siempre.
  /// Se devuelve ya como `ScrollCacheExtent` y no como número suelto porque es
  /// lo que piden las listas de Flutter desde la 3.41 —`cacheExtent` quedó
  /// obsoleto— y traducirlo en cada sitio de uso sería repetir lo mismo.
  static ScrollCacheExtent? get cuantoSeConstruyeDeMas => switch (nivel) {
        NivelDeAparato.bajo => const ScrollCacheExtent.pixels(250),
        NivelDeAparato.medio => const ScrollCacheExtent.pixels(600),
        NivelDeAparato.alto => null,
      };

  /// Lo mismo en píxeles, para poder mostrarlo en Ajustes.
  static double? get pixelesQueSeConstruyenDeMas => switch (nivel) {
        NivelDeAparato.bajo => 250,
        NivelDeAparato.medio => 600,
        NivelDeAparato.alto => null,
      };

  // ── Limpieza ──────────────────────────────────────────────────────────────

  /// Suelta lo que la app tiene guardado y ya no hace falta.
  ///
  /// ── Qué borra y qué NO ──────────────────────────────────────────────────
  ///
  /// Borra archivos temporales: lo que quedó de una descarga a medias, de un
  /// registro exportado, de una actualización que ya se instaló. Todo eso se
  /// vuelve a generar solo cuando haga falta.
  ///
  /// **No toca nada que le importe a nadie**: ni las extensiones, ni el
  /// historial, ni lo que se está viendo, ni los ajustes, ni las cookies de
  /// sesión de las extensiones —borrarlas cerraría la sesión de las que
  /// necesitan cuenta—.
  ///
  /// Devuelve cuántos bytes se soltaron.
  static Future<int> limpiar() async {
    var soltados = 0;
    try {
      final cache = Directory(PrismHubDirectory.getCacheDirectory);
      if (cache.existsSync()) {
        soltados += _vaciar(cache);
      }
    } catch (e) {
      // Un archivo tomado por otro proceso, o sin permiso: se sigue con el
      // resto. Limpiar es de mejor esfuerzo, no una operación que pueda fallar.
      logger.info('PrismHub+: no se pudo limpiar todo — $e');
    }
    logger.info('PrismHub+: se soltaron '
        '${(soltados / (1024 * 1024)).toStringAsFixed(1)} MB de temporales');
    return soltados;
  }

  /// Borra el contenido de una carpeta, no la carpeta.
  static int _vaciar(Directory dir) {
    var soltados = 0;
    for (final cosa in dir.listSync()) {
      try {
        if (cosa is File) {
          soltados += cosa.lengthSync();
          cosa.deleteSync();
        } else if (cosa is Directory) {
          soltados += _pesa(cosa);
          cosa.deleteSync(recursive: true);
        }
      } catch (_) {
        // Ese no se pudo. Los demás sí.
      }
    }
    return soltados;
  }

  static int _pesa(Directory dir) {
    var total = 0;
    try {
      for (final c in dir.listSync(recursive: true)) {
        if (c is File) total += c.lengthSync();
      }
    } catch (_) {
      // Sin permiso para recorrerla: se cuenta como 0 y se sigue.
    }
    return total;
  }

  /// Deja escrito en el registro qué decidió, al arrancar.
  ///
  /// Es la línea que contesta «¿por qué en este aparato se ve distinto?» sin
  /// tener que deducirlo del resto del registro.
  static void anotarEnElRegistro() {
    logger.info(
      'PrismHub+ · aparato ${PerfilDeAparato.nivel.name} · '
      'vídeo hasta ${techoDeCalidad}p · '
      'peticiones a la vez: '
      '${peticionesALaVez == 0 ? 'sin límite' : peticionesALaVez}',
    );
  }
}
