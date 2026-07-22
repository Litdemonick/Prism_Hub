import { useEffect, useState } from 'react';

export const REPO = 'Litdemonick/Prism_Hub';

export type ReleaseAsset = { name: string; browser_download_url: string; size: number };
export type ReleaseInfo = {
  tag: string;
  htmlUrl: string;
  windows?: ReleaseAsset;
  linux?: ReleaseAsset;
  android?: ReleaseAsset;
};

export function formatSize(bytes?: number) {
  if (!bytes) return '';
  const mb = bytes / (1024 * 1024);
  return `${mb.toFixed(0)} MB`;
}

/** Trae la última release de GitHub para armar botones de descarga directa
 * (en vez de asumir un nombre de archivo fijo, que cambia en cada versión). */
export function useLatestRelease() {
  const [release, setRelease] = useState<ReleaseInfo | null>(null);
  useEffect(() => {
    let cancelled = false;
    fetch(`https://api.github.com/repos/${REPO}/releases/latest`)
      .then((r) => (r.ok ? r.json() : Promise.reject(r.status)))
      .then((data) => {
        if (cancelled) return;
        const assets: ReleaseAsset[] = data.assets || [];
        const find = (re: RegExp) => assets.find((a) => re.test(a.name));
        setRelease({
          tag: data.tag_name,
          htmlUrl: data.html_url,
          windows: find(/\.exe$/i) || find(/windows.*\.zip$/i),
          linux: find(/linux.*\.tar\.gz$/i),
          android: find(/arm64-v8a.*\.apk$/i) || find(/\.apk$/i),
        });
      })
      .catch(() => {});
    return () => {
      cancelled = true;
    };
  }, []);
  return release;
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
