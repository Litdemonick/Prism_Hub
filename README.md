# PrismHub

<div align="center">
  <h3>Anime · Manga · Películas · Series · y más — vía extensiones Prism+</h3>
  <p>App multiplataforma en Flutter. Motor de extensiones universal impulsado por <strong>Prism+</strong>.</p>

  ![Flutter](https://img.shields.io/badge/Flutter-3.44+-02569B?logo=flutter)
  ![Dart](https://img.shields.io/badge/Dart-3.12+-0175C2?logo=dart)
  ![Prism+](https://img.shields.io/badge/Prism+-SDK-6D28D9?logo=typescript)
  ![Plataformas](https://img.shields.io/badge/Platforms-Windows%20%7C%20Android%20%7C%20Linux%20%7C%20iOS-22C55E)
  ![License](https://img.shields.io/badge/License-AGPL--3.0-3B82F6)
</div>

---

## 🧩 ¿Qué es PrismHub?

PrismHub es una aplicación de entretenimiento multiplataforma que consume contenido a través de **extensiones TypeScript**. Soporta anime, manga, películas, series, podcasts, TV en vivo y cualquier tipo de media gracias a su integración con **Prism+**, el núcleo universal de extensiones.

El motor de extensiones ejecuta cada bundle JS en un runtime QuickJS aislado dentro de la app, sin colisiones entre extensiones ni acceso al sistema de archivos del usuario.

---

## ⚡ Integración con Prism+

PrismHub usa [Prism+](https://github.com/Litdemonick/prism-plus) como su **núcleo de extensiones**. Esto significa:

- Las extensiones escritas para Prism+ funcionan directamente en PrismHub sin modificaciones
- Los tipos en `extensions/types/prism.d.ts` son idénticos al SDK de Prism+
- El formato del `index.json` de repositorio es compatible con ambos proyectos
- PrismHub puede apuntar al repositorio de Prism+ para instalar sus 16+ extensiones

### Agregar el repositorio de Prism+

En la pantalla de **Extensiones** → **Repositorios**, agrega:

```
https://raw.githubusercontent.com/Litdemonick/prism-plus/main/dist/index.json
```

Esto habilita la instalación de todas las extensiones incluidas en Prism+.

---

## ✨ Características

- 🎬 Reproductor de video integrado (`media_kit`) con soporte multi-calidad
- 📖 Lector de manga / cómics / novelas con scroll continuo
- 🔌 Sistema de extensiones Prism+ — instala, actualiza y desinstala sin reiniciar
- 🏃 Runtime JS aislado por extensión (QuickJS vía `flutter_js`)
- 💾 Historial y favoritos persistentes (Isar)
- 🌐 i18n ES / EN
- 🎨 Tema claro/oscuro (Material 3)
- 🖥️ Navegación adaptativa: rail en desktop, bottom bar en móvil
- 🔄 Compatible con repositorios de extensiones externos

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
| Extensiones | Prism+ SDK → esbuild → flutter_js (QuickJS) |
| Video | media_kit |
| Desktop | window_manager |
| i18n | flutter_i18n |

---

## 📁 Estructura del proyecto

```
Prism_Hub/
├── lib/
│   ├── core/
│   │   ├── config/        # AppConfig (constantes globales)
│   │   ├── db/            # DatabaseService (Isar)
│   │   ├── router/        # AppRouter + rutas (go_router)
│   │   ├── theme/         # AppTheme (Material 3)
│   │   └── utils/         # Logger, AppStorage, Responsive
│   ├── data/
│   │   ├── models/        # MediaItem, WatchData, ExtensionModel, …
│   │   ├── providers/     # ExtensionRepoProvider
│   │   └── services/
│   │       └── extension/ # ExtensionService + Loader + Installer
│   ├── modules/           # Una carpeta por pantalla
│   │   ├── home/
│   │   ├── search/
│   │   ├── detail/
│   │   ├── player/        # Reproductor (anime, películas, series)
│   │   ├── reader/        # Lector (manga, cómic, novela)
│   │   ├── extensions/    # Gestión de extensiones + repos
│   │   └── settings/
│   └── shared/
│       ├── widgets/       # AppShell, ContentCard
│       └── dialogs/
├── extensions/
│   ├── types/
│   │   └── prism.d.ts     # Tipos Prism+ SDK (sincronizados)
│   ├── _template/
│   │   └── index.ts       # Plantilla para nuevas extensiones
│   └── index.json         # Registro local de extensiones
├── scripts/
│   ├── build.mjs          # Compila extensiones TS → JS (esbuild)
│   └── new-extension.mjs  # Scaffolding de nueva extensión
├── package.json
└── tsconfig.json
```

---

## 🔌 API de extensiones (contrato Prism+)

Cada extensión exporta exactamente cuatro funciones asíncronas:

| Función | Firma | Descripción |
|---------|-------|-------------|
| `latest` | `(page) => Promise<PrismItem[] \| PrismPage<PrismItem>>` | Últimos contenidos |
| `search` | `(keyword, page, filter?) => Promise<PrismItem[] \| PrismPage<PrismItem>>` | Búsqueda |
| `detail` | `(url) => Promise<PrismDetail>` | Metadata + episodios/capítulos |
| `watch` | `(url) => Promise<PrismWatch>` | Streams de video o páginas |

### Tipos de media soportados

`anime` · `manga` · `novel` · `movie` · `series` · `documentary` · `live` · `video` · `music` · `podcast` · `other`

### Crear una extensión nueva

```bash
# Copiar la plantilla
cp -r extensions/_template extensions/mi-extension

# Editar extensions/mi-extension/index.ts
# Completar las 4 funciones con la lógica del sitio

# Compilar
npm run build -- --extension=mi-extension
```

La plantilla en `extensions/_template/index.ts` incluye los tipos correctos de Prism+ y stubs listos para rellenar.

---

## 🚀 Instalación y desarrollo

### Requisitos previos

- Flutter 3.44+
- Node.js 18+ (para compilar extensiones TypeScript)

### Pasos

```bash
# 1. Clonar y cambiar a la rama de desarrollo
git clone https://github.com/Litdemonick/Prism_Hub.git
cd Prism_Hub
git checkout develop

# 2. Dependencias Flutter
flutter pub get
dart run build_runner build --delete-conflicting-outputs

# 3. Correr la app
flutter run -d windows    # Desktop
flutter run -d android    # Android

# 4. Dependencias de extensiones (TypeScript)
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

1. Haz fork del repo y crea tu rama desde `develop`
2. Para extensiones: sigue el contrato Prism+ (`extensions/_template/index.ts`)
3. Para la app: mantén la arquitectura GetX + go_router existente
4. Abre un PR hacia `develop` — describe qué hace y por qué

Ver también: [Prism+](https://github.com/Litdemonick/prism-plus) si quieres contribuir extensiones al catálogo compartido.

---

## 📄 Licencia

AGPL-3.0 — ver [LICENSE](LICENSE).
