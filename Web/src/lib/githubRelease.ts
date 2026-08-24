import { useEffect, useState } from 'react';

export const REPO = 'Litdemonick/Prism_Hub';
export const APP_VERSION = 'v1.0.10';

export type ReleaseAsset = { name: string; browser_download_url: string; size: number };
export type ReleaseInfo = {
  tag: string;
  htmlUrl: string;
  body?: string;
  publishedAt?: string;
  windows?: ReleaseAsset;
  linux?: ReleaseAsset;
  android?: ReleaseAsset;
  /// El APK con nombre de televisor. Es una copia IDENTICA del de Android
  /// —un solo APK sirve para telefono, tablet y TV— y existe para que en la
  /// pagina se vea de un vistazo cual bajar para un televisor.
  androidTv?: ReleaseAsset;
  androidArm64?: ReleaseAsset;
  androidArmv7?: ReleaseAsset;
  androidX64?: ReleaseAsset;
};

export type DownloadPlatform = 'windows' | 'linux' | 'android' | 'androidTv';
export type AndroidVariant = 'auto' | 'arm64-v8a' | 'armeabi-v7a' | 'x86_64';

const fallbackAssetNames = {
  windows: `PrismHub-setup-windows-${APP_VERSION}.exe`,
  androidTv: `PrismHub-androidtv-arm64-v8a.apk`,
  linux: `PrismHub-${APP_VERSION}-linux-x64.tar.gz`,
  androidArm64: `PrismHub-${APP_VERSION}-arm64-v8a.apk`,
  androidArmv7: `PrismHub-${APP_VERSION}-armeabi-v7a.apk`,
  androidX64: `PrismHub-${APP_VERSION}-x86_64.apk`,
};

function latestDownloadUrl(assetName: string) {
  return `https://github.com/${REPO}/releases/latest/download/${assetName}`;
}

export const fallbackDownloads = {
  windows: latestDownloadUrl(fallbackAssetNames.windows),
  androidTv: latestDownloadUrl(fallbackAssetNames.androidTv),
  linux: latestDownloadUrl(fallbackAssetNames.linux),
  androidArm64: latestDownloadUrl(fallbackAssetNames.androidArm64),
  androidArmv7: latestDownloadUrl(fallbackAssetNames.androidArmv7),
  androidX64: latestDownloadUrl(fallbackAssetNames.androidX64),
};

export function formatDate(iso?: string) {
  if (!iso) return '';
  return new Date(iso).toLocaleDateString('es-ES', {
    day: 'numeric',
    month: 'long',
    year: 'numeric',
  });
}

export function formatSize(bytes?: number) {
  if (!bytes) return '';
  const mb = bytes / (1024 * 1024);
  return `${mb.toFixed(0)} MB`;
}

function assetsToRelease(data: {
  tag_name: string;
  html_url: string;
  body?: string;
  published_at?: string;
  assets?: ReleaseAsset[];
}): ReleaseInfo {
  const assets: ReleaseAsset[] = data.assets || [];
  const find = (re: RegExp) => assets.find((a) => re.test(a.name));
  // Los APK de televisor llevan "androidtv" en el nombre y son una copia
  // identica de los de Android. Se excluyen de la busqueda de telefono para
  // que cada boton apunte al archivo que dice su nombre — si no, el de
  // "Android" podia terminar ofreciendo el de TV, que confunde aunque sea el
  // mismo archivo.
  const esDeTv = (nombre: string) => /androidtv/i.test(nombre);
  const buscarApk = (re: RegExp) =>
    assets.find((a) => re.test(a.name) && !esDeTv(a.name));
  const androidArm64 = buscarApk(/arm64-v8a.*\.apk$/i);
  const androidArmv7 = buscarApk(/armeabi-v7a.*\.apk$/i);
  const androidX64 = buscarApk(/x86_64.*\.apk$/i);
  const androidTv = find(/androidtv.*arm64-v8a.*\.apk$/i) ||
      find(/androidtv.*\.apk$/i);
  return {
    tag: data.tag_name,
    htmlUrl: data.html_url,
    body: data.body,
    publishedAt: data.published_at,
    windows: find(/setup.*\.exe$/i) || find(/\.exe$/i) || find(/windows.*\.zip$/i),
    linux: find(/linux.*\.tar\.gz$/i),
    android: androidArm64 || androidArmv7 || androidX64 || find(/\.apk$/i),
    // Si un release viejo no trae el de televisor, se cae al de Android: es
    // el mismo archivo, asi que el boton sigue sirviendo igual.
    androidTv: androidTv || androidArm64 || find(/\.apk$/i),
    androidArm64,
    androidArmv7,
    androidX64,
  };
}

