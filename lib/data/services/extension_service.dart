import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_js/extensions/fetch.dart';
import 'package:get/get.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart';
import 'package:prismhub/data/services/extension_jscore_plugin.dart';
import 'package:prismhub/data/services/stream_sniffer_service.dart';
import 'package:prismhub/utils/log.dart';
import 'package:prismhub/utils/prismhub_storage.dart';
import 'package:prismhub/utils/request.dart';
import 'package:xpath_selector_html_parser/xpath_selector_html_parser.dart';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_js/flutter_js.dart';
import 'package:prismhub/models/index.dart';
import 'package:prismhub/data/services/database_service.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/utils/search_text.dart';
import 'package:flutter_js/javascriptcore/jscore_runtime.dart';

class ExtensionService {
  late JavascriptRuntime runtime;
  late Extension extension;
  String evalString = '';
  late JsBridge jsBridge;
  static Map<dynamic, dynamic> evalMap = {};
  static Future<List<String>>? _coreScriptsFuture;
  String className = '';
  bool isinit = false;

  static Future<List<String>> _loadCoreScripts() {
    return _coreScriptsFuture ??= Future.wait([
      rootBundle.loadString('assets/js/CryptoJS.min.js'),
      rootBundle.loadString('assets/js/jsencrypt.min.js'),
      rootBundle.loadString('assets/js/md5.min.js'),
    ]);
  }

  /// Levanta el motor de esta extensión.
  ///
  /// [rutaGuion] existe para la vista previa del Home: esas extensiones NO
  /// están instaladas y su guion vive en otra carpeta, porque cualquier `.js`
  /// dentro de `extensionsDir` se considera instalado (hay un escaneo y hasta
  /// un vigilante de esa carpeta). Sin este parámetro, previsualizar una
  /// extensión sería instalarla por la puerta de atrás.
  /// Deja la extensión LISTA PARA USAR, pero sin levantar su motor todavía.
  ///
  /// ── Por qué el motor no se crea acá ─────────────────────────────────────
  ///
  /// Cada extensión tiene su propio motor de JavaScript, y levantarlo no es
  /// barato: además del guion de la extensión, ese motor evalúa CryptoJS,
  /// jsencrypt y md5 — unos 148 KB de JavaScript minificado que hay que
  /// analizar y dejar en memoria. Por motor.
  ///
  /// Antes se levantaban TODOS al arrancar la app. Con diecinueve extensiones
  /// instaladas eso son diecinueve copias de esas tres librerías vivas desde
  /// el primer segundo, más diecinueve pilas de un mega. Medido en un
  /// televisor de 0,9 GB con trece extensiones: el sistema pidió memoria
  /// cuatro veces en los primeros cuarenta segundos, y los cuadros lentos de
  /// la app se concentraban justo en esa ventana.
  ///
  /// Y la mayoría no se usa nunca en una sesión: se abre la app, se mira una
  /// zona y se reproduce algo de UNA extensión.
  ///
  /// Lo que sí se hace acá es todo lo barato —leer el nombre, la versión, el
  /// tipo, los ajustes declarados— porque de eso viven el catálogo, la
  /// pantalla de extensiones y los filtros, y todo eso tiene que estar listo
  /// sin tocar un solo motor.
  ///
  /// El motor se levanta solo la primera vez que se le pide algo a la
  /// extensión. Ver [asegurarMotor].
  initRuntime(Extension ext, {String? rutaGuion}) async {
    extension = ext;
    className = extension.package.replaceAll('.', '');
    // example: if the package name is com.example.extension the class name will be comexampleextension
    // but if  the package name is 9anime.to the class name will be animetoRenamed

    if (!className.isAlphabetOnly) {
      className = "${className.replaceAll(RegExp(r'[^a-zA-z]'), '')}Renamed";
    }
    _rutaGuion = rutaGuion;
    return this;
  }

  /// De dónde sale el guion. Null es «de la carpeta de instaladas».
  String? _rutaGuion;

  /// Si el motor de esta extensión ya está levantado.
  bool get motorListo => _motorListo;
  bool _motorListo = false;

  /// Lo que está levantando el motor ahora mismo, si hay algo.
  ///
  /// Sin esto, dos llamadas a la vez —que es lo normal: el Home pide varias
  /// zonas juntas— levantarían dos motores para la misma extensión y el
  /// segundo pisaría al primero, dejando el primero vivo y sin dueño.
  Future<void>? _levantando;

  /// Levanta el motor si hace falta. Barato de llamar de más.
  Future<void> asegurarMotor() {
    if (_motorListo) return Future<void>.value();
    return _levantando ??= _levantarMotor().whenComplete(() {
      _levantando = null;
    });
  }

