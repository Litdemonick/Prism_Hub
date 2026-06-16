<div align="center">

<img width="180" src="./icons/logo.png" alt="PrismHub Logo"/>

# PrismHub

**Aplicación multiplataforma para anime, manga y series**

[![License](https://img.shields.io/github/license/Litdemonick/Prism_Hub?style=for-the-badge)](LICENSE)
[![Stars](https://img.shields.io/github/stars/Litdemonick/Prism_Hub?style=for-the-badge)](https://github.com/Litdemonick/Prism_Hub/stargazers)
[![Issues](https://img.shields.io/github/issues/Litdemonick/Prism_Hub?style=for-the-badge)](https://github.com/Litdemonick/Prism_Hub/issues)
[![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20Android%20%7C%20Linux-informational?style=for-the-badge)](https://github.com/Litdemonick/Prism_Hub/releases)

</div>

---

## ¿Qué es PrismHub?

PrismHub es una aplicación de streaming multiplataforma (Windows, Android, Linux) para ver anime, leer manga y acceder a series y películas. Funciona mediante un sistema de **extensiones JavaScript** que permiten añadir cualquier fuente de contenido sin modificar la app.

### Características

- Soporte de extensiones JavaScript (formato Miru-compatible)
- Multi-servidor con failover automático — si un servidor falla, prueba el siguiente sin salir del episodio
- Historial, favoritos y seguimiento de progreso
- Integración con AniList
- DLNA / Cast a TV
- Subtítulos externos
- Proxy HLS y cookie jar persistente

---

## Instalación

### Windows

```powershell
irm https://raw.githubusercontent.com/Litdemonick/Prism_Hub/main/install/install.ps1 | iex
```

O descarga el instalador `.exe` directamente desde [Releases](https://github.com/Litdemonick/Prism_Hub/releases/latest).

### Linux

```bash
curl -fsSL https://raw.githubusercontent.com/Litdemonick/Prism_Hub/main/install/install.sh | bash
```

**Arch Linux (PKGBUILD):**
```bash
cd install
makepkg -si
```

### Android

Descarga el `.apk` desde [Releases](https://github.com/Litdemonick/Prism_Hub/releases/latest).

---

## Extensiones

PrismHub usa un sistema de extensiones para acceder al contenido. Hay dos repositorios de extensiones:

### Repositorio oficial (prism+)

Extensiones propias de PrismHub, enfocadas en contenido en español:

```
https://raw.githubusercontent.com/Litdemonick/prism-plus/main/index.json
```

Incluye: **TioAnime**, **AnimeFLV**, **MonosChinos** y más.

> Este repositorio es el que viene configurado por defecto en la app.

### Repositorio de la comunidad

Más de 100 extensiones para contenido en múltiples idiomas (anime, manga, novelas, películas):

```
https://raw.githubusercontent.com/Litdemonick/Prism_Hub/main/index.json
```

**Cómo añadir un repositorio en la app:**

1. Abre PrismHub
2. Ve a **Ajustes → Extensiones → URL del repositorio**
3. Pega la URL y guarda
4. En la sección **Repositorio de extensiones**, pulsa **Recargar**

---

## Desarrollo de extensiones

Las extensiones son archivos JavaScript con el siguiente formato:

```javascript
// ==MiruExtension==
// @name         MiExtension
// @version      1.0.0
// @author       TuNombre
// @lang         es
// @license      MIT
// @package      com.tudominio.miextension
// @type         bangumi
// @webSite      https://sitio.com
// ==/MiruExtension==

export default class extends Extension {
  async latest(page) { /* retorna [{title, url, cover}] */ }
  async search(kw, page) { /* retorna [{title, url, cover}] */ }
  async detail(url) { /* retorna {title, cover, desc, episodes:[...]} */ }
  async watch(url) { /* retorna {type:'hls'|'mp4', url, headers} */ }
}
```

### API disponible en extensiones

| Método | Descripción |
|--------|-------------|
| `this.request('/ruta')` | HTTP al sitio base (`webSite` + ruta) — incluye UA y cookies |
| `fetch(url, options)` | HTTP a cualquier URL externa |
| `this.querySelector(html, selector)` | Selector CSS sobre HTML |
| `this.queryXPath(html, xpath)` | XPath sobre HTML |
| `CryptoJS` | Librería CryptoJS (pre-cargada, disponible siempre) |

### Tipos de extensión

| Tipo | `@type` | `watch()` retorna |
|------|---------|-------------------|
| Anime / Series | `bangumi` | `{ type: 'hls'\|'mp4', url, headers }` |
| Manga / Cómic | `manga` | `{ urls: ['img1', 'img2', ...], headers }` |
| Novela | `fikushon` | `{ title, content: ['párrafo...'] }` |

---

## Estructura del repositorio

```
Prism_Hub/
├── lib/                    ← Código fuente Flutter
│   ├── controllers/        ← Lógica de negocio (GetX)
│   ├── data/services/      ← Runtime JS, base de datos
│   ├── models/             ← Modelos Isar / JSON
│   ├── utils/              ← Utilidades, storage, request
│   └── views/              ← UI (pages, widgets)
├── extensions/             ← Extensiones de la comunidad (100+)
├── assets/
│   ├── i18n/               ← Traducciones (es.json, en.json, zh.json…)
│   ├── js/                 ← CryptoJS, jsencrypt, md5 (runtime)
│   └── icon/               ← Iconos de la app
├── install/                ← Scripts de instalación (Windows/Linux/Arch)
├── .github/workflows/      ← CI/CD (release, build, pages)
├── index.json              ← Catálogo de extensiones de la comunidad
└── pubspec.yaml            ← Dependencias Flutter
```

---

## Compilar desde código fuente

```bash
# Requiere Flutter 3.22+
flutter pub get
flutter build windows --release   # Windows
flutter build apk --release       # Android
flutter build linux --release     # Linux
```

---

## Licencia

[AGPL-3.0](LICENSE)

---

<div align="center">

**PrismHub** — Tu portal de entretenimiento en español

[Releases](https://github.com/Litdemonick/Prism_Hub/releases) · [Issues](https://github.com/Litdemonick/Prism_Hub/issues) · [prism+ extensions](https://github.com/Litdemonick/prism-plus)

</div>
