import 'package:flutter/rendering.dart';

import 'package:prismhub/utils/log.dart';
import 'package:prismhub/utils/platform_tv.dart';

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
  static bool get estaAjustando => PerfilDeAparato.nivel != NivelDeAparato.alto;

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

  /// Cuántos motores de extensión pueden estar vivos a la vez. 0 es sin tope.
  ///
  /// Cada motor es un QuickJS con su pila de 1 MB y con CryptoJS, jsencrypt y
  /// md5 analizados adentro. Se levantan solos al usar una extensión y hasta
  /// ahora solo se soltaban por tiempo — así que pasear por el Inicio y las
  /// zonas dejaba doce vivos a la vez (medido en el registro de un televisor
  /// de 893 MB, justo antes de que el sistema matara la app).
  ///
  /// El tope es más alto que `peticionesALaVez` en el mismo aparato: así
  /// nunca hay que soltar uno que se está usando. Ver
  /// `ExtensionUtils.limitarMotoresVivos`.
  static int get motoresVivosALaVez => switch (nivel) {
        // Seis y no tres: con tres, el Inicio y las zonas —que le piden a
        // media docena de extensiones seguidas— soltaban y volvían a
        // levantar un motor cada dos segundos, y cada levantada vuelve a
        // analizar 148 KB de JavaScript. El tope está para cortar la cola
        // larga (doce vivos), no para pelearse con lo que se está usando.
        NivelDeAparato.bajo => 6,
        NivelDeAparato.medio => 10,
        NivelDeAparato.alto => 0,
      };

  /// Por cuánto se multiplica el ancho al que se decodifica una imagen.
  ///
  /// 1 es «al tamaño exacto en el que se ve», que es lo correcto y lo que se
  /// hace en todos lados. Pero en un aparato modesto el problema no es una
  /// portada sino el total: con un techo de 22 MB —unas 88 portadas— cada una
  /// que entra echa a otra, y la misma tarjeta se vuelve a decodificar cada
  /// vez que se pasa por encima. Un cuarto menos de ancho es casi la mitad de
  /// bytes: entran casi el doble bajo el mismo techo, y se decodifica (y se
  /// sube a la GPU) mucho menos.
  ///
  /// A tres metros de un televisor de 720p esa diferencia de nitidez no se
  /// distingue. El tirón sí se distinguía.
  static double get factorDeDecodificacion => switch (nivel) {
        NivelDeAparato.bajo => 0.75,
        NivelDeAparato.medio => 0.9,
        NivelDeAparato.alto => 1,
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

  /// Cuánto se le aguanta a un motor de extensión sin usarse antes de soltarlo.
  ///
  /// ── Por qué no es «para siempre» ni «enseguida» ─────────────────────────
  ///
  /// Un motor que ya no se usa se queda con su pila y con CryptoJS, jsencrypt y
  /// md5 analizados adentro. Si alguien recorre cinco zonas, termina con cinco
  /// motores vivos de los que está usando uno.
  ///
  /// Pero soltarlo enseguida sería peor: entrar a una zona, salir y volver
  /// costaría levantarlo de nuevo cada vez. La ventana tiene que ser más larga
  /// que un paseo por el menú y más corta que una sesión.
  ///
  /// Un minuto en un aparato modesto, donde la memoria es lo escaso; cinco en
  /// uno capaz, donde lo escaso es la paciencia.
  static Duration get cuantoDuraUnMotorSinUsar => switch (nivel) {
        // Medio minuto en el aparato justo: con uno entero, pasear por dos
        // zonas dejaba media docena de motores esperando su turno de
        // barrido mientras el sistema ya pedía memoria.
        NivelDeAparato.bajo => const Duration(seconds: 30),
        NivelDeAparato.medio => const Duration(minutes: 3),
        NivelDeAparato.alto => const Duration(minutes: 5),
      };

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
