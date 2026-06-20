import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:prismhub/utils/log.dart';
import 'package:prismhub/utils/prismhub_storage.dart';

/// Stream de video capturado por el sniffer: URL directa + Referer necesario.
class SniffedStream {
  final String url;
  final String referer;
  const SniffedStream(this.url, this.referer);
}

/// Sniffer universal de streams vía WebView oculto.
///
/// Cuando el resolver nativo (regex) no logra extraer el stream de un embed
/// (voe, netu, streamwish, doodstream...), este servicio carga la página del
/// embed en un [HeadlessInAppWebView] invisible, deja correr el JavaScript real
/// del host (que sabe desencriptar/armar su propio stream) e intercepta la
/// primera petición a un `.m3u8`/`.mp4`. Esa URL se reproduce nativa en mpv.
///
/// Es la técnica robusta frente a la ofuscación rotativa de los hosts: usa la
/// lógica real del host en vez de adivinar su HTML, así que no se rompe cuando
/// cambian la página.
class StreamSnifferService {
  StreamSnifferService._();

  /// JS inyectado al inicio del documento. Hookea `fetch`, `XMLHttpRequest`,
  /// el setter de `<video>.src` y escanea tags `<video>/<source>` para reportar
  /// cualquier URL que parezca un stream de video al lado Dart.
  ///
  /// En WebView2 (Windows), `flutter_inappwebview.callHandler` no está disponible
  /// en iframes cross-origin. Se usa un doble mecanismo:
  ///   1. Llamada directa si estamos en el frame principal.
  ///   2. postMessage hacia el frame principal si estamos en un sub-frame.
  ///      El frame principal escucha esos mensajes y los reenvía a Dart.
  static const String _hookSource = r'''
(function(){
  var _isTop = (window === window.top);

  function sendStream(u, frameHref){
    try{
      // Llamada directa (funciona en frame principal y, en Android, en sub-frames)
      window.flutter_inappwebview.callHandler('prismStream', u, frameHref || location.href);
    }catch(e){
      // Sub-frame cross-origin en WebView2: relay via postMessage al frame raíz
      try{
        window.top.postMessage(JSON.stringify({_prism:1,h:'prismStream',a:[u, frameHref||location.href]}),'*');
      }catch(e2){}
    }
  }

  function rep(u){
    try{
      if(!u) return;
      u = '' + u;
      if(/\.m3u8(\?|#|$)|\.mp4(\?|#|$)|\.mkv(\?|#|$)|\.webm(\?|#|$)|mime=video|\/manifest|\.ts(\?|#|$)/i.test(u)){
        if(u.indexOf('http')!==0){ try{ u = new URL(u, location.href).href; }catch(e){} }
        sendStream(u, location.href);
      }
    }catch(e){}
  }

  // Relay de sub-frames: solo en el frame principal
  if(_isTop){
    try{
      window.addEventListener('message', function(ev){
        try{
          var d = JSON.parse(ev.data);
          if(d && d._prism===1 && d.h==='prismStream' && d.a && d.a[0]){
            try{ window.flutter_inappwebview.callHandler('prismStream', d.a[0], d.a[1]||''); }catch(e){}
          }
        }catch(e){}
      }, false);
    }catch(e){}
  }

  try{
    var of = window.fetch;
    if(of){ window.fetch = function(){ try{ var a=arguments[0]; rep(a && a.url ? a.url : a); }catch(e){} return of.apply(this, arguments); }; }
  }catch(e){}
  try{
    var oo = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function(m,u){ try{ rep(u); }catch(e){} return oo.apply(this, arguments); };
  }catch(e){}
  try{
    var proto = HTMLMediaElement.prototype;
    var d = Object.getOwnPropertyDescriptor(proto,'src');
    if(d && d.set){
      Object.defineProperty(proto,'src',{
        set:function(v){ rep(v); return d.set.call(this,v); },
        get:function(){ return d.get.call(this); },
        configurable:true
      });
    }
  }catch(e){}
  try{
    // Escaneo periódico de <video>/<source> + auto-play de videos pausados
    setInterval(function(){
      var els = document.querySelectorAll('video, source');
      for(var i=0;i<els.length;i++){ rep(els[i].src || els[i].getAttribute('src')); }
      // Intentar reproducir videos pausados (players que esperan clic)
      var vids = document.querySelectorAll('video');
      for(var j=0;j<vids.length;j++){
        try{ if(vids[j].paused && vids[j].readyState>0) vids[j].play(); }catch(e){}
      }
    }, 400);
  }catch(e){}
  // Auto-clic en botones de play comunes, una vez que el DOM esté listo
  try{
    function _tryClickPlay(){
      var sels=['.vjs-big-play-button','.jw-icon-display','.fp-play',
                '[class*="play-btn"i]','[class*="play-button"i]',
                '[data-plyr="play"]','.btn-play','.play-overlay',
                '[aria-label*="Play"i]','button[title*="Play"i]'];
      for(var i=0;i<sels.length;i++){
        try{ var el=document.querySelector(sels[i]); if(el){ el.click(); break; } }catch(e){}
      }
    }
    setTimeout(_tryClickPlay, 1200);
    setTimeout(_tryClickPlay, 3000);
  }catch(e){}
})();
''';

