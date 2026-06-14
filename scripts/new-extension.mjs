/**
 * Crea una nueva extensión a partir del template.
 * Uso: node scripts/new-extension.mjs mi-extension
 */

import { cpSync, readFileSync, writeFileSync } from 'fs'
import { join, resolve } from 'path'

const ROOT = resolve(import.meta.dirname, '..')
const name = process.argv[2]

if (!name || name.startsWith('_')) {
  console.error('Uso: node scripts/new-extension.mjs <nombre-extension>')
  process.exit(1)
}

const src = join(ROOT, 'extensions', '_template')
const dest = join(ROOT, 'extensions', name)

cpSync(src, dest, { recursive: true })

// Reemplaza el nombre en index.ts
const indexPath = join(dest, 'index.ts')
const content = readFileSync(indexPath, 'utf8')
  .replace('Mi Extensión', name)
  .replace('com.prismhub.mi-extension', `com.prismhub.${name}`)
  .replace('https://example.com', `https://${name}.com`)

writeFileSync(indexPath, content)
console.log(`Extensión "${name}" creada en extensions/${name}/`)
console.log(`Edita extensions/${name}/index.ts y luego: npm run build -- --extension=${name}`)
