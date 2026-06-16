// ==PrismHubExtension==
// @name         TioAnime
// @version      v0.1.7
// @author       PrismHub
// @lang         es
// @license      MIT
// @icon         https://tioanime.com/favicon.ico
// @package      tioanime
// @type         bangumi
// @webSite      https://jimov-api.vercel.app
// @description  Anime en español Latino vía TioAnime
// ==/PrismHubExtension==

export default class extends Extension {
  async load() {
    this.registerSetting({
      title: "Jimov API",
      key: "tioanime",
      type: "input",
      description: "Multimedia API",
      defaultValue: "https://jimov-api.vercel.app",
    });
  }

  async createFilter() {
    return {};
  }

  async req(url) {
    return this.request(url, {
      headers: { "Miru-Url": await this.getSetting("tioanime") },
    });
  }

  async latest(page) {
    const res = await this.req(`/anime/tioanime/filter?page=${page}`);
    const results = Array.isArray(res) ? res : ((res && res.results) || []);
    return results.map((item) => ({
      url: item.url,
      title: item.name,
      cover: item.image || "",
    }));
  }

  async search(kw, page) {
    const res = await this.req(
      `/anime/tioanime/filter?q=${encodeURIComponent(kw)}&page=${page}`
    );
    const results = Array.isArray(res) ? res : ((res && res.results) || []);
    return results.map((item) => ({
      title: item.name,
      url: item.url,
      cover: item.image || "",
      desc: item.type || "",
    }));
  }

  async detail(url) {
    const res = await this.req(url);
    if (!res) return { title: "", cover: "", desc: "", episodes: [] };
    const cover = res.image ? (res.image.url || res.image) : "";
    const episodes = (res.episodes || []).map((ep) => ({
      name: ep.name || (ep.num != null ? `Ep ${ep.num}` : (ep.number != null ? `Ep ${ep.number}` : "Ep ?")),
      url: ep.url,
    }));
    return {
      title: res.name || "",
      cover,
      desc: res.synopsis || "",
      episodes: [{ title: "Episodios", urls: episodes }],
    };
  }

  _refererFor(url) {
    if (!url) return "";
    if (url.includes("yourupload.com")) return "https://www.yourupload.com/";
    if (url.includes("hqq.tv") || url.includes("netu")) return "https://hqq.tv/";
    if (url.includes("ok.ru")) return "https://ok.ru/";
    if (url.includes("streamsb") || url.includes("sbfull") || url.includes("sbplay"))
      return "https://streamsb.com/";
    if (url.includes("fembed") || url.includes("anime789"))
      return "https://www.fembed.com/";
    if (url.includes("mp4upload")) return "https://www.mp4upload.com/";
    if (url.includes("streamtape")) return "https://streamtape.com/";
    return "https://tioanime.com/";
  }