  Future<void> _levantarMotor() async {
    final rutaGuion = _rutaGuion;
    // 读取文件
    final file = File(
        rutaGuion ?? '${ExtensionUtils.extensionsDir}/${extension.package}.js');
    final content = await file.readAsString();

    // 初始化runtime
    if (Platform.isAndroid) {
      runtime = QuickJsRuntime2(stackSize: 1024 * 1024);
    } else if (Platform.isWindows || Platform.isLinux) {
      runtime = QuickJsRuntime2();
    } else {
      runtime = JavascriptCoreRuntime();
    }
    runtime.enableFetch();
    runtime.enableHandlePromises();

    jsLog(dynamic args) {
      // No se escribe aca: addLog ya lo manda al registro unico, y con el
      // paquete adelante. Hacerlo en los dos sitios dejaba cada console.log
      // de las extensiones dos veces en el archivo.
      ExtensionUtils.addLog(
        extension,
        ExtensionLogLevel.info,
        args[0],
      );
    }

    jsRequest(dynamic args) async {
      final headers = args[1]['headers'] ?? {};
      if (headers['User-Agent'] == null) {
        headers['User-Agent'] = PrismHubStorage.getUASetting();
      }

      final url = args[0];
      final method = args[1]['method'] ?? 'get';
      final requestBody = args[1]['data'];

      final log = ExtensionNetworkLog(
        extension: extension,
        url: args[0],
        method: method,
        requestHeaders: headers,
      );
      final key = UniqueKey().toString();
      ExtensionUtils.addNetworkLog(
        key,
        log,
      );

      try {
        final res =
            await PrismRequest.dioForPackage(extension.package).request<String>(
          url,
          data: requestBody,
          queryParameters: args[1]['queryParameters'] ?? {},
          options: Options(
            headers: headers,
            method: method,
            // No tirar excepción por un status code "raro" (4xx/5xx) — varios
            // sitios devuelven el HTML real y útil bajo un status no-2xx por
            // algún detalle de su propio ruteo (confirmado en vivo dos veces:
            // animeytx pasándose de la última página real, animejara
            // paginando/filtrando su catálogo por género — ambos con 404
            // pero cuerpo perfectamente válido). Antes esto se perdía ANTES
            // de que la extensión llegara a verlo. Los fallos de red de
            // verdad (timeout, DNS, conexión rechazada) siguen tirando
            // DioException igual — eso no depende de validateStatus.
            validateStatus: (_) => true,
            // El cliente Dio global no fija receiveTimeout (se usa también
            // para descargas grandes, ver request.dart) — pero jsRequest es
            // el puente de red de TODAS las extensiones (latest/search/
            // detail/watch), siempre páginas/JSON chicos. Sin este límite,
            // un sitio que acepta la conexión pero se cuelga a mitad de
            // respuesta deja esperando para siempre, sin ningún timeout que
            // lo rescate — el reproductor queda pegado en "Obteniendo
            // enlace..." sin forma de recuperarse salvo cerrar la app.
            // 25s y no 20: margen extra para sitios servidos desde lejos con
            // latencia alta (mismo motivo que el connectTimeout de
            // request.dart).
            receiveTimeout: const Duration(seconds: 25),
          ),
        );
        log.requestHeaders = res.requestOptions.headers;
        log.responseBody = res.data;
        log.responseHeaders = res.headers.map.map(
          (key, value) => MapEntry(
            key,
            value.join(';'),
          ),
        );
        log.statusCode = res.statusCode;

        ExtensionUtils.addNetworkLog(
          key,
          log,
        );
        return res.data;
      } on DioException catch (e) {
        log.url = e.requestOptions.uri.toString();
        log.requestHeaders = e.requestOptions.headers;
        log.responseBody = e.response?.data;
        log.responseHeaders = e.response?.headers.map.map(
          (key, value) => MapEntry(
            key,
            value.join(';'),
          ),
        );
        log.statusCode = e.response?.statusCode;
        ExtensionUtils.addNetworkLog(
          key,
          log,
        );
        rethrow;
      }
    }

    // Respaldo de jsRequest para sitios que bloquean el pedido HTTP directo
    // (Dio no corre JavaScript, así que un desafío tipo Cloudflare "Just a
    // moment..." le llega a la extensión como si fuera la respuesta real —
    // ver StreamSnifferService.renderHtml). Mucho más lento a propósito: la
    // extensión lo pide solo cuando ya notó que jsRequest volvió bloqueada,
    // no en cada pedido.
    jsRequestViaWebview(dynamic args) async {
      final url = args[0].toString();
      final headers = (args.length > 1 && args[1] is Map)
          ? Map<String, dynamic>.from(args[1]['headers'] ?? {})
          : <String, dynamic>{};
      final referer = headers['Referer']?.toString();

      final log = ExtensionNetworkLog(
        extension: extension,
        url: url,
        method: 'GET (webview)',
        requestHeaders: headers,
      );
      final key = UniqueKey().toString();
      ExtensionUtils.addNetworkLog(key, log);

      final html = await StreamSnifferService.renderHtml(url, referer: referer);
      log.responseBody = html;
      log.statusCode = html != null ? 200 : null;
      ExtensionUtils.addNetworkLog(key, log);
      return html ?? '';
    }

    jsRegisterSetting(dynamic args) async {
      args[0]['package'] = extension.package;

      return DatabaseService.registerExtensionSetting(
        ExtensionSetting()
          ..package = extension.package
          ..title = args[0]['title']
          ..key = args[0]['key']
          ..value = args[0]['value']
          ..type = ExtensionSetting.stringToType(args[0]['type'])
          ..description = args[0]['description']
          ..defaultValue = args[0]['defaultValue']
          ..options = jsonEncode(args[0]['options']),
      );
    }

    jsGetMessage(dynamic args) async {
      final setting =
          await DatabaseService.getExtensionSetting(extension.package, args[0]);
      return setting!.value ?? setting.defaultValue;
    }

    jsCleanSettings(dynamic args) async {
      // debugPrint('cleanSettings: ${args[0]}');
      return DatabaseService.cleanExtensionSettings(
          extension.package, List<String>.from(args[0]));
    }

    jsQuerySelector(dynamic args) {
      final content = args[0];
      final selector = args[1];
      final fun = args[2];

      final doc = parse(content).querySelector(selector);
      String result = '';
      switch (fun) {
        case 'text':
          result = doc?.text ?? '';
        case 'outerHTML':
          result = doc?.outerHtml ?? '';
        case 'innerHTML':
          result = doc?.innerHtml ?? '';
        default:
          result = doc?.outerHtml ?? '';
      }
      return result;
    }

    jsQueryXPath(args) {
      final content = args[0];
      final selector = args[1];
      final fun = args[2];

      final xpath = HtmlXPath.html(content);
      final result = xpath.queryXPath(selector);
      String returnVal = '';
      switch (fun) {
        case 'attr':
          returnVal = result.attr ?? '';
        case 'attrs':
          returnVal = jsonEncode(result.attrs);
        case 'text':
          returnVal = result.node?.text ?? '';
        case 'allHTML':
          returnVal = result.nodes
              .map((e) => (e.node as Element).outerHtml)
              .toList()
              .toString();
        case 'outerHTML':
          returnVal = (result.node?.node as Element).outerHtml;
        default:
          returnVal = result.node?.text ?? "";
      }
      return returnVal;
    }

    jsRemoveSelector(dynamic args) {
      final content = args[0];
      final selector = args[1];
      final doc = parse(content);
      doc.querySelectorAll(selector).forEach((element) {
        element.remove();
      });
      return doc.outerHtml;
    }

    jsGetAttributeText(args) {
      final content = args[0];
      final selector = args[1];
      final attr = args[2];
      final doc = parse(content).querySelector(selector);
      return doc?.attributes[attr];
    }

    jsQuerySelectorAll(dynamic args) async {
      final content = args["content"];
      final selector = args["selector"];
      final doc = parse(content).querySelectorAll(selector);
      final elements = jsonEncode(doc.map((e) {
        return e.outerHtml;
      }).toList());
      return elements;
    }

    runtime.onMessage('getSetting', (dynamic args) => jsGetMessage(args));
    // 日志
    runtime.onMessage('log', (args) => jsLog(args));
    // 请求
    runtime.onMessage('request', (args) => jsRequest(args));
    // Respaldo vía WebView (ver jsRequestViaWebview)
    runtime.onMessage('requestViaWebview', (args) => jsRequestViaWebview(args));
    // 设置
    runtime.onMessage('registerSetting', (args) => jsRegisterSetting(args));
    // 清理扩展设置
    runtime.onMessage('cleanSettings', (dynamic args) => jsCleanSettings(args));
    // xpath 选择器
    runtime.onMessage('queryXPath', (arg) => jsQueryXPath(arg));
    runtime.onMessage('removeSelector', (args) => jsRemoveSelector(args));
    // 获取标签属性
    runtime.onMessage('getAttributeText', (args) => jsGetAttributeText(args));
    runtime.onMessage(
        'querySelectorAll', (dynamic args) => jsQuerySelectorAll(args));
    // css 选择器
    runtime.onMessage('querySelector', (arg) => jsQuerySelector(arg));
    if (Platform.isLinux) {
      handleDartBridge(String channelName, Function fn) {
        jsBridge.setHandler(channelName, (message) async {
          try {
            final args = jsonDecode(message);
            final result = await fn(args);
            await jsBridge.sendMessage(channelName, result);
          } catch (e) {
            // Send null so the JS promise resolves instead of hanging forever,
            // which would crash the JavascriptCore runtime on Linux.
            try {
              await jsBridge.sendMessage(channelName, null);
            } catch (_) {}
          }
        });
      }

      jsBridge = JsBridge(jsRuntime: runtime);
      handleDartBridge('cleanSettings$className', jsCleanSettings);
      handleDartBridge('request$className', jsRequest);
      handleDartBridge('requestViaWebview$className', jsRequestViaWebview);
      handleDartBridge('log$className', jsLog);
      handleDartBridge('queryXPath$className', jsQueryXPath);
      handleDartBridge('removeSelector$className', jsRemoveSelector);
      handleDartBridge("getAttributeText$className", jsGetAttributeText);
      handleDartBridge('querySelectorAll$className', jsQuerySelectorAll);
      handleDartBridge('querySelector$className', jsQuerySelector);
      handleDartBridge('registerSetting$className', jsRegisterSetting);
      handleDartBridge('getSetting$className', jsGetMessage);
    }
    // 初始化运行扩展
    await _initRunExtension(content);
    _motorListo = true;
  }

