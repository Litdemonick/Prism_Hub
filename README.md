# PrismHub

<div align="center">
  <h3>Anime · Manga · Comics · Novelas — via extensiones TypeScript</h3>
  <p>Aplicación multiplataforma construida con Flutter. Motor de extensiones escrito en TypeScript, compilado con esbuild.</p>

  ![Flutter](https://img.shields.io/badge/Flutter-3.44+-02569B?logo=flutter)
  ![Dart](https://img.shields.io/badge/Dart-3.12+-0175C2?logo=dart)
  ![TypeScript](https://img.shields.io/badge/Extensions-TypeScript-3178C6?logo=typescript)
  ![Plataformas](https://img.shields.io/badge/Platforms-Windows%20%7C%20Android%20%7C%20Linux%20%7C%20iOS-green)
  ![License](https://img.shields.io/badge/License-AGPL--3.0-blue)
</div>

---

## ¿Qué es PrismHub?

PrismHub es una aplicación de entretenimiento multiplataforma que consume contenido a través de **extensiones TypeScript**. Soporta anime (video), manga, cómics y novelas ligeras.

Cada extensión es un módulo TypeScript que se compila a un bundle JS con esbuild y se ejecuta en la app a través de `flutter_js`. El tipado estricto garantiza contratos claros entre la app y cada extensión.

## Características

- Reproductor de video integrado (`media_kit`)
- Lector de manga / cómics / novelas
- Sistema de extensiones TypeScript con tipos estrictos
- Compilación con esbuild (bundle IIFE, un archivo por extensión)
- Runtime aislado por extensión (sin colisiones de nombres globales)
- Historial y favoritos persistentes (Isar)
- i18n ES / EN
- Tema claro/oscuro (Material 3)
- Navegación adaptativa: rail en desktop, bottom bar en móvil

## Stack

| Área | Tecnología |
|------|-----------|
| App | Flutter 3.44 + Dart 3.12 |
| Estado / DI | GetX |
| Navegación | go_router (ShellRoute) |
| DB | Isar 3 (code-gen con build_runner) |
| Config / KV | shared_preferences · Hive |
| HTTP | Dio + cookie_jar |
| Extensiones | TypeScript → esbuild → flutter_js |
| Video | media_kit |
| Scraping | html · xpath_selector |
| Desktop | window_manager |
| i18n | flutter_i18n |

## Estructura del proyecto

```
Prism_Hub/
├── lib/
│   ├── core/
│   │   ├── config/        # AppConfig (constantes globales)
│   │   ├── db/            # DatabaseService (Isar)
│   │   ├── router/        # AppRouter + AppRoutes (go_router)
│   │   ├── theme/         # AppTheme (Material 3 light/dark)
│   │   └── utils/         # Logger, AppStorage
│   ├── data/
│   │   ├── models/        # Colecciones Isar (Extension, History, Favorite)
│   │   ├── providers/     # APIs externas (AniList, TMDB…)
│   │   └── services/
│   │       └── extension/ # ExtensionService + ExtensionRuntime
│   ├── modules/           # Un módulo por pantalla
│   │   ├── home/
│   │   ├── search/
│   │   ├── detail/
│   │   ├── player/        # Reproductor anime
│   │   ├── reader/        # Lector manga / comic / novela
│   │   ├── extensions/
│   │   └── settings/
│   └── shared/
│       ├── widgets/       # AppShell, componentes reutilizables
│       └── dialogs/
├── extensions/
│   ├── types/
│   │   └── prism.d.ts     # Tipos TypeScript de la API Prism
│   ├── _template/
│   │   └── index.ts       # Plantilla para nuevas extensiones
│   ├── dist/              # Bundles JS compilados (generado, no commitear)
│   └── index.json         # Registro de extensiones publicadas
├── scripts/
│   ├── build.mjs          # Compila extensiones TS → JS con esbuild
│   └── new-extension.mjs  # Scaffolding de nueva extensión
├── package.json           # TypeScript + esbuild tooling
└── tsconfig.json
```

## API de extensiones

Las extensiones implementan cuatro funciones definidas en `extensions/types/prism.d.ts`:

| Función | Firma | Descripción |
|---------|-------|-------------|
| `latest` | `(page: number) => Promise<PrismItem[]>` | Últimos contenidos |
| `search` | `(keyword, page, filter?) => Promise<PrismItem[]>` | Búsqueda |
| `detail` | `(url: string) => Promise<PrismDetail>` | Info + episodios/capítulos |
| `watch` | `(url: string) => Promise<PrismWatch>` | Streams o páginas |

### Crear una extensión nueva

```bash
npm run new mi-extension          # copia el template
# edita extensions/mi-extension/index.ts
npm run build -- --extension=mi-extension   # compila
```

## Ramas Git

| Rama | Uso |
|------|-----|
| `main` | Producción — solo merges de `develop` vía PR |
| `develop` | Integración activa — base de trabajo diario |
| `feature/*` | Features nuevas → PR a `develop` |
| `fix/*` | Bugfixes → PR a `develop` |

## Instalación / Desarrollo

```bash
# Clonar y cambiar a la rama de desarrollo
git clone https://github.com/Litdemonick/Prism_Hub.git
cd Prism_Hub
git checkout develop

# Flutter
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run -d windows

# Extensiones (TypeScript)
npm install
npm run build:all
```

## Licencia

AGPL-3.0 — ver [LICENSE](LICENSE).
