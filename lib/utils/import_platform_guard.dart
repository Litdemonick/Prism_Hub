import 'dart:io';

import 'package:prismhub/utils/platform_tv.dart';

/// Si la importación masiva está disponible en esta plataforma.
///
/// Solo Android (móvil/tablet) y PC (Windows/Linux/Mac). Explícitamente
/// bloqueada en Android TV: no hay teclado ni portapapeles accesible con
/// un control remoto, y la UI de la caja de texto no tiene sentido ahí.
bool get importDisponible =>
    !PlatformTv.esTelevisionSync &&
    (Platform.isAndroid || Platform.isWindows || Platform.isLinux || Platform.isMacOS);