  _initRunExtension(String extScript) async {
    final coreScripts = await _loadCoreScripts();
    final cryptoJs = coreScripts[0];
    final jsencrypt = coreScripts[1];
    final md5 = coreScripts[2];
    runtime.evaluate(Platform.isLinux
        ? '''
$cryptoJs
$jsencrypt
$md5
class Element {
  constructor(content, selector) {
    this.content = content;
    this.selector = selector || "";
  }
  async querySelector(selector) {
    return new Element(await this.execute(), selector);
  }

  async execute(fun) {
    return await handlePromise("querySelector$className",JSON.stringify([this.content, this.selector, fun]));
  }

  async removeSelector(selector) {
    this.content = await handlePromise("removeSelector$className",JSON.stringify([await this.outerHTML, selector]));
    return this;
  }

  async getAttributeText(attr) {
    return await handlePromise("getAttributeText$className",JSON.stringify([await this.outerHTML, this.selector, attr]));
  }

  get text() {
    return this.execute("text");
  }

  get outerHTML() {
    return this.execute("outerHTML");
  }

  get innerHTML() {
    return this.execute("innerHTML");
  }
}
class XPathNode {
  constructor(content, selector) {
    this.content = content;
    this.selector = selector;
  }

  async excute(fun) {
    return await handlePromise("queryXPath$className",JSON.stringify([this.content, this.selector, fun]));
  }

  get attr() {
    return this.excute("attr");
  }

  get attrs() {
    return this.excute("attrs");
  }

  get text() {
    return this.excute("text");
  }
  
  get allHTML() {
    return this.excute("allHTML");
  }

  get outerHTML() {
    return this.excute("outerHTML");
  }
}

// 重写 console.log
console.log = function (message) {
  if (typeof message === "object") {
    message = JSON.stringify(message);
  }
  DartBridge.sendMessage("log$className", JSON.stringify([message.toString()]));
};
class Extension {
  package = "${extension.package}";
  name = "${extension.name}";
  // 在 load 中注册的 keys
  settingKeys = [];
  
  querySelector(content, selector) {
    return new Element(content, selector);
  }
   async request(url, options) {
    options = options || {};
    options.headers = options.headers || {};
    const miruUrl = options.headers["Miru-Url"] || "${extension.webSite}";
    options.method = options.method || "get";
    const message = await handlePromise("request$className",JSON.stringify([miruUrl + url, options,"${extension.package}"]));
    try {
      return JSON.parse(message);
    }catch(e){
      return message;
    }
  }
  queryXPath(content, selector) {
    return new XPathNode(content, selector);
  }
  async querySelectorAll(content, selector) {
    const arg = await handlePromise("querySelectorAll$className",JSON.stringify({content:content, selector:selector}));
    const message = JSON.parse(arg);
    const elements = [];
    for(const e of message){
      elements.push(new Element(e, selector));
    }
    return elements;
  }
  async getAttributeText(content, selector, attr) {
    const waitForChange  = new Promise(resolve=>{DartBridge.setHandler("getAttributeText$className", async (arg) => {
      resolve(arg);
    })});
    DartBridge.sendMessage("getAttributeText$className",  JSON.stringify([content, selector, attr]));
    const elements = await waitForChange;
    return elements;
  }
  latest(page) {
    throw new Error("not implement latest");
  }
  search(kw, page, filter) {
    throw new Error("not implement search");
  }
  createFilter(filter){
    throw new Error("not implement createFilter");
  }
  detail(url) {
    throw new Error("not implement detail");
  }
  watch(url) {
    throw new Error("not implement watch");
  }
  checkUpdate(url) {
    throw new Error("not implement checkUpdate");
  }
  top(filter, page) {
    throw new Error("not implement top");
  }
  createTopFilter(){
    throw new Error("not implement createTopFilter");
  }
  async getSetting(key) {
    return await handlePromise("getSetting$className",JSON.stringify([key]));
  }
  async registerSetting(settings) {
    this.settingKeys.push(settings.key);
    return await handlePromise("registerSetting$className",JSON.stringify([settings]));
  }
  async load() {}
}
async function handlePromise(channelName,message){
  const waitForChange  = new Promise(resolve=>{DartBridge.setHandler(channelName, async (arg) => {
    resolve(arg);
  })});
  DartBridge.sendMessage(channelName,  message);
  return await waitForChange
}
async function stringify(callback) {
  const data = await callback();
  return typeof data === "object" ? JSON.stringify(data,0,2) : data;
}



            '''
        : '''
          // 重写 console.log
          var window = (global = globalThis);
          $cryptoJs
          $jsencrypt
          $md5
          class Element {
            constructor(content, selector) {
              this.content = content;
              this.selector = selector || "";
            }

            async querySelector(selector) {
              return new Element(await this.excute(), selector);
            }

            async excute(fun) {
              return await sendMessage(
                "querySelector",
                JSON.stringify([this.content, this.selector, fun])
              );
            }

            async removeSelector(selector) {
              this.content = await sendMessage(
                "removeSelector",
                JSON.stringify([await this.outerHTML, selector])
              );
              return this;
            }

            async getAttributeText(attr) {
              return await sendMessage(
                "getAttributeText",
                JSON.stringify([await this.outerHTML, this.selector, attr])
              );
            }

            get text() {
              return this.excute("text");
            }

            get outerHTML() {
              return this.excute("outerHTML");
            }

            get innerHTML() {
              return this.excute("innerHTML");
            }
          }
          class XPathNode {
            constructor(content, selector) {
              this.content = content;
              this.selector = selector;
            }

            async excute(fun) {
              return await sendMessage(
                "queryXPath",
                JSON.stringify([this.content, this.selector, fun])
              );
            }

            get attr() {
              return this.excute("attr");
            }

            get attrs() {
              return this.excute("attrs");
            }

            get text() {
              return this.excute("text");
            }
            
            get allHTML() {
              return this.excute("allHTML");
            }

            get outerHTML() {
              return this.excute("outerHTML");
            }
          }

          
          console.log = function (message) {
            if (typeof message === "object") {
              message = JSON.stringify(message);
            }
            sendMessage("log", JSON.stringify([message.toString()]));
          };
          class Extension {
            package = "${extension.package}";
            name = "${extension.name}";
            // 在 load 中注册的 keys
            settingKeys = [];
            async request(url, options) {
              options = options || {};
              options.headers = options.headers || {};
              const miruUrl = options.headers["Miru-Url"] || "${extension.webSite}";
              options.method = options.method || "get";
              const res = await sendMessage(
                "request",
                JSON.stringify([miruUrl + url, options])
              );
              try {
                return JSON.parse(res);
              } catch (e) {
                return res;
              }
            }
            querySelector(content, selector) {
              return new Element(content, selector);
            }
            queryXPath(content, selector) {
              return new XPathNode(content, selector);
            }
            async querySelectorAll(content, selector) {
              let elements = [];
              JSON.parse(
                await sendMessage("querySelectorAll", JSON.stringify({content:content,selector:selector}))
              ).forEach((e) => {
                elements.push(new Element(e, selector));
              });
              return elements;
            }
            async getAttributeText(content, selector, attr) {
              return await sendMessage(
                "getAttributeText",
                JSON.stringify([content, selector, attr])
              );
            }
            popular(page) {
              throw new Error("not implement popular");
            }
            latest(page) {
              throw new Error("not implement latest");
            }
            search(kw, page, filter) {
              throw new Error("not implement search");
            }
            createFilter(filter){
              throw new Error("not implement createFilter");
            }
            detail(url) {
              throw new Error("not implement detail");
            }
            watch(url) {
              throw new Error("not implement watch");
            }
            checkUpdate(url) {
              throw new Error("not implement checkUpdate");
            }
            top(filter, page) {
              throw new Error("not implement top");
            }
            createTopFilter(){
              throw new Error("not implement createTopFilter");
            }
            async getSetting(key) {
              return sendMessage("getSetting", JSON.stringify([key]));
            }
            async registerSetting(settings) {
              this.settingKeys.push(settings.key);
              return sendMessage("registerSetting", JSON.stringify([settings]));
            }
            async load() {}
          }

          async function stringify(callback) {
            const data = await callback();
            return typeof data === "object" ? JSON.stringify(data,0,2) : data;
          }
    ''');

    final ext = extScript.replaceAll(RegExp(r'export default class.*'),
        'class $className extends Extension {');

    runtime.evaluate('''
      $ext
      if(typeof ${className}Instance !== 'undefined'){
        delete ${className}Instance;
      }
      var ${className}Instance = new $className();
      ${className}Instance.load().then(()=>{
        if(${Platform.isLinux}){
           DartBridge.sendMessage("cleanSettings$className",JSON.stringify([extension.settingKeys]));
        }
        sendMessage("cleanSettings", JSON.stringify([extension.settingKeys]));
      });
    ''');
    isinit = true;
  }