export function detectAndroidVariant(): AndroidVariant {
  if (typeof navigator === 'undefined') return 'arm64-v8a';
  const ua = navigator.userAgent.toLowerCase();
  if (ua.includes('x86_64') || ua.includes('x64')) return 'x86_64';
  if (ua.includes('x86')) return 'x86_64';
  if (ua.includes('armeabi-v7a') || ua.includes('armv7')) return 'armeabi-v7a';
  return 'arm64-v8a';
}

export function getAndroidAsset(
  release?: ReleaseInfo | null,
  variant: AndroidVariant = 'auto',
) {
  const resolved = variant === 'auto' ? detectAndroidVariant() : variant;
  if (resolved === 'x86_64') return release?.androidX64 || release?.androidArm64 || release?.android;
  if (resolved === 'armeabi-v7a') return release?.androidArmv7 || release?.androidArm64 || release?.android;
  return release?.androidArm64 || release?.android;
}

export function getAndroidDownloadHref(
  release?: ReleaseInfo | null,
  variant: AndroidVariant = 'auto',
) {
  const resolved = variant === 'auto' ? detectAndroidVariant() : variant;
  const asset = getAndroidAsset(release, resolved);
  if (asset?.browser_download_url) return asset.browser_download_url;
  if (resolved === 'x86_64') return fallbackDownloads.androidX64;
  if (resolved === 'armeabi-v7a') return fallbackDownloads.androidArmv7;
  return fallbackDownloads.androidArm64;
}

export function getDirectDownloadHref(
  release: ReleaseInfo | null | undefined,
  platform: DownloadPlatform,
) {
  if (platform === 'android') return getAndroidDownloadHref(release);
  return release?.[platform]?.browser_download_url || fallbackDownloads[platform];
}

/** Últimas N releases publicadas (para mostrar historial/changelog real en
 * vez de texto escrito a mano que se desactualiza en cada versión nueva). */
export function useReleases(limit = 2) {
  const [releases, setReleases] = useState<ReleaseInfo[] | null>(null);
  useEffect(() => {
    let cancelled = false;
    fetch(`https://api.github.com/repos/${REPO}/releases?per_page=${limit}`)
      .then((r) => (r.ok ? r.json() : Promise.reject(r.status)))
      .then((data: unknown[]) => {
        if (cancelled) return;
        setReleases(
          (data as Parameters<typeof assetsToRelease>[0][]).map(assetsToRelease),
        );
      })
      .catch(() => {
        if (!cancelled) setReleases([]);
      });
    return () => {
      cancelled = true;
    };
  }, [limit]);
  return releases;
}

/** Solo la última release — usado por los botones de descarga directa
 * (Windows/Linux/Android) fuera de la sección de historial. */
export function useLatestRelease() {
  const releases = useReleases(1);
  return releases?.[0] ?? null;
}

/** Cuenta real de extensiones del repo oficial (no un número fijo en el código
 * que se desactualiza solo — se lee el catálogo real en cada carga). */
export function useExtensionCount() {
  const [count, setCount] = useState<number | null>(null);
  useEffect(() => {
    let cancelled = false;
    fetch('https://raw.githubusercontent.com/Litdemonick/prism-plus/main/index.json')
      .then((r) => r.json())
      .then((data) => {
        if (cancelled) return;
        const list = Array.isArray(data) ? data : data.extensions || [];
        setCount(list.length);
      })
      .catch(() => {});
    return () => {
      cancelled = true;
    };
  }, []);
  return count;
}