  /// JS inyectado al final del documento SOLO en page-sniff. Muchos sitios
  /// (animeflv, tioanime, monoschinos) no montan el reproductor hasta que el
  /// usuario clickea un servidor: la página solo trae la lista de embeds en
  /// `var videos` / `[data-player]` (base64) / iframes. Este script lee esa
  /// lista y monta cada embed en un iframe oculto — replicando el click — para
  /// que sus players arranquen, pidan su m3u8 y el hook lo capture.
  // Reemplaza la creación de iframes por un callHandler con las URLs.
  // Los iframes dinámicos en WebView2 (Windows) NO reciben _hookSource
  // (userScripts no se inyectan en frames creados en runtime), por lo que
  // callHandler no estaba disponible en ellos y los streams nunca se capturaban.
  // Solución: enviar las embed URLs a Dart; Dart abre un WebView independiente
  // por cada URL (frame principal → callHandler funciona perfectamente).
  static const String _loaderSource = r'''
(function(){
  function pick(){
    var out = [];
    try {
      var v = window.videos;
      if (v) {
        var arr = [];
        if (Array.isArray(v)) arr = v;
        else for (var k in v){ if(Array.isArray(v[k])) arr = arr.concat(v[k]); }
        for (var i=0;i<arr.length;i++){
          var it = arr[i];
          if (Array.isArray(it)){ for(var j=0;j<it.length;j++){ if(typeof it[j]==='string' && it[j].indexOf('http')===0) out.push(it[j]); } }
          else if (it && (it.code||it.url)){ out.push(it.code||it.url); }
        }
      }
    } catch(e){}
    try {
      var els = document.querySelectorAll('[data-player]');
      for (var i=0;i<els.length;i++){ try{ var d=atob(els[i].getAttribute('data-player')); if(d.indexOf('http')===0) out.push(d); }catch(e){} }
    } catch(e){}
    try {
      var ifr = document.querySelectorAll('iframe[src]');
      for (var i=0;i<ifr.length;i++){ var s=ifr[i].src||''; if(s.indexOf('http')===0) out.push(s); }
    } catch(e){}
    var seen={}, uniq=[];
    for (var i=0;i<out.length;i++){ if(!seen[out[i]]){ seen[out[i]]=1; uniq.push(out[i]); } }
    return uniq;
  }
  var done=false, tries=0;
  var t=setInterval(function(){
    tries++;
    var e=pick();
    if (e.length && !done){
      done=true; clearInterval(t);
      try{ window.flutter_inappwebview.callHandler('prismEmbeds', JSON.stringify(e)); }catch(x){}
    }
    if (tries>40){ clearInterval(t); try{ window.flutter_inappwebview.callHandler('prismEmbeds', JSON.stringify([])); }catch(x){} }
  }, 300);
})();
''';

  /// True si la URL aparenta ser un stream reproducible nativamente.
  static bool _looksLikeStream(String u) {
    final s = u.toLowerCase();
    return s.contains('.m3u8') ||
        s.contains('.mp4') ||
        s.contains('.mkv') ||
        s.contains('.webm') ||
        s.contains('mime=video') ||
        s.contains('/manifest');
  }

  /// Referer por defecto: el origen del propio embed.
  static String _embedReferer(String embedUrl) {
    try {
      final u = Uri.parse(embedUrl);
      return '${u.scheme}://${u.host}/';
    } catch (_) {
      return embedUrl;
    }
  }