  // 清理 cookie
  cleanCookie() async {
    await PrismRequest.cleanCookieForPackage(
        extension.package, extension.webSite);
  }

  /// 添加 cookie
  /// key=value; key=value
  setCookie(String cookies) async {
    await PrismRequest.setCookieForPackage(
        extension.package, cookies, extension.webSite);
  }

  // 列出所有的 cookie
  Future<String> listCookie() async {
    return await PrismRequest.getCookieForPackage(
        extension.package, extension.webSite);
  }

  Future<T> runExtension<T>(Future<T> Function() fun) async {
    try {
      // El motor se levanta acá, la primera vez que de verdad hace falta.
      //
      // Este es el paso obligado de TODAS las llamadas a la extensión —listar,
      // buscar, la ficha, el enlace de vídeo—, así que poniéndolo acá no queda
      // ningún camino por el que se le pida algo a un motor que no está.
      await asegurarMotor();
      return await fun();
    } catch (e) {
      ExtensionUtils.addLog(
        extension,
        ExtensionLogLevel.error,
        e.toString(),
      );
      rethrow;
    }
  }

  // Antes usaba _cuurentRequestUrl, un campo de instancia que jsRequest
  // pisaba en CADA request — con dos llamadas concurrentes a esta misma
  // extensión (ej. Home pidiendo latest() mientras Detail pide detail()
  // para la misma extensión, comparten la única instancia de
  // ExtensionService por package), el Referer de una podía terminar
  // reflejando la URL de la otra. extension.webSite es estable y no
  // depende de qué request haya corrido último.
  Future<Map<String, String>> get _defaultHeaders async {
    return {
      "Referer": extension.webSite,
      "User-Agent": PrismHubStorage.getUASetting(),
      "Cookie": await listCookie(),
    };
  }

