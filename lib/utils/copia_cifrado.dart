import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Pone y saca la clave de una copia de seguridad.
///
/// El archivo lleva el historial completo, incluido el de la Zona +18. Eso es
/// exactamente lo que nadie quiere que se lea si el archivo termina en una
/// carpeta compartida, en la nube o en un teléfono prestado. Con clave, el
/// archivo por sí solo no dice nada.
///
/// Se usa **AES-GCM**, que además de ocultar el contenido detecta si el archivo
/// fue tocado: si le cambiaron un byte, falla al abrirlo en vez de devolver
/// datos a medias que después se meterían en la base.
///
/// La clave del usuario no se usa directamente: se pasa por **PBKDF2** con
/// muchas vueltas y una sal distinta en cada archivo. Eso es lo que hace que
/// probar claves a lo bruto sea lento, y que la misma clave en dos copias no
/// produzca el mismo resultado.
class CopiaCifrado {
  /// Vueltas de PBKDF2.
  ///
  /// Alto a propósito: es lo único que separa una clave corta de que la
  /// adivinen probando. Se paga una sola vez al exportar o importar —una espera
  /// de fracciones de segundo— y encarece cada intento de quien no la sepa.
  static const _vueltas = 150000;

  /// 32 bytes = AES-256.
  static const _largoClave = 32;
  static const _largoSal = 16;

  /// 12 bytes es el tamaño con el que GCM está pensado para trabajar.
  static const _largoNonce = 12;

  /// 128 bits de etiqueta: es lo que detecta que el archivo fue modificado.
  static const _bitsEtiqueta = 128;

  static final _azar = Random.secure();

  static Uint8List _bytesAlAzar(int cuantos) => Uint8List.fromList(
      List<int>.generate(cuantos, (_) => _azar.nextInt(256)));

  static Uint8List _derivar(String clave, Uint8List sal) {
    final kdf = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(sal, _vueltas, _largoClave));
    return kdf.process(Uint8List.fromList(utf8.encode(clave)));
  }

  static GCMBlockCipher _motor(
      Uint8List clave, Uint8List nonce, bool cifrando) {
    return GCMBlockCipher(AESEngine())
      ..init(
        cifrando,
        AEADParameters(
          KeyParameter(clave),
          _bitsEtiqueta,
          nonce,
          Uint8List(0),
        ),
      );
  }

  /// Cierra un texto con la clave. Devuelve la sal, el nonce y el resultado,
  /// todo en base64 para que quepa en el archivo de texto.
  static ({String sal, String nonce, String datos}) cerrar(
      String texto, String clave) {
    // Sal y nonce NUEVOS en cada archivo. Repetir el nonce con la misma clave
    // es lo único que rompe GCM de verdad, así que no se reutilizan nunca.
    final sal = _bytesAlAzar(_largoSal);
    final nonce = _bytesAlAzar(_largoNonce);
    final cerrado = _motor(_derivar(clave, sal), nonce, true)
        .process(Uint8List.fromList(utf8.encode(texto)));
    return (
      sal: base64Encode(sal),
      nonce: base64Encode(nonce),
      datos: base64Encode(cerrado),
    );
  }

  /// Abre lo que cerró [cerrar]. Devuelve null si la clave no es la correcta o
  /// si el archivo está dañado — para quien llama son el mismo caso: no se
  /// puede leer, y no hay forma de distinguirlos sin arriesgarse a usar datos
  /// que no son.
  static String? abrir({
    required String sal,
    required String nonce,
    required String datos,
    required String clave,
  }) {
    try {
      final abierto = _motor(
        _derivar(clave, base64Decode(sal)),
        base64Decode(nonce),
        false,
      ).process(base64Decode(datos));
      return utf8.decode(abierto);
    } catch (_) {
      // Con la clave equivocada, GCM no devuelve basura: falla la comprobación
      // de la etiqueta y salta. Es justo lo que queremos.
      return null;
    }
  }
}
