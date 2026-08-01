import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:prismhub/views/pages/watch/video/webview_player_page.dart' show ensureWebViewEnvironment;
import 'package:get/get.dart';

class AnilistWebViewPage extends StatefulWidget {
  const AnilistWebViewPage({
    super.key,
    required this.url,
  });
  final String url;

  @override
  State<AnilistWebViewPage> createState() => _AnilistWebViewPageState();
}

class _AnilistWebViewPageState extends State<AnilistWebViewPage> {
  late String url = widget.url;

  // Entorno de WebView2 con la carpeta de datos en Documentos.
  //
  // Sin el, WebView2 usa una carpeta junto al propio ejecutable
  // ("PrismHub.exe.WebView2\\EBWebView"). Con la app instalada eso cae dentro
  // de Program Files, donde un usuario normal no puede escribir: Edge levanta
  // un cartel de "no hemos podido crear el directorio de datos" y la pagina
  // queda en negro. Solo se notaba con la version instalada, no corriendo la
  // portable desde una carpeta escribible.
  //
  // Se resuelve una vez al montar; hasta que llegue, no se dibuja el WebView.
  // En Linux y Android devuelve null y el WebView se crea como siempre.
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

  @override
  void dispose() {
    CookieManager.instance().deleteCookies(url: WebUri(widget.url));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Anilist Login"),
      ),
      body: !_entornoListo
          ? const Center(child: CircularProgressIndicator())
          : InAppWebView(
        webViewEnvironment: _entorno,
        initialUrlRequest: URLRequest(
          url: WebUri(widget.url),
        ),
        onLoadStart: (controller, url) async {
          if (url != null && url.toString().contains("access_token")) {
            debugPrint(url.host);
            Get.back(result: url.toString());
          }
        },
      ),
    );
  }
}