  // Las extensiones son código de terceros: pueden devolver algo que no es
  // una lista, elementos que no son objetos, o un ítem sin título (que en
  // ExtensionListItem es un String obligatorio, así que fromJson tira "type
  // 'Null' is not a subtype of type 'String'"). Con un .map() pelado, UN
  // ítem malo hacía fallar la tanda ENTERA: la extensión se veía como si no
  // tuviera nada. Se descarta lo que no se puede leer y se conserva el resto,
  // que es lo que el usuario quiere ver.
  List<ExtensionListItem> _parseListItems(dynamic decoded) {
    if (decoded is! List) {
      logger.warning(
          '${extension.package}: se esperaba una lista y llegó ${decoded.runtimeType}');
      return const [];
    }
    final items = <ExtensionListItem>[];
    var descartados = 0;
    for (final e in decoded) {
      if (e is! Map) {
        descartados++;
        continue;
      }
      try {
        items.add(ExtensionListItem.fromJson(Map<String, dynamic>.from(e)));
      } catch (_) {
        descartados++;
      }
    }
    if (descartados > 0) {
      logger.warning(
          '${extension.package}: $descartados ítem(s) con formato inválido descartados');
    }
    return items;
  }

  // Mismo criterio que _parseListItems: un filtro mal armado descarta ESE
  // filtro, no los demás. Antes bastaba con uno malo para que el botón de
  // filtros de esa extensión no abriera nada.
  Map<String, ExtensionFilter> _parseFilters(dynamic decoded) {
    if (decoded is! Map) return {};
    final filters = <String, ExtensionFilter>{};
    decoded.forEach((key, value) {
      if (key is! String || value is! Map) return;
      try {
        filters[key] =
            ExtensionFilter.fromJson(Map<String, dynamic>.from(value));
      } catch (_) {
        logger.warning('${extension.package}: filtro "$key" inválido');
      }
    });
    return filters;
  }

