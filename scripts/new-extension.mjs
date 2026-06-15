/**
 * Crea una nueva extensión a partir del template.
 * Uso: node scripts/new-extension.mjs nombre-extension
 */

import { cpSync, readFileSync, writeFileSync } from 'fs'
import { join, resolve } from 'path'

const ROOT = resolve(import.meta.dirname, '..')
const name = process.argv[2]

if (!name || name.startsWith('_')) {
  console.error('Uso: node scripts/new-extension.mjs <nombre-extension>')
  process.exit(1)
}

const displayName = name
  .split('-')
  .map((w) => w.charAt(0).toUpperCase() + w.slice(1))
  .join('')

const src = join(ROOT, 'extensions', '_template')
const dest = join(ROOT, 'extensions', name)

cpSync(src, dest, { recursive: true })

const indexPath = join(dest, 'index.ts')
const content = readFileSync(indexPath, 'utf8')
  .replace('PrismPlusExtension', displayName)
  .replace('io.prismhub.my-extension', `io.prismhub.${name}`)
  .replace('Extension description', `${displayName} extension for PrismHub`)
  .replace('https://target-site.com', `https://${name}.com`)

writeFileSync(indexPath, content)
console.log(`✅ Extensión "${displayName}" creada en extensions/${name}/`)
console.log(`📝 Edita extensions/${name}/index.ts`)
console.log(`🔨 Compila con: npm run build -- --extension=${name}`)
