import 'dart:convert';
import 'dart:typed_data';

import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;

/// Verificación de firma de extensiones (Ed25519).
///
/// prism+ firma cada extensión oficial con su llave PRIVADA. PrismHub trae aquí
/// embebida la llave PÚBLICA y verifica la firma antes de instalar:
///
///  - Firma válida (de prism+)      → extensión OFICIAL, verificada ✅
///  - Firma presente pero inválida  → fue alterada/manipulada → se RECHAZA ❌
///  - Sin firma                     → extensión EXTERNA (sideload/otro repo),
///                                    permitida pero NO verificada ⚠️
///
/// PrismHub es open source y permite instalar extensiones de terceros; la firma
/// no las bloquea, solo distingue lo oficial de prism+ de lo externo y evita que
/// alguien falsifique una "oficial".
class ExtensionSignature {
  ExtensionSignature._();

  /// Llave pública oficial de prism+ (Ed25519, 32 bytes en hex).
  /// Generada con `npm run keygen` en prism+. La privada nunca sale de la
  /// máquina del mantenedor.
  static const String officialPublicKeyHex =
      '7f676280d790608cbad2e35518ea397f8dcf7437e5a2129d86b68ae7141214ae';

  static final ed.PublicKey _publicKey =
      ed.PublicKey(_hexToBytes(officialPublicKeyHex));

  static List<int> _hexToBytes(String hex) {
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  /// True si [signatureBase64] es una firma Ed25519 válida de prism+ sobre [js].
  ///
  /// Normaliza CRLF→LF para que la firma sea estable sin importar cómo el repo o
  /// el CDN sirvan los saltos de línea (la firma se calcula sobre LF).
  static bool isOfficial(String js, String? signatureBase64) {
    if (signatureBase64 == null || signatureBase64.isEmpty) return false;
    try {
      final message = utf8.encode(js.replaceAll('\r\n', '\n'));
      final signature = base64.decode(signatureBase64);
      if (signature.length != 64) return false;
      return ed.verify(_publicKey, Uint8List.fromList(message),
          Uint8List.fromList(signature));
    } catch (_) {
      return false;
    }
  }
}