  /// Carga [embedUrl] en un WebView oculto e intenta capturar su stream.
  /// Devuelve null si no aparece ningún stream antes de [timeout].
  static Future<SniffedStream?> sniff(
    String embedUrl, {
    String? referer,
    Duration timeout = const Duration(seconds: 12),
    // true en page-sniff: inyecta el loader que monta los embeds de la página
    // en iframes ocultos (sitios que no auto-cargan su player).
    bool loadEmbeds = false,
  }) async {
    final completer = Completer<SniffedStream?>();
    final hostReferer = referer ?? _embedReferer(embedUrl);
    HeadlessInAppWebView? webView;
    Timer? timer;

    void finish(SniffedStream? result) {
      if (completer.isCompleted) return;
      timer?.cancel();
      completer.complete(result);
      // Liberar el WebView en microtask para no cortar el callback en curso.
      Future.microtask(() async {
        try {
          await webView?.dispose();
        } catch (_) {}
      });
    }

    void onCandidate(String u, [String? frameHref]) {
      if (!_looksLikeStream(u)) return;
      // El Referer correcto es el del frame que pidió el stream (el embed real),
      // no el de la página contenedora. Si no llega, se usa el del embed cargado.
      var ref = hostReferer;
      if (frameHref != null && frameHref.startsWith('http')) {
        try {
          final f = Uri.parse(frameHref);
          ref = '${f.scheme}://${f.host}/';
        } catch (_) {}
      }
      logger.info('[sniffer] stream capturado: $u (ref: $ref)');
      finish(SniffedStream(u, ref));
    }

    try {
      webView = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(
          url: WebUri(embedUrl),
          headers: referer != null ? {'Referer': referer} : null,
        ),
        initialSettings: InAppWebViewSettings(
          userAgent: PrismHubStorage.getUASetting(),
          javaScriptEnabled: true,
          // Bloquear popups/ventanas de anuncios de los hosts.
          javaScriptCanOpenWindowsAutomatically: false,
          supportMultipleWindows: false,
          mediaPlaybackRequiresUserGesture: false,
          transparentBackground: true,
          useOnLoadResource: true,
          // No reproducir audio del WebView oculto.
          isInspectable: false,
        ),
        initialUserScripts: UnmodifiableListView<UserScript>([
          UserScript(
            source: _hookSource,
            injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
            // forMainFrameOnly:false → también inyecta en iframes. Imprescindible
            // para el "page-sniff": el sitio (animeflv, etc.) carga su player
            // dentro de un <iframe>, y ahí es donde se pide el m3u8.
            forMainFrameOnly: false,
          ),
          // Loader: solo en page-sniff, solo en el frame principal (donde está
          // la lista de embeds del sitio).
          if (loadEmbeds)
            UserScript(
              source: _loaderSource,
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
              forMainFrameOnly: true,
            ),
        ]),
        onWebViewCreated: (controller) {
          controller.addJavaScriptHandler(
            handlerName: 'prismStream',
            callback: (args) {
              if (args.isNotEmpty && args.first != null) {
                final frameHref =
                    args.length > 1 ? args[1]?.toString() : null;
                onCandidate(args.first.toString(), frameHref);
              }
            },
          );
          // Diagnóstico del loader: qué embeds encontró (o si no encontró).
          controller.addJavaScriptHandler(
            handlerName: 'prismDebug',
            callback: (args) {
              if (args.isNotEmpty) logger.info('[sniffer/loader] ${args.first}');
              return null;
            },
          );
        },
        // Bonus en plataformas donde dispara: intercepta el recurso aunque el
        // hook JS no lo capture (algunos players usan APIs no hookeadas).
        onLoadResource: (controller, resource) {
          final u = resource.url?.toString();
          if (u != null) onCandidate(u);
        },
      );

      await webView.run();
      timer = Timer(timeout, () {
        logger.info('[sniffer] timeout sin stream para $embedUrl');
        finish(null);
      });
    } catch (e) {
      logger.warning('[sniffer] error iniciando WebView oculto: $e');
      finish(null);
    }

    return completer.future;
  }

  /// Carga [pageUrl] en un WebView oculto y espera a que [_loaderSource]
  /// detecte los embed URLs (window.videos, [data-player], iframe[src]).
  /// Devuelve la lista de URLs (puede estar vacía si la página no las tiene
  /// o si vence el [timeout]).
  /// Úsalo como primera etapa del page-sniff antes de sniffear cada embed
  /// individualmente con [sniff()].
  static Future<List<String>> getEmbedUrls(
    String pageUrl, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final completer = Completer<List<String>>();
    HeadlessInAppWebView? webView;
    Timer? timer;

    void finish(List<String> result) {
      if (completer.isCompleted) return;
      timer?.cancel();
      completer.complete(result);
      Future.microtask(() async {
        try { await webView?.dispose(); } catch (_) {}
      });
    }

    try {
      webView = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(pageUrl)),
        initialSettings: InAppWebViewSettings(
          userAgent: PrismHubStorage.getUASetting(),
          javaScriptEnabled: true,
          javaScriptCanOpenWindowsAutomatically: false,
          supportMultipleWindows: false,
          mediaPlaybackRequiresUserGesture: false,
          transparentBackground: true,
          isInspectable: false,
        ),
        initialUserScripts: UnmodifiableListView<UserScript>([
          UserScript(
            source: _loaderSource,
            injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
            forMainFrameOnly: true,
          ),
        ]),
        onWebViewCreated: (controller) {
          controller.addJavaScriptHandler(
            handlerName: 'prismEmbeds',
            callback: (args) {
              try {
                if (args.isNotEmpty && args.first != null) {
                  final List<dynamic> parsed =
                      jsonDecode(args.first.toString());
                  final urls =
                      parsed.map((e) => e.toString()).toList();
                  logger.info('[sniffer/embeds] ${urls.length} embed(s) en $pageUrl');
                  finish(urls);
                } else {
                  finish([]);
                }
              } catch (e) {
                logger.warning('[sniffer/embeds] error parseando: $e');
                finish([]);
              }
              return null;
            },
          );
        },
      );

      await webView.run();
      timer = Timer(timeout, () {
        logger.info('[sniffer/embeds] timeout para $pageUrl');
        finish([]);
      });
    } catch (e) {
      logger.warning('[sniffer/embeds] error WebView: $e');
      finish([]);
    }

    return completer.future;
  }
}
