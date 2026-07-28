#!/bin/bash

# Script para actualizar la descripción de la release v1.0.2 en GitHub

TOKEN="${GH_TOKEN}"
REPO="Litdemonick/Prism_Hub"
TAG="v1.0.2"

BODY=$(cat <<'EOF'
## PrismHub — anime, manga y series, sin límites

App multiplataforma (Windows · Linux · Android) para ver anime, leer manga y acceder a series/películas mediante un sistema de **extensiones JavaScript**. Cada fuente de contenido es un script que se instala o actualiza por separado, sin depender de una actualización de la app.

### 📦 Assets disponibles

| Archivo | Plataforma | Descripción |
|---------|-----------|------------|
| `PrismHub-setup-v1.0.2.exe` | Windows x64 | Instalador (recomendado) |
| `PrismHub-v1.0.2-windows-x64.zip` | Windows x64 | Versión portable (sin instalador) |
| `PrismHub-v1.0.2-linux-x64.tar.gz` | Linux x64 | Binario precompilado |
| `PrismHub-v1.0.2-arm64-v8a.apk` | Android | ARM64 (teléfonos modernos — **recomendado**) |
| `PrismHub-v1.0.2-armeabi-v7a.apk` | Android | ARM32 (teléfonos antiguos) |
| `PrismHub-v1.0.2-x86_64.apk` | Android | x86_64 (emuladores / tabletas x86) |

### Qué incluye
- **Reproductor con failover automático**: si un servidor falla, cambia solo al siguiente sin cortar la reproducción.
- **Lector de manga** con modo paginado y modo cascada (scroll vertical tipo webtoon).
- **Historial y favoritos** unificados, con progreso por episodio/capítulo guardado localmente.
- **Auto-actualización en Windows y Linux**: la app se avisa sola de nuevas versiones y se actualiza desde Ajustes, sin volver a descargar el instalador a mano.
- Repositorio oficial de extensiones **prism+** preinstalado (en crecimiento).

### Cambios en v1.0.2
- ✅ **Fix Linux**: Corecciones críticas para mejorar la estabilidad en Linux.

Proyecto **open source bajo AGPL-3.0**. Sigue en beta — reportá bugs en [Issues](https://github.com/Litdemonick/Prism_Hub/issues).
EOF
)

# Escapar comillas en el JSON
BODY_JSON=$(echo "$BODY" | jq -Rs .)

curl -X PATCH \
  -H "Authorization: token $TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  https://api.github.com/repos/$REPO/releases/tags/$TAG \
  -d "{\"body\": $BODY_JSON}" \
  -v
