#!/usr/bin/env bash
# =============================================================================
#  PrismHub — Sincronizar extensiones de la comunidad desde miru-repo
#  Descarga todas las extensiones de miru-repo.0n0.dev y genera el index.json
#  apuntando al repo de PrismHub en GitHub.
# =============================================================================
set -e

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
EXT_DIR="$REPO_DIR/extensions"
SOURCE_BASE="https://miru-repo.0n0.dev"
RAW_BASE="https://raw.githubusercontent.com/Litdemonick/Prism_Hub/main"

echo "📥 Descargando index.json de miru-repo..."
curl -s "$SOURCE_BASE/index.json" -o /tmp/miru_index.json
TOTAL=$(python3 -c "import json; data=json.load(open('/tmp/miru_index.json')); print(len(data))")
echo "📦 Total de extensiones: $TOTAL"

echo ""
echo "📥 Descargando archivos .js..."
mkdir -p "$EXT_DIR"

python3 - <<'PYEOF'
import json, urllib.request, os

SOURCE_BASE = "https://miru-repo.0n0.dev"
EXT_DIR_ENV = os.environ.get("EXT_DIR", "extensions")

with open('/tmp/miru_index.json') as f:
    extensions = json.load(f)

ok = 0
fail = 0
for ext in extensions:
    js_filename = ext.get('url', '')
    if not js_filename or not js_filename.endswith('.js'):
        continue
    url = f"{SOURCE_BASE}/{js_filename}"
    dest = os.path.join(EXT_DIR_ENV, js_filename)
    try:
        urllib.request.urlretrieve(url, dest)
        ok += 1
        print(f"  ✅ {js_filename}")
    except Exception as e:
        fail += 1
        print(f"  ❌ {js_filename}: {e}")

print(f"\n✅ Descargados: {ok}  ❌ Fallidos: {fail}")
PYEOF

echo ""
echo "📝 Generando index.json apuntando a PrismHub..."

python3 - <<PYEOF
import json, os

RAW_BASE = "https://raw.githubusercontent.com/Litdemonick/Prism_Hub/main"
REPO_DIR = os.path.dirname(os.path.dirname(os.path.abspath("$0")))

with open('/tmp/miru_index.json') as f:
    extensions = json.load(f)

new_index = []
for ext in extensions:
    js_filename = ext.get('url', '')
    if not js_filename.endswith('.js'):
        continue
    new_ext = dict(ext)
    new_ext['url'] = f"{RAW_BASE}/extensions/{js_filename}"
    new_index.append(new_ext)

with open(os.path.join(REPO_DIR, 'index.json'), 'w', encoding='utf-8') as f:
    json.dump(new_index, f, ensure_ascii=False, indent=4)

print(f"✅ index.json generado con {len(new_index)} extensiones")
PYEOF

echo ""
echo "📤 Haciendo commit..."
cd "$REPO_DIR"
COUNT=$(find extensions/ -name "*.js" | wc -l)
git add extensions/ index.json
git commit -m "feat: sync $COUNT community extensions from miru-repo"
git push origin main

echo ""
echo "🎉 Extensiones sincronizadas en PrismHub."
echo "   URL del repo: $RAW_BASE/index.json"
