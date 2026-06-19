import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:prismhub/utils/prismhub_storage.dart';

/// True when a URL is a direct media stream that media_kit can play natively.
/// Anything else (an embed/player page like mega.nz/embed, voe.sx/e, ...) is not
/// directly playable.
bool isDirectStream(String url) {
  final u = url.toLowerCase();
  return u.contains('.m3u8') ||
      u.contains('.mp4') ||
      u.contains('.mkv') ||
      u.contains('.webm') ||
      u.contains('.ts') ||
      u.contains('mime=video') ||
      u.contains('/api/file/'); // pixeldrain direct
}

/// Opens an embed/player page in the fullscreen in-app WebView.
void openWebViewPlayer(
  BuildContext context,
  String url, {
  String? referer,
  String title = '',
}) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) =>
          WebViewPlayerPage(url: url, referer: referer, title: title),
    ),
  );
}

/// Fullscreen WebView player. Loads an embed/player page (mega, voe, mixdrop,
/// etc.) in a real browser engine so it runs the host's own player + JS — the
/// fallback for servers that can't be resolved to a direct stream URL.
class WebViewPlayerPage extends StatefulWidget {
  const WebViewPlayerPage({
    super.key,
    required this.url,
    this.title = '',
    this.referer,
  });

  final String url;
  final String title;
  final String? referer;

  @override
  State<WebViewPlayerPage> createState() => _WebViewPlayerPageState();
}

class _WebViewPlayerPageState extends State<WebViewPlayerPage> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(
              url: WebUri(widget.url),
              headers: widget.referer != null ? {'Referer': widget.referer!} : null,
            ),
            initialSettings: InAppWebViewSettings(
              userAgent: PrismHubStorage.getUASetting(),
              mediaPlaybackRequiresUserGesture: false,
              allowsInlineMediaPlayback: true,
              javaScriptEnabled: true,
              transparentBackground: true,
              // Bloquea ventanas/popups de anuncios de los hosts.
              javaScriptCanOpenWindowsAutomatically: false,
              supportMultipleWindows: false,
            ),
            onLoadStop: (controller, url) {
              if (mounted) setState(() => _loading = false);
            },
            // Mantener la navegación dentro del mismo host: bloquea redirecciones
            // a páginas de anuncios de otros dominios.
            shouldOverrideUrlLoading: (controller, action) async {
              final u = action.request.url;
              if (u == null) return NavigationActionPolicy.ALLOW;
              final host = Uri.tryParse(widget.url)?.host;
              if (action.isForMainFrame &&
                  host != null &&
                  u.host.isNotEmpty &&
                  u.host != host) {
                return NavigationActionPolicy.CANCEL;
              }
              return NavigationActionPolicy.ALLOW;
            },
          ),
          if (_loading)
            const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          // Botón de volver.
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Container(
                margin: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
