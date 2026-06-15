/**
 * Plantilla de extensión PrismHub / Prism+
 *
 * Copia esta carpeta con el nombre de tu extensión:
 *   node scripts/new-extension.mjs nombre-extension
 *
 * Compila después de editar:
 *   npm run build -- --extension=nombre-extension
 *
 * Tipos: ../types/prism.d.ts — idéntico al SDK de Prism+
 */

import type {
  PrismItem,
  PrismPage,
  PrismDetail,
  PrismWatch,
  PrismFilter,
} from '../types/prism'

// ---------------------------------------------------------------------------
// Metadata — refleja estos valores en extensions/index.json
// ---------------------------------------------------------------------------

export const meta = {
  name: 'PrismPlusExtension',
  package: 'io.prismhub.my-extension',
  version: '1.0.0',
  author: 'Litdemonick',
  type: 'anime' as const,
  description: 'Extension description',
  icon: '',
  baseUrl: 'https://target-site.com',
}

// ---------------------------------------------------------------------------
// Helpers internos
// ---------------------------------------------------------------------------

async function fetchHtml(url: string, headers?: Record<string, string>): Promise<string> {
  const res = await fetch(url, {
    headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      ...headers,
    },
  })
  if (!res.ok) throw new Error(`HTTP ${res.status} — ${url}`)
  return res.text()
}

// ---------------------------------------------------------------------------
// API requerida
// ---------------------------------------------------------------------------

export async function latest(page: number): Promise<PrismItem[] | PrismPage<PrismItem>> {
  const html = await fetchHtml(`${meta.baseUrl}/page/${page}`)
  // TODO: parsear HTML y retornar items
  console.log('[latest] page', page, 'html length', html.length)
  return []
}

export async function search(
  keyword: string,
  page: number,
  _filter?: PrismFilter,
): Promise<PrismItem[] | PrismPage<PrismItem>> {
  const url = `${meta.baseUrl}/search?q=${encodeURIComponent(keyword)}&page=${page}`
  const html = await fetchHtml(url)
  // TODO: parsear HTML y retornar items
  console.log('[search]', keyword, 'page', page, 'html length', html.length)
  return []
}

export async function detail(url: string): Promise<PrismDetail> {
  const html = await fetchHtml(url)
  // TODO: parsear HTML y retornar detalle + episodios
  console.log('[detail]', url, html.length)
  return {
    title: '',
    episodes: [],
  }
}

export async function watch(url: string): Promise<PrismWatch> {
  const html = await fetchHtml(url)
  // TODO: extraer URLs de stream o páginas del capítulo
  console.log('[watch]', url, html.length)
  return {
    streams: [],
  }
}
