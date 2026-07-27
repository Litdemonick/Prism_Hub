import { useEffect, useState } from 'react';

export const REPO = 'Litdemonick/Prism_Hub';

export type ReleaseAsset = { name: string; browser_download_url: string; size: number };
export type ReleaseInfo = {
  tag: string;
  htmlUrl: string;
  body?: string;
  publishedAt?: string;
  windows?: ReleaseAsset;
  linux?: ReleaseAsset;
  android?: ReleaseAsset;
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
  return {
    tag: data.tag_name,
    htmlUrl: data.html_url,
    body: data.body,
    publishedAt: data.published_at,
    windows: find(/\.exe$/i) || find(/windows.*\.zip$/i),
    linux: find(/linux.*\.tar\.gz$/i),
    android: find(/arm64-v8a.*\.apk$/i) || find(/\.apk$/i),
  };
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