  async watch(url) {
    if (url.includes("yourupload.com")) {
      return await this._watchYourUpload(url);
    }
    if (url.includes("hqq.tv") || url.includes("netu.tv") || url.includes("netu.ac")) {
      return await this._watchNetu(url);
    }
    if (url.includes("ok.ru")) {
      return await this._watchOkru(url);
    }
    if (url.includes("mp4upload.com")) {
      return await this._watchMp4Upload(url);
    }
    if (url.includes("streamtape.com")) {
      return await this._watchStreamtape(url);
    }
    if (url.startsWith("https://") && !url.includes("jimov-api")) {
      return { type: "hls", url: "error://unsupported-server" };
    }

    const servers = await this.req(url);
    const list = Array.isArray(servers) ? servers : [];

    if (list.length === 0) {
      return { type: "hls", url: "error://no-servers-found" };
    }

    const embedUrls = {};
    const referers = {};
    for (const s of list) {
      if (s && s.name && s.url) {
        embedUrls[s.name] = s.url;
        referers[s.name] = this._refererFor(s.url);
      }
    }

    const preferred = ["YourUpload", "Netu", "HQQ", "Okru", "Mp4Upload", "Streamtape"];
    const allNames = [
      ...preferred.filter((n) => embedUrls[n]),
      ...Object.keys(embedUrls).filter((n) => !preferred.includes(n)),
    ];

    let primaryName = null;
    let primaryResult = null;

    for (const name of allNames) {
      if (!embedUrls[name]) continue;
      try {
        const result = await this._extractByEmbedUrl(embedUrls[name]);
        if (result && !result.url.startsWith("error://")) {
          primaryName = name;
          primaryResult = result;
          break;
        }
      } catch (_) {}
    }

    if (!primaryName) {
      return {
        type: "hls",
        url: "error://no-playable-server",
        headers: {
          "X-Servers": JSON.stringify(embedUrls),
          "X-Server-Referers": JSON.stringify(referers),
          "X-Primary-Server": allNames[0] || "",
        },
      };
    }

    return {
      type: "hls",
      url: primaryResult.url,
      headers: {
        ...(primaryResult.headers || {}),
        "Referer": referers[primaryName] || this._refererFor(embedUrls[primaryName]),
        "X-Servers": JSON.stringify(embedUrls),
        "X-Server-Referers": JSON.stringify(referers),
        "X-Primary-Server": primaryName,
      },
    };
  }

  async _extractByEmbedUrl(embedUrl) {
    if (embedUrl.includes("yourupload.com")) return this._watchYourUpload(embedUrl);
    if (embedUrl.includes("hqq.tv") || embedUrl.includes("netu")) return this._watchNetu(embedUrl);
    if (embedUrl.includes("ok.ru")) return this._watchOkru(embedUrl);
    if (embedUrl.includes("mp4upload.com")) return this._watchMp4Upload(embedUrl);
    if (embedUrl.includes("streamtape.com")) return this._watchStreamtape(embedUrl);
    return { type: "hls", url: "error://unsupported-server" };
  }

