import 'dart:async';
import 'dart:collection';

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
  static const String _hookSource = r'''
(function(){
  function rep(u){
    try{
      if(!u) return;
      u = '' + u;
      if(/\.m3u8(\?|#|$)|\.mp4(\?|#|$)|\.mkv(\?|#|$)|\.webm(\?|#|$)|mime=video|\/manifest|\.ts(\?|#|$)/i.test(u)){
        if(u.indexOf('http')!==0){ try{ u = new URL(u, location.href).href; }catch(e){} }
        // Segundo arg: la URL del frame que pidió el stream. Cuando sniffeamos la
        // página completa, el m3u8 lo pide un iframe (voe, streamwish...) y su
        // Referer correcto es el de ESE host, no el de la página contenedora.
        try{ window.flutter_inappwebview.callHandler('prismStream', u, location.href); }catch(e){}
      }
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
    setInterval(function(){
      var els = document.querySelectorAll('video, source');
      for(var i=0;i<els.length;i++){ rep(els[i].src || els[i].getAttribute('src')); }
    }, 400);
  }catch(e){}
})();
''';

  /// JS inyectado al final del documento SOLO en page-sniff. Muchos sitios
  /// (animeflv, tioanime, monoschinos) no montan el reproductor hasta que el
  /// usuario clickea un servidor: la página solo trae la lista de embeds en
  /// `var videos` / `[data-player]` (base64) / iframes. Este script lee esa
  /// lista y monta cada embed en un iframe oculto — replicando el click — para
  /// que sus players arranquen, pidan su m3u8 y el hook lo capture.
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
      try{ window.flutter_inappwebview.callHandler('prismDebug', 'embeds:'+e.length+' '+e.slice(0,6).join(' | ')); }catch(x){}
      for (var i=0;i<e.length && i<6;i++){
        try{
          var f=document.createElement('iframe');
          f.style.cssText='position:absolute;left:-9999px;top:0;width:640px;height:360px;border:0;';
          f.setAttribute('allow','autoplay; encrypted-media; fullscreen');
          f.src=e[i];
          document.body.appendChild(f);
        }catch(e2){}
      }
    }
    if (tries>40){ clearInterval(t); try{ window.flutter_inappwebview.callHandler('prismDebug', 'sin embeds tras '+tries+' intentos'); }catch(x){} }
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
}