  Future<dynamic> _decodeJsonResult(String source) {
    if (source.length < 4096) {
      return Future.value(jsonDecode(source));
    }
    return compute(jsonDecode, source);
  }

  Future<void> _fillMissingHeaders(List<ExtensionListItem> result) async {
    if (result.isEmpty || result.every((element) => element.headers != null)) {
      return;
    }
    final headers = await _defaultHeaders;
    for (var element in result) {
      element.headers ??= headers;
    }
  }

  Future<List<ExtensionListItem>> latest(int page) async {
    return runExtension(() async {
      final jsResult = await runtime.handlePromise(
        await runtime
            .evaluateAsync('stringify(()=>${className}Instance.latest($page))'),
      );

      final decoded = await _decodeJsonResult(jsResult.stringResult);
      final result = _parseListItems(decoded);
      await _fillMissingHeaders(result);
      return result;
    });
  }

  Future<List<ExtensionListItem>> search(
    String kw,
    int page, {
    Map<String, List<String>>? filter,
  }) async {
    return runExtension(() async {
      // jsonEncode(kw) en vez de interpolar "$kw" a mano: un término de
      // búsqueda con comillas (copiar/pegar un título con comillas
      // tipográficas, etc.) rompía la sintaxis del JS generado y la
      // búsqueda fallaba con un error genérico en vez de escaparlo bien.
      final kwJs = jsonEncode(kw);
      final jsResult = await runtime.handlePromise(
        await runtime.evaluateAsync(
            'stringify(()=>${className}Instance.search($kwJs,$page,${filter == null ? null : jsonEncode(filter)}))'),
      );
      final decoded = await _decodeJsonResult(jsResult.stringResult);
      final result = _parseListItems(decoded);
      await _fillMissingHeaders(result);
      return result;
    });
  }

