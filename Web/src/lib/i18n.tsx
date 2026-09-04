import { createContext, useContext, useEffect, useState, type ReactNode } from 'react';

export type Lang = 'es' | 'en';

const STORAGE_KEY = 'prismhub-lang';

// Colocar el diccionario, el contexto, el proveedor y el hook en un mismo
// archivo es el patrón habitual para esto — separarlos en más archivos no
// gana nada salvo que el refresco en caliente de Vite sea "rápido" en vez de
// una recarga completa durante el desarrollo, que es justo lo único que
// avisa esta regla.
// eslint-disable-next-line react-refresh/only-export-components
export const dict = {
  es: {
    'nav.home': 'Inicio',
    'nav.docs': 'Docs',
    'nav.faq': 'FAQ',
    'nav.developers': 'Extensiones',
    'nav.license': 'Licencia',
    'nav.github': 'GitHub',
    'nav.theme': 'Cambiar tema',
    'nav.lang': 'Cambiar idioma',

    'hero.badge': 'Open source · sin anuncios · AGPL-3.0',
    'hero.title.1': 'Todo tu contenido,',
    'hero.title.2': 'una sola app nativa.',
    'hero.subtitle':
      'Anime, manga, novelas, series y películas desde extensiones JavaScript que instalás vos. Sin límites de catálogo, sin cuentas, sin anuncios.',
    'hero.cta.download': 'Descargar PrismHub',
    'hero.cta.windows': 'Instalar en Windows',
    'hero.cta.linux': 'Instalar en Linux',
    'hero.cta.android': 'Instalar en Android',
    'hero.cta.source': 'Ver código fuente',
    'hero.stat.extensions': 'extensiones activas',
    'hero.stat.platforms': 'plataformas nativas',
    'hero.stat.license': 'licencia',

    'platforms.windows': 'Windows',
    'platforms.linux': 'Linux',
    'platforms.android': 'Android',
    'platforms.androidTv': 'Android TV',
    'platforms.install': 'Instalar',
    'platforms.new': 'NUEVO',

    'features.eyebrow': 'Por qué PrismHub',
    'features.title': 'Construido sobre extensiones, no un catálogo fijo',
    'features.f1.title': 'El contenido no está incrustado en la app',
    'features.f1.desc':
      'Cada fuente es una extensión que mantiene prism+, el repositorio oficial. Sitios nuevos y arreglos llegan actualizando el catálogo, sin esperar una versión nueva de la app entera.',
    'features.f2.title': 'Nativo de verdad',
    'features.f2.desc':
      'Flutter compilado a binario en cada plataforma — no es una página web empaquetada. Arranca rápido y usa la memoria que el aparato realmente tiene.',
    'features.f3.title': 'Varios servidores por episodio',
    'features.f3.desc':
      'Si uno falla, cambiar al siguiente es un solo toque: el reproductor ya trae la lista completa que declaró la extensión, no hay que salir a buscarla.',
    'features.f4.title': 'Pensado también para el televisor',
    'features.f4.desc':
      'El mismo APK de Android funciona en Android TV, con una interfaz propia para control remoto: filas densas, foco visible, sin gestos de dedo.',
    'features.f5.title': 'Tu progreso, en tu aparato',
    'features.f5.desc':
      'Sin cuentas ni servidores propios que guarden qué mirás. El historial y los favoritos viven en el aparato donde los usás.',
    'features.f6.title': 'Código abierto de punta a punta',
    'features.f6.desc':
      'AGPL-3.0: la app y el repositorio oficial de extensiones son públicos. Se puede auditar, forkear y compilar desde cero.',

    'showcase.eyebrow': 'La app, tal cual se ve',
    'showcase.title': 'Un diseño distinto por plataforma, no una web estirada',
    'showcase.desc':
      'Escritorio, teléfono y televisor no navegan igual — cada uno tiene su propia interfaz, no un mismo diseño achicado o agrandado.',

    'requirements.eyebrow': 'Antes de instalar',
    'requirements.title': 'Requisitos',
    'requirements.desc':
      'Los umbrales de abajo son los mismos que usa la app para decidir cuánta calidad pedir y cuántos procesos mantener vivos — no un número de marketing.',
    'requirements.min': 'Mínimos',
    'requirements.rec': 'Recomendados',
    'requirements.os': 'Sistema',
    'requirements.ram': 'Memoria',
    'requirements.cpu': 'Procesador',
    'requirements.storage': 'Espacio en disco',
    'requirements.note':
      'Por debajo de los mínimos la app sigue andando: baja la calidad de vídeo, decodifica imágenes más chicas y suelta lo que no se está usando con más agresividad. No hay un piso que la deje afuera.',
    'requirements.tipTitle': 'Para que ande lo más fluido posible',
    'requirements.tip':
      'Cumplir los recomendados no alcanza si la conexión a internet es inestable: todo se transmite en vivo desde cada sitio, no hay descargas, así que un corte o una red lenta se nota como lag aunque el aparato sobre. El resto es trabajo nuestro: la app tiene que andar fluida y estable así el aparato esté con otras cosas abiertas al mismo tiempo, jugando o lo que sea — por eso cada versión trae mejoras de rendimiento reales, no solo funciones nuevas.',

    'download.beforeTitle': 'Antes de instalar',
    'download.eyebrow': 'Descargar',
    'download.title': 'Elegí tu plataforma',
    'download.version': 'Versión',
    'download.size': 'Tamaño',
    'download.notes': 'Ver notas de la versión',
    'download.betaZone': 'Beta',
    'download.betaZoneDesc': 'Lo único que existe por ahora — probado, pero todavía en pulido activo.',
    'download.stableZone': 'Versión estable · oficial',
    'download.stableZoneDesc': 'La primera versión 1.0 llega cuando la beta esté lo bastante probada.',
    'download.stableEmpty': 'Todavía no hay nada acá: la primera versión estable va a ser la 1.1.0, cuando la beta esté lo bastante probada.',
    'download.releases': 'Todas las versiones en GitHub Releases →',

    'footer.tagline': 'Anime, manga, novelas, series y películas — sin límites. Open source, nativo, sin anuncios.',
    'footer.product': 'Producto',
    'footer.install': 'Instalar',
    'footer.project': 'Proyecto',
    'footer.source': 'Código fuente',
    'footer.extensionsRepo': 'Extensiones (prism+)',
    'footer.reportBug': 'Reportar un bug',
    'footer.allReleases': 'Releases en GitHub',
  },
  en: {
    'nav.home': 'Home',
    'nav.docs': 'Docs',
    'nav.faq': 'FAQ',
    'nav.developers': 'Extensions',
    'nav.license': 'License',
    'nav.github': 'GitHub',
    'nav.theme': 'Toggle theme',
    'nav.lang': 'Change language',

    'hero.badge': 'Open source · no ads · AGPL-3.0',
    'hero.title.1': 'All your content,',
    'hero.title.2': 'one native app.',
    'hero.subtitle':
      'Anime, manga, novels, series and movies from JavaScript extensions you install yourself. No catalog limits, no accounts, no ads.',
    'hero.cta.download': 'Download PrismHub',
    'hero.cta.windows': 'Install on Windows',
    'hero.cta.linux': 'Install on Linux',
    'hero.cta.android': 'Install on Android',
    'hero.cta.source': 'View source code',
    'hero.stat.extensions': 'active extensions',
    'hero.stat.platforms': 'native platforms',
    'hero.stat.license': 'license',

    'platforms.windows': 'Windows',
    'platforms.linux': 'Linux',
    'platforms.android': 'Android',
    'platforms.androidTv': 'Android TV',
    'platforms.install': 'Install',
    'platforms.new': 'NEW',

    'features.eyebrow': 'Why PrismHub',
    'features.title': 'Built on extensions, not a fixed catalog',
    'features.f1.title': "Content isn't baked into the app",
    'features.f1.desc':
      "Every source is an extension maintained by prism+, the official repository. New sites and fixes ship by updating the catalog, with no need to wait for a whole new app version.",
    'features.f2.title': 'Actually native',
    'features.f2.desc':
      'Flutter compiled to a binary on every platform — not a packaged web page. Starts fast and uses the memory the device actually has.',
    'features.f3.title': 'Several servers per episode',
    'features.f3.desc':
      "If one goes down, switching to the next is a single tap: the player already has the full list the extension declared, no need to go looking for it.",
    'features.f4.title': 'Built for the TV too',
    'features.f4.desc':
      "The same Android APK runs on Android TV, with its own remote-friendly interface: dense rows, visible focus, no finger gestures.",
    'features.f5.title': 'Your progress, on your device',
    'features.f5.desc':
      "No accounts, no servers of ours tracking what you watch. History and favorites live on the device you use them on.",
    'features.f6.title': 'Open source end to end',
    'features.f6.desc':
      'AGPL-3.0: the app and the official extensions repository are both public. Audit it, fork it, build it from scratch.',

    'showcase.eyebrow': 'The app, as it looks',
    'showcase.title': 'A different design per platform, not a stretched webpage',
    'showcase.desc':
      "Desktop, phone and TV don't navigate the same way — each gets its own interface, not one layout scaled up or down.",

    'requirements.eyebrow': 'Before installing',
    'requirements.title': 'Requirements',
    'requirements.desc':
      "The thresholds below are the same ones the app uses to decide how much quality to request and how many processes to keep alive — not a marketing figure.",
    'requirements.min': 'Minimum',
    'requirements.rec': 'Recommended',
    'requirements.os': 'OS',
    'requirements.ram': 'Memory',
    'requirements.cpu': 'Processor',
    'requirements.storage': 'Disk space',
    'requirements.note':
      "Below the minimum the app still runs: it lowers video quality, decodes smaller images and releases what's not in use more aggressively. There's no floor that locks you out.",
    'requirements.tipTitle': 'For the smoothest experience',
    'requirements.tip':
      "Meeting the recommended specs isn't enough if the internet connection is unstable: everything streams live from each site, there are no downloads, so a drop or a slow network shows up as lag even on a device that's more than capable. The rest is on us: the app has to stay smooth and stable even with other heavy things running at the same time, gaming or whatever else — that's why every release ships real performance improvements, not just new features.",

    'download.beforeTitle': 'Before installing',
    'download.eyebrow': 'Download',
    'download.title': 'Pick your platform',
    'download.version': 'Version',
    'download.size': 'Size',
    'download.notes': 'View release notes',
    'download.betaZone': 'Beta',
    'download.betaZoneDesc': "The only thing that exists right now — tested, but still actively being polished.",
    'download.stableZone': 'Stable version · official',
    'download.stableZoneDesc': "The first 1.0 release ships once the beta has been tested enough.",
    'download.stableEmpty': "Nothing here yet — for now, the whole app lives in Beta.",
    'download.releases': 'All versions on GitHub Releases →',

    'footer.tagline': 'Anime, manga, novels, series and movies — no limits. Open source, native, no ads.',
    'footer.product': 'Product',
    'footer.install': 'Install',
    'footer.project': 'Project',
    'footer.source': 'Source code',
    'footer.extensionsRepo': 'Extensions (prism+)',
    'footer.reportBug': 'Report a bug',
    'footer.allReleases': 'Releases on GitHub',
  },
} as const;

