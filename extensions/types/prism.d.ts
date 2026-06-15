/**
 * Prism+ SDK — Tipos para extensiones PrismHub
 *
 * Contrato idéntico al SDK de Prism+ (https://github.com/Litdemonick/prism-plus).
 * Importa desde aquí para que tus extensiones sean compatibles con ambos ecosistemas.
 */

// ---------------------------------------------------------------------------
// Tipos base
// ---------------------------------------------------------------------------

export type MediaType =
  | 'anime'        // Animación japonesa / donghua
  | 'manga'        // Cómics japoneses, manhwa, manhua, webtoon
  | 'novel'        // Light novels, web novels
  | 'movie'        // Películas
  | 'series'       // Series de TV, dramas, doramas
  | 'documentary'  // Documentales
  | 'live'         // Canales en vivo / IPTV
  | 'video'        // Contenido de vídeo general
  | 'music'        // Vídeos musicales
  | 'podcast'      // Podcasts con vídeo o audio
  | 'other'        // Cualquier otro tipo

export type ContentStatus = 'ongoing' | 'completed' | 'upcoming' | 'hiatus'

// ---------------------------------------------------------------------------
// Paginación
// ---------------------------------------------------------------------------

/** Resultado paginado — retornable como alternativa a PrismItem[] */
export interface PrismPage<T = PrismItem> {
  items: T[]
  /** false = no hay más páginas */
  hasMore: boolean
  /** Total de resultados si la API lo provee */
  total?: number
}

// ---------------------------------------------------------------------------
// Listas
// ---------------------------------------------------------------------------

/** Ítem de lista — retornado por latest() y search() */
export interface PrismItem {
  title: string
  url: string
  cover?: string
  description?: string
  tags?: string[]
  year?: number
  rating?: number
  /** Sobreescribe el tipo de la extensión para contenido mixto */
  type?: MediaType
}

// ---------------------------------------------------------------------------
// Detalle
// ---------------------------------------------------------------------------

export interface PrismEpisode {
  title: string
  url: string
  thumbnail?: string
  /** Duración en segundos */
  duration?: number
  /** ISO 8601 (YYYY-MM-DD) */
  airDate?: string
  number?: number
}

export interface PrismSeason {
  title: string
  episodes: PrismEpisode[]
  year?: number
  cover?: string
}

export interface PrismDetail {
  title: string
  cover?: string
  description?: string
  /** Lista plana de episodios (sin temporadas) */
  episodes: PrismEpisode[]
  seasons?: PrismSeason[]
  genres?: string[]
  status?: ContentStatus
  year?: number
  rating?: number
  /** Metadatos extra clave-valor */
  extra?: Record<string, string>
}

// ---------------------------------------------------------------------------
// Reproducción
// ---------------------------------------------------------------------------

export interface PrismStream {
  url: string
  quality?: string
  label?: string
  headers?: Record<string, string>
  mimeType?: string
}

export interface PrismSubtitle {
  label: string
  url: string
  /** BCP-47 (es, en, ja, etc.) */
  lang?: string
}

export interface PrismWatch {
  streams: PrismStream[]
  subtitles?: PrismSubtitle[]
  /** Headers globales para todos los streams */
  headers?: Record<string, string>
  /**
   * Razón por la que streams[] está vacío.
   * Ejemplos: "region_blocked", "premium_required", "js_eval_required"
   */
  reason?: string
}

// ---------------------------------------------------------------------------
// Filtros (compatibilidad)
// ---------------------------------------------------------------------------

export type FilterValue = string | number | boolean

export interface PrismFilter {
  [key: string]: FilterValue
}