  // Búsqueda de UNA página (la 1) con red de seguridad: si la query
  // completa no encuentra nada, se reintenta con una versión más genérica
  // (menos palabras, ver SearchText.broadenedRemoteQueries) porque algunas
  // extensiones exigen que el título empiece exactamente con lo escrito.
  // En el caso normal (la query encuentra algo) es UN solo pedido, igual
  // que antes — importante para la velocidad: la búsqueda general dispara
  // esto por CADA extensión instalada.
  //
  // Acá hubo, y se sacó, un recolector multi-página (hasta 6 pedidos
  // secuenciales por extensión, más una consulta suplementaria): fue un
  // intento equivocado de compensar desde el app que el buscador de
  // AnimeFenix omitía resultados. La causa real estaba en el sitio (no
  // devolvía ciertos títulos sin ?tipo=) y quedó resuelta dentro de esa
  // extensión, que ahora hace la unión por tipos ella misma. Mantener el
  // multi-página además de eso multiplicaba los pedidos (hasta ~50 por
  // búsqueda con esa extensión) y era la causa principal de que la barra
  // de carga quedara colgada un buen rato — confirmado en vivo.
  //
  // Segunda red de seguridad, esta sobre los FILTROS: si con los filtros
  // puestos no aparece nada, se vuelve a buscar sin ellos.
  //
  // El motivo es que los filtros del panel se quedan puestos de una búsqueda a
  // la otra. Alguien deja "Género: Romance" de un rato antes, después escribe
  // el nombre de una obra que existe pero está catalogada en otro género, y la
  // pantalla dice "no se encontraron resultados" — que es falso: la obra está,
  // solo que no en ese género. Y no hay ninguna pista de que la culpa la tiene
  // un filtro que quedó de antes.
  //
  // Cuando el reintento sí encuentra, se avisa por [onFiltrosIgnorados] para
  // poder decirlo en pantalla: mostrar resultados que no cumplen los filtros
  // sin explicar por qué sería igual de confuso que no mostrar nada.
  //
  // No cuesta pedidos de más en el caso normal: solo corre cuando ya se agotó
  // todo lo anterior sin un solo resultado.
  Future<List<ExtensionListItem>> searchFirstPageWithBroadening(
    String kw, {
    Map<String, List<String>>? filter,
    void Function()? onFiltrosIgnorados,
  }) async {
    final queries = SearchText.broadenedRemoteQueries(kw);
    for (final query in queries) {
      final result = await _searchAcotado(query, filter);
      if (result.isNotEmpty) return result;
    }

    final hayFiltros =
        filter != null && filter.values.any((v) => v.isNotEmpty);
    if (!hayFiltros) return const [];

    for (final query in queries) {
      final result = await _searchAcotado(query, null);
      if (result.isNotEmpty) {
        onFiltrosIgnorados?.call();
        return result;
      }
    }
    return const [];
  }

  // Cada intento de la cascada acotado por SU CUENTA, no el total.
  //
  // El puente de red (jsRequest, más arriba) ya corta solo a los veinte
  // segundos. Antes nada envolvía esto acá adentro y la búsqueda general
  // (search_controller.dart) le ponía QUINCE fijos a la cascada ENTERA —
  // menos de lo que tarda un solo intento en cortarse por su cuenta, así
  // que ni siquiera el primero llegaba a responder antes de que el
  // buscador general se rindiera con "no encontró resultados". Buscando
  // esa misma extensión de forma directa (extension_searcher_page.dart, sin
  // ningún límite propio) sí encontraba, porque ahí el intento tenía los
  // veinte segundos completos del puente.
  //
  // Con el límite acá, en cada intento: si uno se cuelga se da por vacío y
  // la cascada sigue probando con la palabra que sigue, en vez de
  // abortarse entera con un error. Y el buscador general ya no necesita
  // adivinar cuántos intentos puede llegar a hacer una búsqueda para
  // ponerle el tiempo justo por fuera (ver getResult en search_controller).
  Future<List<ExtensionListItem>> _searchAcotado(
    String query,
    Map<String, List<String>>? filter,
  ) {
    return search(query, 1, filter: filter).timeout(
      const Duration(seconds: 22),
      onTimeout: () => const [],
    );
  }

  Future<Map<String, ExtensionFilter>> createFilter({
    Map<String, List<String>>? filter,
  }) async {
    // jsonEncode(filter) se interpola DIRECTO como literal de objeto JS (JSON
    // válido es JS válido) — igual que search()/top(). Antes se envolvía a
    // mano entre comillas simples + JSON.parse: jsonEncode escapa `"` y `\`
    // pero no comillas simples literales, así que un valor de filtro con un
    // apóstrofe (ej. un género "Women's") cortaba el string JS antes de
    // tiempo y el resto quedaba como código JS crudo — mínimo rompía el
    // filtro con un SyntaxError, en el peor caso inyectaba JS arbitrario.
    late String eval;
    if (filter == null) {
      eval = 'stringify(()=>${className}Instance.createFilter())';
    } else {
      eval =
          'stringify(()=>${className}Instance.createFilter(${jsonEncode(filter)}))';
    }
    return runExtension(() async {
      final jsResult = await runtime.handlePromise(
        await runtime.evaluateAsync(eval),
      );
      return _parseFilters(await _decodeJsonResult(jsResult.stringResult));
    });
  }

  // Ranking/top nativo de la extensión (no de AniList) — cada extensión trae
  // su propia noción de "top" con sus propios filtros reales (ver
  // createTopFilter): JKAnime por temporada/año, Olympus por total/mensual,
  // etc. Extensiones que no lo implementan devuelven [] (ver wrapper
  // generado por prism-plus), nunca lanzan.
  Future<List<ExtensionListItem>> top({
    Map<String, List<String>>? filter,
    int page = 1,
  }) async {
    return runExtension(() async {
      final jsResult = await runtime.handlePromise(
        await runtime.evaluateAsync(
            'stringify(()=>${className}Instance.top(${filter == null ? null : jsonEncode(filter)},$page))'),
      );
      final decoded = await _decodeJsonResult(jsResult.stringResult);
      final result = _parseListItems(decoded);
      await _fillMissingHeaders(result);
      return result;
    });
  }

  Future<Map<String, ExtensionFilter>> createTopFilter() async {
    return runExtension(() async {
      final jsResult = await runtime.handlePromise(
        await runtime.evaluateAsync(
            'stringify(()=>${className}Instance.createTopFilter())'),
      );
      return _parseFilters(await _decodeJsonResult(jsResult.stringResult));
    });
  }