export type DictKey = keyof (typeof dict)['es'];

function readInitialLang(): Lang {
  if (typeof window === 'undefined') return 'es';
  const saved = window.localStorage.getItem(STORAGE_KEY);
  if (saved === 'es' || saved === 'en') return saved;
  // PrismHub nació en español (assets/i18n/es.json es la fuente en la app);
  // el navegador solo decide para quien nunca lo dijo.
  return navigator.language?.toLowerCase().startsWith('en') ? 'en' : 'es';
}

const LangContext = createContext<{ lang: Lang; setLang: (l: Lang) => void; t: (k: DictKey) => string } | null>(
  null,
);

export function LangProvider({ children }: { children: ReactNode }) {
  const [lang, setLang] = useState<Lang>(readInitialLang);

  useEffect(() => {
    document.documentElement.setAttribute('lang', lang);
    window.localStorage.setItem(STORAGE_KEY, lang);
  }, [lang]);

  const t = (key: DictKey) => dict[lang][key] ?? dict.es[key] ?? key;

  return <LangContext.Provider value={{ lang, setLang, t }}>{children}</LangContext.Provider>;
}

// eslint-disable-next-line react-refresh/only-export-components
export function useLang() {
  const ctx = useContext(LangContext);
  if (!ctx) throw new Error('useLang debe usarse dentro de LangProvider');
  return ctx;
}
