/**
 * Build script — compila extensiones TypeScript a bundles JS para PrismHub.
 *
 * Uso:
 *   node scripts/build.mjs                      # compila extensión en cwd
 *   node scripts/build.mjs --extension=animeflv # compila una extensión concreta
 *   node scripts/build.mjs --all                # compila todas las extensiones
 */

import { build } from 'esbuild'
import { readdirSync, existsSync, writeFileSync, readFileSync } from 'fs'
import { join, resolve } from 'path'

const ROOT = resolve(import.meta.dirname, '..')
const EXT_DIR = join(ROOT, 'extensions')
const DIST_DIR = join(EXT_DIR, 'dist')
const INDEX_PATH = join(EXT_DIR, 'index.json')

const args = process.argv.slice(2)
const buildAll = args.includes('--all')
const single = args.find(a => a.startsWith('--extension='))?.split('=')[1]

/** @returns {string[]} carpetas de extensiones (excluye _template, types, dist) */
function getExtensionDirs() {
  return readdirSync(EXT_DIR, { withFileTypes: true })
    .filter(d => d.isDirectory() && !d.name.startsWith('_') && d.name !== 'dist' && d.name !== 'types')
    .map(d => d.name)
}

/** Compila una extensión a bundle JS (IIFE compatible con flutter_js) */
async function buildExtension(name) {
  const entry = join(EXT_DIR, name, 'index.ts')
  if (!existsSync(entry)) {
    console.warn(`[skip] ${name}: no se encontró index.ts`)
    return null
  }

  const outfile = join(DIST_DIR, `${name}.js`)

  await build({
    entryPoints: [entry],
    bundle: true,
    format: 'iife',        // flutter_js necesita IIFE (no ESM)
    globalName: '__ext',
    outfile,
    platform: 'browser',
    target: 'es2020',
    minify: true,
    define: {
      'process.env.NODE_ENV': '"production"',
    },
    // Expone latest/search/detail/watch como globales para flutter_js
    footer: {
      js: [
        'if(typeof __ext!=="undefined"){',
        '  if(__ext.latest)   globalThis.latest   = __ext.latest;',
        '  if(__ext.search)   globalThis.search   = __ext.search;',
        '  if(__ext.detail)   globalThis.detail   = __ext.detail;',
        '  if(__ext.watch)    globalThis.watch     = __ext.watch;',
        '}',
      ].join(''),
    },
  })

  console.log(`[built] ${name} → dist/${name}.js`)
  return outfile
}

/** Lee metadata del index.ts y actualiza extensions/index.json */
function updateIndex(builtExtensions) {
  /** @type {{ extensions: any[] }} */
  const indexData = JSON.parse(readFileSync(INDEX_PATH, 'utf8'))

  for (const name of builtExtensions) {
    const metaPath = join(EXT_DIR, name, 'index.ts')
    const src = readFileSync(metaPath, 'utf8')
    const metaMatch = src.match(/export const meta\s*=\s*\{([^}]+)\}/)
    if (!metaMatch) continue

    // Extrae campos simples del objeto meta (solo strings/numbers literales)
    const extract = (field) => {
      const m = metaMatch[1].match(new RegExp(`${field}:\\s*['"]([^'"]+)['"]`))
      return m?.[1] ?? ''
    }

    const pkg = extract('package')
    if (!pkg) continue

    const entry = {
      name: extract('name'),
      package: pkg,
      version: extract('version'),
      author: extract('author'),
      type: extract('type'),
      icon: extract('icon'),
      script: `https://raw.githubusercontent.com/Litdemonick/Prism_Hub/main/extensions/dist/${name}.js`,
    }

    const idx = indexData.extensions.findIndex(e => e.package === pkg)
    if (idx >= 0) indexData.extensions[idx] = entry
    else indexData.extensions.push(entry)
  }

  writeFileSync(INDEX_PATH, JSON.stringify(indexData, null, 2))
  console.log(`[index] actualizado (${indexData.extensions.length} extensiones)`)
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

const targets = buildAll
  ? getExtensionDirs()
  : single
  ? [single]
  : getExtensionDirs()

if (targets.length === 0) {
  console.log('No hay extensiones para compilar.')
  process.exit(0)
}

const built = []
for (const name of targets) {
  const out = await buildExtension(name)
  if (out) built.push(name)
}

updateIndex(built)
