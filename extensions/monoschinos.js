// ==PrismHubExtension==
// @name         MonosChinos
// @version      v0.2.0
// @author       PrismHub
// @lang         es
// @license      MIT
// @package      monoschinos
// @type         bangumi
// @icon         https://monoschinos.st/img/2web.jpg
// @webSite      https://monoschinos.st
// @nsfw         false
// ==/PrismHubExtension==

// MonosChinos carga episodios y players vía JavaScript (AJAX).
// Estrategia:
//  - detail(): slug del botón "Ver ahora", luego escanea links "Siguiente" 
//              para construir la lista completa de episodios.
//  - watch():  intenta extraer el stream de los servidores de video
//              (filemoon, voe, doodstream, mp4upload, mega) via sus APIs.

export default class extends Extension {

  async latest(page) {
    const res = await this.request(`/animes?p=${page}`);
    const items = await this.querySelectorAll(res, "li.col.mb-5.ficha_efecto");
    const result = [];
    for (const el of items) {
      const html  = await el.content;
      const url   = await this.getAttributeText(html, "a", "href");
      const title = await this.querySelector(html, "h3.title_cap").text;
      const cover = await this.getAttributeText(html, "img.lazy", "data-src");
      if (url && title) result.push({ title: title.trim(), url, cover: cover || "" });
    }
    return result;
  }

  async search(kw) {
    const res = await this.request(`/buscar?q=${encodeURIComponent(kw)}`);
    const items = await this.querySelectorAll(res, "li.col.mb-5.ficha_efecto");
    const result = [];
    for (const el of items) {
      const html  = await el.content;
      const url   = await this.getAttributeText(html, "a", "href");
      const title = await this.querySelector(html, "h3.title_cap").text;
      const cover = await this.getAttributeText(html, "img.lazy", "data-src");
      if (url && title) result.push({ title: title.trim(), url, cover: cover || "" });
    }
    return result;
  }

