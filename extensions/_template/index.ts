/**
 * PrismHub Extension Template
 *
 * Copia esta carpeta, renómbrala y rellena las funciones.
 * Compila con:  npm run build -- --extension=mi-extension
 */

import type { PrismItem, PrismDetail, PrismWatch, PrismFilter } from '../types/prism'

// ---------------------------------------------------------------------------
// Metadata (también declarada en extensions/index.json)
// ---------------------------------------------------------------------------

export const meta = {
  name: 'Mi Extensión',
  package: 'com.prismhub.mi-extension',
  version: '1.0.0',
  author: 'tu-usuario',
  type: 'anime' as const,           // 'anime' | 'manga' | 'comic' | 'novel'
  icon: 'https://example.com/icon.png',
  baseUrl: 'https://example.com',
}

// ---------------------------------------------------------------------------
// Helpers internos (no se exportan)
// ---------------------------------------------------------------------------

async function fetchHtml(url: string): Promise<string> {
  const res = await fetch(url, {
    headers: {
      'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    },
  })
  return res.text()
}

// ---------------------------------------------------------------------------
// API requerida
// ---------------------------------------------------------------------------

export async function latest(page: number): Promise<PrismItem[]> {
  const html = await fetchHtml(`${meta.baseUrl}/page/${page}`)
  // TODO: parsear HTML y devolver items
  console.log('[latest] page', page, 'html length', html.length)
  return []
}

export async function search(
  keyword: string,
  page: number,
  _filter?: PrismFilter
): Promise<PrismItem[]> {
  const url = `${meta.baseUrl}/search?q=${encodeURIComponent(keyword)}&page=${page}`
  const html = await fetchHtml(url)
  // TODO: parsear HTML y devolver items
  console.log('[search]', keyword, html.length)
  return []
}

export async function detail(url: string): Promise<PrismDetail> {
  const html = await fetchHtml(url)
  // TODO: parsear HTML y devolver detalle + episodios
  console.log('[detail]', url, html.length)
  return {
    title: '',
    type: meta.type,
    episodes: [],
  }
}

export async function watch(url: string): Promise<PrismWatch> {
  const html = await fetchHtml(url)
  // TODO: extraer URLs de stream / imágenes del capítulo
  console.log('[watch]', url, html.length)
  return {
    streams: [],
  }
}
