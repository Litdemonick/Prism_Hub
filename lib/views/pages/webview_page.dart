import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:prismhub/views/pages/watch/video/webview_player_page.dart' show ensureWebViewEnvironment;
import 'package:prismhub/data/services/extension_service.dart';
import 'package:prismhub/utils/extension.dart';
import 'package:prismhub/utils/prismhub_storage.dart';
import 'package:webview_cookie_manager_plus/webview_cookie_manager_plus.dart';

class WebViewPage extends StatefulWidget {
  const WebViewPage({
    super.key,
    required this.extensionRuntime,
    required this.url,
  });
  final ExtensionService extensionRuntime;
  final String url;

  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> {
  late String url = ExtensionUtils.joinWebUrl(
      widget.extensionRuntime.extension.webSite, widget.url);
  final cookieManager = WebviewCookieManager();
  late Uri loadUrl = Uri.parse(url);

  // Entorno de WebView2 con la carpeta de datos en Documentos — ver el
  // comentario largo en stream_sniffer_service.dart. Sin el, con la app
  // instalada en Program Files, Edge no puede crear su carpeta y la pagina
  // queda en negro con un cartel del sistema.
  WebViewEnvironment? _entorno;
  bool _entornoListo = false;

  @override
  void initState() {
    super.initState();
    ensureWebViewEnvironment().then((env) {
      if (!mounted) return;
      setState(() {
        _entorno = env;
        _entornoListo = true;
      });
    });
  }

  _setCookie() async {
    if (loadUrl.host != Uri.parse(url).host) {
      return;
    }
    final cookies = await cookieManager.getCookies(loadUrl.toString());
    final cookieString =
        cookies.map((e) => '${e.name}=${e.value}').toList().join(';');
    debugPrint('$url $cookieString');
    widget.extensionRuntime.setCookie(
      cookieString,
    );
  }

  @override
  void dispose() {
    _setCookie();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(loadUrl.toString()),
      ),
      body: !_entornoListo
          ? const Center(child: CircularProgressIndicator())
          : InAppWebView(
        webViewEnvironment: _entorno,
        initialUrlRequest: URLRequest(
          url: WebUri(url),
        ),
        initialSettings: InAppWebViewSettings(
          userAgent: PrismHubStorage.getUASetting(),
        ),
        onLoadStart: (controller, url) {
          setState(() {
            loadUrl = url!;
          });
        },
      ),
    );
  }
}