  async detail(animeUrl) {
    const res = await this.request("", { headers: { "Miru-Url": animeUrl } });

    // Título y portada
    const title = await this.querySelector(res, "h1").text || "";
    let cover = "";
    try { cover = await this.getAttributeText(res, "img.lazy[data-src]", "data-src") || ""; } catch (_) {}

    // Descripción
    let desc = "";
    try { desc = await this.querySelector(res, "div.mb-3 p").text || ""; } catch (_) {}

    // ── Extraer slug del anime desde el botón "Ver ahora" (ep1) ──────────────
    // Patrón: href="https://monoschinos.st/ver/<slug>-episodio-1"
    const ep1Match = res.match(/href="(https?:\/\/monoschinos\.st\/ver\/([^"]+)-episodio-1)"/);
    const ep1Url = ep1Match ? ep1Match[1] : null;
    const slug   = ep1Match ? ep1Match[2] : null;

    if (!slug) {
      return {
        title: title.trim(),
        cover,
        desc: desc.trim(),
        episodes: [{ title: "Episodios", urls: [] }],
      };
    }

    // ── Descubrir número total de episodios ───────────────────────────────────
    // La página del episodio tiene un link "Siguiente" al próximo,
    // y un link "A continuación" con el número del siguiente episodio.
    // Buscamos el máximo número de episodio linkeado en la página de detalle del anime.
    let maxEp = 1;

    // Buscar todos los links /ver/<slug>-episodio-N en el HTML del detalle
    const epLinkRe = new RegExp(`/ver/${slug.replace(/[-]/g, '[-]')}-episodio-(\\d+)`, 'g');
    let m;
    while ((m = epLinkRe.exec(res)) !== null) {
      const n = parseInt(m[1]);
      if (n > maxEp) maxEp = n;
    }

    // Si solo encontramos ep1, intentar obtener el número total
    // haciendo una petición al ep1 y leyendo el link "Siguiente"
    if (maxEp <= 1 && ep1Url) {
      try {
        const ep1Res = await this.request("", { headers: { "Miru-Url": ep1Url } });
        // Buscar "Siguiente" → siguiente episodio
        // La página ep1 también tiene links a otros episodios en "A continuación"
        const epLinks = [...ep1Res.matchAll(new RegExp(`/ver/${slug.replace(/[-]/g, '[-]')}-episodio-(\\d+)`, 'g'))];
        for (const lm of epLinks) {
          const n = parseInt(lm[1]);
          if (n > maxEp) maxEp = n;
        }
        // Buscar el link "Lista" con el total de episodios de la sección info
        const totalMatch = ep1Res.match(/(\d+)\s*cap[ií]tulos?/i);
        if (totalMatch && parseInt(totalMatch[1]) > maxEp) {
          maxEp = parseInt(totalMatch[1]);
        }
      } catch (_) {}
    }

    // Construir lista de episodios en orden ascendente (Ep 1 primero)
    const episodes = [];
    for (let i = 1; i <= maxEp; i++) {
      episodes.push({
        name: `Episodio ${i}`,
        url: `https://monoschinos.st/ver/${slug}-episodio-${i}`,
      });
    }

    return {
      title: title.trim(),
      cover,
      desc: desc.trim(),
      episodes: [{ title: "Episodios", urls: episodes }],
    };
  }

  // ── watch(): el player se carga con JS, no está en el HTML estático ─────────
  // Estrategia: buscar el servidor de video en los links de descarga directa
  // que SÍ están en el HTML, o usar el JS de filemoon/voe/doodstream directamente.
  async watch(url) {
    const res = await this.request("", {
      headers: {
        "Miru-Url": url,
        "Referer": "https://monoschinos.st/",
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
      },
    });

    if (!res || typeof res !== "string") return { type: "hls", url: "error://no-response" };

    // Extraer el slug y número del episodio para construir la URL de la API
    // Formato: /ver/<slug>-episodio-<N>
    const episodioMatch = url.match(/\/ver\/(.+)-episodio-(\d+)$/);
    if (!episodioMatch) return { type: "hls", url: "error://bad-url" };
    const epSlug = episodioMatch[1];
    const epNum  = episodioMatch[2];

    // ── Intentar API interna de MonosChinos ──────────────────────────────────
    // El sitio tiene un endpoint /api/episode que devuelve los servers
    const apiEndpoints = [
      `https://monoschinos.st/api/episode?slug=${epSlug}&number=${epNum}`,
      `https://monoschinos.st/api/servers?slug=${epSlug}-episodio-${epNum}`,
      `https://monoschinos.st/api/episode/${epSlug}/${epNum}`,
    ];

    for (const ep of apiEndpoints) {
      try {
        const apiRes = await this.request("", {
          headers: {
            "Miru-Url": ep,
            "Referer": url,
            "X-Requested-With": "XMLHttpRequest",
          },
        });
        if (!apiRes || typeof apiRes !== "string") continue;
        const data = typeof apiRes === "object" ? apiRes : (() => {
          try { return JSON.parse(apiRes); } catch { return null; }
        })();
        if (data && data.url) return { type: "hls", url: data.url };
        if (data && data.server_url) return { type: "hls", url: data.server_url };
      } catch (_) {}
    }

    // ── Buscar links de descarga directa en el HTML (Filemoon, Mega, etc.) ───
    // MonosChinos muestra links de descarga en el HTML (sin JS):
    //   [Filemoon](https://bysekoze.com/d/cvj3eehzhmcp/)
    //   [Gofile](https://gofile.io/d/2cJoQn)
    //   [Pixeldrain](https://pixeldrain.com/u/cLiwLgZo)
    //   [Mediafire](https://mediafire.com/file/...)

    const downloadLinks = [];
    const dlRe = /https?:\/\/(bysekoze\.com|gofile\.io|pixeldrain\.com|mediafire\.com|filemoon\.[a-z]+|voe\.sx|doodstream\.com|mp4upload\.com)[^\s"')]+/g;
    let dlm;
    while ((dlm = dlRe.exec(res)) !== null) {
      downloadLinks.push(dlm[0]);
    }

    // Intentar cada link de descarga para obtener el stream
    for (const dlUrl of downloadLinks) {
      try {
        // Pixeldrain tiene API directa
        if (dlUrl.includes("pixeldrain.com/u/")) {
          const pdId = dlUrl.split("/u/")[1].split(/[?#]/)[0];
          return {
            type: "mp4",
            url: `https://pixeldrain.com/api/file/${pdId}?download`,
            headers: { Referer: "https://pixeldrain.com/" },
          };
        }

        // Filemoon/bysekoze: extraer desde la página embed
        if (dlUrl.includes("bysekoze.com") || dlUrl.includes("filemoon")) {
          const fmRes = await this.request("", {
            headers: { "Miru-Url": dlUrl, "Referer": url },
          });
          if (fmRes && typeof fmRes === "string") {
            const m3u8 = fmRes.match(/(https?:\/\/[^"'<>\s]+\.m3u8[^"'<>\s]*)/);
            if (m3u8) return { type: "hls", url: m3u8[1], headers: { Referer: dlUrl } };
          }
        }

        // Gofile: usar la API pública
        if (dlUrl.includes("gofile.io/d/")) {
          const gfId = dlUrl.split("/d/")[1].split(/[?#]/)[0];
          const gfRes = await this.request("", {
            headers: {
              "Miru-Url": `https://api.gofile.io/getContent?contentId=${gfId}&token=&websiteToken=7fd94ds12fds4`,
              "Referer": "https://gofile.io/",
            },
          });
          if (gfRes && typeof gfRes === "string") {
            const gfData = JSON.parse(gfRes);
            if (gfData.status === "ok" && gfData.data && gfData.data.contents) {
              const files = Object.values(gfData.data.contents);
              const videoFile = files.find(f => f.mimetype && f.mimetype.includes("video"));
              if (videoFile && videoFile.directLink) {
                return { type: "mp4", url: videoFile.directLink, headers: { Referer: "https://gofile.io/" } };
              }
            }
          }
        }
      } catch (_) {}
    }

    // ── Último fallback: intentar extracción de Voe si aparece en el HTML ────
    const voeMatch = res.match(/https?:\/\/voe\.sx\/[a-zA-Z0-9]+/);
    if (voeMatch) {
      try {
        const voeRes = await this.request("", {
          headers: { "Miru-Url": voeMatch[0], "Referer": url },
        });
        if (voeRes) {
          const m3u8 = voeRes.match(/(https?:\/\/[^"'<>\s]+\.m3u8[^"'<>\s]*)/);
          if (m3u8) return { type: "hls", url: m3u8[1], headers: { Referer: "https://voe.sx/" } };
        }
      } catch (_) {}
    }

    return { type: "hls", url: "error://players-require-javascript" };
  }
}
