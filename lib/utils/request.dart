import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter_socks_proxy/socks_proxy.dart';
import 'package:prismhub/utils/prismhub_directory.dart';
import 'package:prismhub/utils/prismhub_storage.dart';

late final Dio dio;

class PrismRequest {
  static final _cookieJar = PersistCookieJar(
    ignoreExpires: true,
    storage: FileStorage("${PrismHubDirectory.getDirectory}/.cookies/"),
  );

  static bool _isInitialized = false;

  static Future<void> ensureInitialized() async {
    // Sin connectTimeout, Dio espera indefinidamente a que abra la conexión.
    // En redes restrictivas (ej. universidad con proxy/inspección SSL o DNS
    // lento) eso nunca falla ni se reintenta — para el usuario, "la extensión
    // no carga" y se queda así para siempre. NO se fija receiveTimeout acá:
    // este mismo cliente se usa para descargas grandes (actualización de la
    // app, binario de bt-server) y un límite global de recepción las cortaría
    // a mitad de camino en una red lenta. Los fetches chicos (catálogo de
    // extensiones, scripts) le ponen su propio receiveTimeout por request.
    dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 15),
    ));
    final cookieManager = CookieManager(_cookieJar);
    dio.interceptors.add(cookieManager);
    refreshProxy();
    _isInitialized = true;
  }

  static refreshProxy() {
    String proxy = "";
    final type = PrismHubStorage.getSetting(SettingKey.proxyType);
    if (type == "DIRECT") {
      proxy = type;
    } else {
      proxy = '$type ${PrismHubStorage.getSetting(SettingKey.proxy)}';
    }

    if (!_isInitialized) {
      SocksProxy.initProxy(proxy: proxy);
      return;
    }
    SocksProxy.setProxy(proxy);
  }

  static Future<void> cleanCookie(String url) async {
    await _cookieJar.delete(Uri.parse(url));
  }

  static Future<void> setCookie(String cookies, String url) async {
    final cookieList = cookies.split(';');
    for (final cookie in cookieList) {
      await _cookieJar.saveFromResponse(
        Uri.parse(url),
        [Cookie.fromSetCookieValue(cookie)],
      );
    }
  }

  static Future<String> getCookie(String url) async {
    final cookies = await _cookieJar.loadForRequest(Uri.parse(url));
    return cookies.map((e) => e.toString()).join(';');
  }

  // Dio+CookieJar aislados por extensión — antes TODAS las extensiones
  // compartían el mismo `dio`/`_cookieJar` de arriba. Una extensión puede
  // pedir cualquier URL (su propio request() deja pisar el destino con el
  // header "Miru-Url", y el puente sendMessage('request',...) del SDK ni
  // eso — el string que llega es lo que se pide, sin restricción de
  // dominio), así que con un jar compartido, la extensión A podía apuntar
  // al dominio de la extensión B y la respuesta volvía con las cookies de
  // sesión de B adjuntas — robo de sesión entre extensiones. Un Dio nuevo
  // hereda el proxy vigente solo (SocksProxy parchea HttpOverrides.global,
  // a nivel de proceso — confirmado leyendo su fuente), así que no hace
  // falta replicar refreshProxy() acá.
  static final Map<String, Dio> _extensionDios = {};
  static final Map<String, PersistCookieJar> _extensionCookieJars = {};

  static PersistCookieJar cookieJarForPackage(String package) {
    return _extensionCookieJars.putIfAbsent(
      package,
      () => PersistCookieJar(
        ignoreExpires: true,
        storage: FileStorage(
          "${PrismHubDirectory.getDirectory}/.cookies_ext/$package/",
        ),
      ),
    );
  }

  static Dio dioForPackage(String package) {
    return _extensionDios.putIfAbsent(package, () {
      final d = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(seconds: 15),
      ));
      d.interceptors.add(CookieManager(cookieJarForPackage(package)));
      return d;
    });
  }

  static Future<void> cleanCookieForPackage(String package, String url) async {
    await cookieJarForPackage(package).delete(Uri.parse(url));
  }

  static Future<void> setCookieForPackage(
      String package, String cookies, String url) async {
    final cookieList = cookies.split(';');
    for (final cookie in cookieList) {
      await cookieJarForPackage(package).saveFromResponse(
        Uri.parse(url),
        [Cookie.fromSetCookieValue(cookie)],
      );
    }
  }

  static Future<String> getCookieForPackage(String package, String url) async {
    final cookies = await cookieJarForPackage(package).loadForRequest(Uri.parse(url));
    return cookies.map((e) => e.toString()).join(';');
  }
}