  Future<ExtensionDetail> detail(String url) async {
    return runExtension(() async {
      final urlJs = jsonEncode(url);
      final jsResult = await runtime.handlePromise(
        await runtime.evaluateAsync(
            'stringify(()=>${className}Instance.detail($urlJs))'),
      );
      final decoded = await _decodeJsonResult(jsResult.stringResult);
      // Mensaje propio en vez de dejar salir el error crudo del generador de
      // json_serializable ("type 'Null' is not a subtype of type 'String'"),
      // que no le dice nada a nadie sobre cuál es el problema real.
      if (decoded is! Map) {
        throw Exception(
            '${extension.name}: el detalle no vino en el formato esperado');
      }
      final ExtensionDetail result;
      try {
        result = ExtensionDetail.fromJson(Map<String, dynamic>.from(decoded));
      } catch (e) {
        throw Exception(
            '${extension.name}: el detalle llegó incompleto o mal formado');
      }
      result.headers ??= await _defaultHeaders;
      return result;
    });
  }

  // typeHint: solo hace falta para extensiones "mixed" (ExtensionType.type
  // fijo no alcanza para decidir manga vs bangumi ahí) — el llamador ya sabe
  // qué tipo de título está reproduciendo (viene de ExtensionUtils.resolveType
  // o del contexto: video_controller/reader_controller solo se usan para un
  // tipo cada uno). Para el resto de extensiones no cambia nada: sigue
  // cayendo a extension.type de siempre.
  Future<Object?> watch(String url, {ExtensionType? typeHint}) async {
    return runExtension(() async {
      final urlJs = jsonEncode(url);
      final jsResult = await runtime.handlePromise(
        await runtime
            .evaluateAsync('stringify(()=>${className}Instance.watch($urlJs))'),
      );
      final data = await _decodeJsonResult(jsResult.stringResult);

      // Lo que devuelve la extension se valida ANTES de armar el modelo.
      //
      // Cada lector espera una forma distinta: el de video una url, el de
      // paginas una lista de imagenes, el de texto una lista de parrafos. Si la
      // extension devuelve otra cosa, el modelo generado hacia el cast a secas
      // y la app moria con "type 'Null' is not a subtype of type
      // 'List<dynamic>'" — un error que no le dice nada a nadie y que ademas
      // parecia un fallo de la app y no de la extension. Paso de verdad con
      // Ikigai, que devolvia texto para un capitulo de comic.
      //
      // No se intenta adivinar ni adaptar la forma a proposito: que una
      // extension devuelva algo que no corresponde es un error suyo, y taparlo
      // en silencio significa mostrar contenido equivocado sin que nadie se
      // entere. Se avisa con el nombre de la extension y que fue lo que pasó.
      final tipo = typeHint ?? extension.type;
      try {
        switch (tipo) {
          case ExtensionType.bangumi:
            final result = ExtensionBangumiWatch.fromJson(data);
            result.headers ??= await _defaultHeaders;
            return result;
          case ExtensionType.manga:
            final result = ExtensionMangaWatch.fromJson(data);
            result.headers ??= await _defaultHeaders;
            return result;
          default:
            return ExtensionFikushonWatch.fromJson(data);
        }
      } catch (e) {
        throw Exception(_erroDeFormaWatch(extension.name, tipo, data));
      }
    });
  }

  // Arma el aviso de "la extension devolvio algo que no puedo leer".
  //
  // Se mira que trajo de verdad para poder decirlo en criollo. El caso mas
  // comun, y el mas confuso de todos, es el cruce entre los dos lectores de
  // lectura: un capitulo de texto abierto con el lector de paginas se veia como
  // un error de tipos de Dart, sin ninguna pista de que la culpa era del tipo
  // que la extension le puso a la obra.
  static String _erroDeFormaWatch(
    String nombre,
    ExtensionType tipo,
    Map<String, dynamic> data,
  ) {
    final trajoTexto = data['content'] is List;
    final trajoPaginas = data['urls'] is List;
    final trajoVideo = data['url'] is String;

    if (tipo == ExtensionType.manga && trajoTexto) {
      return '$nombre: este capítulo vino como texto pero la obra figura como '
          'cómic, así que no se puede abrir con el lector de páginas. '
          'Es un problema de la extensión.';
    }
    if (tipo == ExtensionType.fikushon && trajoPaginas) {
      return '$nombre: este capítulo vino como imágenes pero la obra figura '
          'como novela. Es un problema de la extensión.';
    }
    if (tipo == ExtensionType.bangumi && !trajoVideo) {
      return '$nombre: no devolvió el enlace del vídeo de este episodio.';
    }
    return '$nombre: el capítulo llegó incompleto o mal formado.';
  }

  Future<String> checkUpdate(url) async {
    return runExtension(() async {
      final urlJs = jsonEncode(url);
      final jsResult = await runtime.handlePromise(
        await runtime.evaluateAsync(
            'stringify(()=>${className}Instance.checkUpdate($urlJs))'),
      );
      return jsResult.stringResult;
    });
  }
}