  async _watchYourUpload(embedUrl) {
    const html = await this.request("", {
      headers: { "Miru-Url": embedUrl },
    });
    if (!html || typeof html !== "string" || html.length < 100) {
      return { type: "hls", url: "error://extraction-failed" };
    }
    const m = html.match(/file:\s*['"]?(https?:\/\/[^'"<>\s]+\.mp4[^'"<>\s]*)/);
    if (!m) return { type: "hls", url: "error://extraction-failed" };
    const videoUrl = m[1];
    if (videoUrl.includes("novideo") || videoUrl.includes("/embed/")) {
      return { type: "hls", url: "error://extraction-failed" };
    }
    return {
      type: "hls",
      url: videoUrl,
      headers: { Referer: "https://www.yourupload.com/" },
    };
  }

  async _watchNetu(embedUrl) {
    const mirrors = [embedUrl];
    if (embedUrl.includes("hqq.tv"))
      mirrors.push(embedUrl.replace("hqq.tv", "hqq.net"));
    if (embedUrl.includes("netu.ac"))
      mirrors.push(embedUrl.replace("netu.ac", "hqq.tv"));
    if (embedUrl.includes("netu.tv"))
      mirrors.push(embedUrl.replace("netu.tv", "hqq.tv"));

    const ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";

    for (const mirrorUrl of mirrors) {
      let html;
      try {
        html = await this.request("", {
          headers: {
            "Miru-Url": mirrorUrl,
            "Referer": "https://tioanime.com",
            "User-Agent": ua,
            "Accept": "text/html,application/xhtml+xml,*/*",
            "Accept-Language": "es-ES,es;q=0.9,en;q=0.8",
          },
        });
      } catch (_) { continue; }

      if (!html || typeof html !== "string" || html.length < 100) continue;

      const patterns = [
        /'(https?:\/\/[^']+\.m3u8[^']*)'/g,
        /"(https?:\/\/[^"]+\.m3u8[^"]*)"/g,
        /file:\s*["']?(https?:\/\/[^"'<>\s]+\.m3u8[^"'<>\s]*)/g,
        /source\s*[=:]\s*["']?(https?:\/\/[^"'<>\s]+\.m3u8[^"'<>\s]*)/g,
        /url:\s*["'](https?:\/\/[^"']+\.m3u8[^"']*)/g,
        /'(https?:\/\/[^']+\.mp4[^']*)'/g,
        /"(https?:\/\/[^"]+\.mp4[^"]*)"/g,
      ];

      const found = [];
      const seen = new Set();
      for (const pattern of patterns) {
        let m;
        const re = new RegExp(pattern.source, "g");
        while ((m = re.exec(html)) !== null) {
          const u = m[1].replace(/\\/g, "");
          if (!seen.has(u) &&
              !u.includes("undefined") &&
              !u.includes("null") &&
              u.startsWith("http")) {
            seen.add(u);
            found.push(u);
          }
        }
      }

      if (found.length === 0) continue;

      const primary = found[0];
      const cdnReferer = primary.includes("cfglobalcdn.com") || primary.includes("netu") || primary.includes("hqq")
        ? "https://hqq.tv/"
        : "https://tioanime.com/";

      const result = {
        type: "hls",
        url: primary,
        headers: {
          "Referer":    cdnReferer,
          "Origin":     cdnReferer.replace(/\/$/, ""),
          "User-Agent": ua,
        },
      };
      if (found.length > 1) {
        result.headers["X-Netu-Alts"] = JSON.stringify(found.slice(1));
      }
      return result;
    }

    return { type: "hls", url: "error://extraction-failed" };
  }

  async _watchOkru(embedUrl) {
    const html = await this.request("", {
      headers: {
        "Miru-Url": embedUrl,
        Referer: "https://tioanime.com",
      },
    });
    if (!html || typeof html !== "string" || html.length < 100) {
      return { type: "hls", url: "error://extraction-failed" };
    }
    const m = html.match(/"hlsMasterPlaylistUrl":"([^"]+)"/);
    if (m) {
      return {
        type: "hls",
        url: m[1].replace(/\\/g, ""),
        headers: { Referer: "https://ok.ru/" },
      };
    }
    const mp4 = html.match(/"mp4":\s*\[.*?"src":"([^"]+)"/s);
    if (mp4) {
      return {
        type: "hls",
        url: mp4[1].replace(/\\/g, ""),
        headers: { Referer: "https://ok.ru/" },
      };
    }
    return { type: "hls", url: "error://extraction-failed" };
  }

  async _watchMp4Upload(embedUrl) {
    const html = await this.request("", {
      headers: {
        "Miru-Url": embedUrl,
        Referer: "https://tioanime.com",
      },
    });
    if (!html || typeof html !== "string" || html.length < 100) {
      return { type: "hls", url: "error://extraction-failed" };
    }
    const m = html.match(/src:\s*"(https?:\/\/[^"]+\.mp4[^"]*)"/);
    if (!m) return { type: "hls", url: "error://extraction-failed" };
    return {
      type: "hls",
      url: m[1],
      headers: { Referer: "https://www.mp4upload.com/" },
    };
  }

  async _watchStreamtape(embedUrl) {
    const html = await this.request("", {
      headers: {
        "Miru-Url": embedUrl,
        Referer: "https://tioanime.com",
      },
    });
    if (!html || typeof html !== "string" || html.length < 100) {
      return { type: "hls", url: "error://extraction-failed" };
    }
    const m = html.match(/id="ideoooolink"[^>]*>([^<]+)<\/a>/);
    if (m) {
      return {
        type: "hls",
        url: "https:" + m[1].trim(),
        headers: { Referer: "https://streamtape.com/" },
      };
    }
    const m2 = html.match(/&token=[^&"]+&expires=[^"]+/);
    const base = html.match(/\/\/[^"]*streamtape[^/]+\/get_video\?/);
    if (m2 && base) {
      return {
        type: "hls",
        url: "https:" + base[0] + m2[0],
        headers: { Referer: "https://streamtape.com/" },
      };
    }
    return { type: "hls", url: "error://extraction-failed" };
  }
}
