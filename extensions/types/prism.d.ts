/**
 * PrismHub Extension API — Type Definitions
 *
 * Cada extensión es un módulo TypeScript que exporta las cuatro funciones
 * requeridas. Después de compilar con esbuild, el bundle JS resultante es
 * ejecutado por flutter_js dentro de la app.
 */

// ---------------------------------------------------------------------------
// Datos comunes
// ---------------------------------------------------------------------------

export interface PrismItem {
  title: string
  url: string
  cover?: string
  description?: string
  tags?: string[]
}

export interface PrismEpisode {
  /** Título visible del episodio / capítulo */
  title: string
  /** URL que se pasará a watch() o al lector */
  url: string
}

export interface PrismDetail {
  title: string
  cover?: string
  description?: string
  /** Tipo de contenido para elegir reproductor/lector */
  type: 'anime' | 'manga' | 'comic' | 'novel'
  episodes: PrismEpisode[]
  extra?: Record<string, string>
}

export interface PrismStream {
  /** URL del stream / imagen de página */
  url: string
  /** Calidad o label (e.g. "1080p", "HD") */
  quality?: string
  /** Headers HTTP necesarios (Referer, etc.) */
  headers?: Record<string, string>
}

export interface PrismSubtitle {
  label: string
  url: string
  lang?: string
}

export interface PrismWatch {
  streams: PrismStream[]
  subtitles?: PrismSubtitle[]
}

// ---------------------------------------------------------------------------
// Filtros de búsqueda
// ---------------------------------------------------------------------------

export type FilterValue = string | number | boolean

export interface PrismFilter {
  [key: string]: FilterValue
}

// ---------------------------------------------------------------------------
// Contrato de la extensión
// Las cuatro funciones que DEBE exportar cada extensión
// ---------------------------------------------------------------------------

export interface PrismExtension {
  /**
   * Devuelve los últimos contenidos agregados (paginado).
   * @param page Número de página, empieza en 1
   */
  latest(page: number): Promise<PrismItem[]>

  /**
   * Búsqueda por palabra clave.
   * @param keyword Término de búsqueda
   * @param page Número de página, empieza en 1
   * @param filter Filtros opcionales (género, año, etc.)
   */
  search(keyword: string, page: number, filter?: PrismFilter): Promise<PrismItem[]>

  /**
   * Detalle completo de un contenido: metadata + lista de episodios/capítulos.
   * @param url URL del contenido (obtenida de PrismItem.url)
   */
  detail(url: string): Promise<PrismDetail>

  /**
   * Streams de reproducción o páginas del capítulo.
   * @param url URL del episodio/capítulo (obtenida de PrismEpisode.url)
   */
  watch(url: string): Promise<PrismWatch>
}
