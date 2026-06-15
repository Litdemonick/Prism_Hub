# PrismHub

<div align="center">
  <picture>
    <img src="https://raw.githubusercontent.com/Litdemonick/Prism_Hub/develop/assets/logo_prismhub.png" width="360" alt="PrismHub" />
  </picture>

  <br /><br />

  <h3>Anime · Manga · Películas · Series · y más — impulsado por Prism+</h3>
  <p>App multiplataforma en Flutter. Motor de extensiones universal: <strong>Prism+</strong>.</p>

  <br />

  ![Flutter](https://img.shields.io/badge/Flutter-3.44+-02569B?logo=flutter)
  ![Dart](https://img.shields.io/badge/Dart-3.12+-0175C2?logo=dart)
  ![Prism+](https://img.shields.io/badge/Motor-Prism+-6D28D9?logo=typescript)
  ![Plataformas](https://img.shields.io/badge/Platforms-Windows%20%7C%20Android%20%7C%20Linux%20%7C%20iOS-22C55E)
  ![License](https://img.shields.io/badge/License-AGPL--3.0-3B82F6)
</div>

---

## 🧩 ¿Qué es PrismHub?

PrismHub es una aplicación de entretenimiento multiplataforma que consume contenido a través de **extensiones TypeScript**. Su motor es **[Prism+](https://github.com/Litdemonick/prism-plus)** — el núcleo universal de extensiones que PrismHub usa como fuente oficial.

Cada extensión se ejecuta en un runtime QuickJS aislado dentro de la app. PrismHub se sincroniza automáticamente con el catálogo de Prism+ sin configuración extra.

---

## ⚡ Motor integrado: Prism+

El repositorio de **Prism+** está integrado como motor oficial de PrismHub. Esto significa:

- ✅ Las extensiones de Prism+ se instalan automáticamente en el primer arranque — sin configuración manual
- ✅ Cualquier extensión nueva o actualización en Prism+ se refleja automáticamente en PrismHub
- ✅ El contrato de tipos (`extensions/types/prism.d.ts`) es idéntico al SDK de Prism+
- ✅ Prism+ es la única fuente de extensiones — no se requiere ninguna configuración adicional

---

## ✨ Características

- 🎬 Reproductor de video con soporte multi-calidad y subtítulos
- 📖 Lector de manga / cómics / novelas con scroll continuo
- 🔌 Motor Prism+ integrado — extensiones auto-instaladas desde el primer arranque
- 🏃 Runtime JS aislado por extensión (QuickJS vía `flutter_js`)
- 📱 Diseño completamente responsivo (móvil / tablet / escritorio)
- 💾 Historial y favoritos persistentes (Isar)
- 🌐 i18n ES / EN
- 🎨 Tema claro/oscuro (Material 3)
- 🔄 Sincronización automática con el catálogo de Prism+

---

## 📱 Diseño responsivo

PrismHub adapta toda su interfaz según el tamaño de pantalla del dispositivo:

| Breakpoint | Rango | Navegación | Grid | Comportamiento |
|---|---|---|---|---|
| **Mobile** | < 600 px | Bottom bar | 2 columnas | Smartphones portrait/landscape |
| **Tablet** | 600–1199 px | Bottom bar | 3 columnas | Tablets, laptops compactas |
| **Desktop** | ≥ 1200 px | Navigation Rail | 4 columnas | Escritorio con controles de ventana nativos |

- **Padding horizontal**: proporcional al viewport en móvil/tablet; fijo a la izquierda en desktop
- **Cards de contenido**: ancho adaptativo (110 / 130 / 150 px según dispositivo)
- **Contenido centrado**: ancho máximo de 1280 px en desktop para pantallas muy anchas
- **Ventana en desktop**: tamaño inicial 1200×780 px, mínimo 1000×680 px para que el rail siempre sea visible

---

## 🛠️ Stack

| Área | Tecnología |
|------|-----------|
| App | Flutter 3.44 + Dart 3.12 |
| Estado / DI | GetX |
| Navegación | go_router (ShellRoute) |
| DB | Isar 3 |
| Config / KV | shared_preferences · Hive |
| HTTP | Dio + cookie_jar |
| Motor de extensiones | **Prism+ SDK** → esbuild → flutter_js (QuickJS) |
| Video | media_kit |
| Desktop | window_manager |
| i18n | flutter_i18n |

---

## 📁 Estructura del proyecto

```
Prism_Hub/
├── lib/
│   ├── core/
│   │   ├── config/        # AppConfig — URL de Prism+, constantes globales
│   │   ├── db/            # DatabaseService (Isar)
│   │   ├── router/        # AppRouter + rutas (go_router)
│   │   ├── theme/         # AppTheme (Material 3)
│   │   └── utils/         # Logger, AppStorage, Responsive
│   ├── data/
│   │   ├── models/        # MediaItem, WatchData, ExtensionModel, …
│   │   ├── providers/     # ExtensionRepoProvider
│   │   └── services/
│   │       └── extension/ # ExtensionService + Loader + Installer
│   ├── modules/
│   │   ├── home/
│   │   ├── search/
│   │   ├── detail/
│   │   ├── player/        # Reproductor (video)
│   │   ├── reader/        # Lector (manga, cómic, novela)
│   │   ├── extensions/    # Gestión de extensiones y repos
│   │   └── settings/
│   └── shared/
│       ├── widgets/       # AppShell, ContentCard
│       └── dialogs/
├── extensions/
│   ├── types/
│   │   └── prism.d.ts     # Tipos Prism+ SDK (sincronizados)
│   ├── _template/
│   │   └── index.ts       # Plantilla para nuevas extensiones
│   └── index.json         # Registro local
├── scripts/
│   ├── build.mjs          # Compila TS → JS (esbuild)
│   └── new-extension.mjs  # Scaffolding de extensión
├── package.json
└── tsconfig.json
```

---

## 🔌 API de extensiones (contrato Prism+)

Cada extensión exporta exactamente cuatro funciones asíncronas:

| Función | Firma | Descripción |
|---------|-------|-------------|
| `latest` | `(page) => Promise<PrismItem[] \| PrismPage>` | Últimos contenidos |
| `search` | `(keyword, page, filter?) => Promise<PrismItem[] \| PrismPage>` | Búsqueda |
| `detail` | `(url) => Promise<PrismDetail>` | Metadata + episodios/capítulos |
| `watch` | `(url) => Promise<PrismWatch>` | Streams de video o páginas |

### Tipos de media soportados

`anime` · `manga` · `novel` · `movie` · `series` · `documentary` · `live` · `video` · `music` · `podcast` · `other`

### Crear una extensión local

```bash
# Copiar la plantilla
cp -r extensions/_template extensions/mi-extension

# Editar extensions/mi-extension/index.ts
# Completar las 4 funciones con la lógica del sitio

# Compilar
npm run build -- --extension=mi-extension
```

> Para publicar extensiones al catálogo oficial, contribuye directamente en [Prism+](https://github.com/Litdemonick/prism-plus).

---

## 🚀 Instalación y desarrollo

### Requisitos

- Flutter 3.44+
- Node.js 18+ (para compilar extensiones TypeScript)

### Pasos

```bash
# 1. Clonar y cambiar a develop
git clone https://github.com/Litdemonick/Prism_Hub.git
cd Prism_Hub
git checkout develop

# 2. Dependencias Flutter
flutter pub get
dart run build_runner build --delete-conflicting-outputs

# 3. Correr la app
flutter run -d windows    # Desktop
flutter run -d android    # Android

# 4. Dependencias de extensiones
npm install
npm run build:all
```

---

## 🌿 Ramas Git

| Rama | Uso |
|------|-----|
| `main` | Producción — solo merges de `develop` vía PR |
| `develop` | Integración activa — base de trabajo diario |
| `feature/*` | Features nuevas → PR a `develop` |
| `fix/*` | Bugfixes → PR a `develop` |

---

## 🤝 Contribuir

1. Haz fork y crea tu rama desde `develop`
2. Para la app: mantén la arquitectura GetX + go_router existente
3. Para nuevas extensiones: contribuye directamente al catálogo en [Prism+](https://github.com/Litdemonick/prism-plus)
4. Abre un PR hacia `develop`

---

## 📄 Licencia

AGPL-3.0 — ver [LICENSE](LICENSE).
