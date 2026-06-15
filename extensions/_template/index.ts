/**
 * Plantilla de extensión PrismHub / Prism+
 *
 * Copia esta carpeta, renómbrala y rellena las cuatro funciones.
 *
 * Compilar:
 *   npm run build -- --extension=mi-extension
 *
 * Tipos: ../types/prism.d.ts  (idéntico al SDK de Prism+)
 */

import type {
  PrismItem,
  PrismPage,
  PrismDetail,
  PrismWatch,
  PrismFilter,
} from '../types/prism'

// ---------------------------------------------------------------------------
// Metadata — también declara estos valores en extensions/index.json
// ---------------------------------------------------------------------------

export const meta = {
  name: 'Mi Extensión',
  package: 'io.prismhub.mi-extension',
  version: '1.0.0',
  author: 'tu-usuario',
  type: 'anime' as const,
  description: 'Descripción corta de la extensión',
  icon: 'https://example.com/icon.png',
  baseUrl: 'https://example.com',
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
// API requerida — las cuatro funciones que DEBE exportar toda extensión
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
