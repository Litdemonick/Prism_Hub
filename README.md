# PrismHub

<div align="center">
  <h3>Anime · Manga · Comics · Novelas — via extensiones JS</h3>
  <p>Aplicación multiplataforma construida con Flutter. Inspirada en Miru App, diseñada desde cero.</p>

  ![Flutter](https://img.shields.io/badge/Flutter-3.44+-02569B?logo=flutter)
  ![Dart](https://img.shields.io/badge/Dart-3.12+-0175C2?logo=dart)
  ![Plataformas](https://img.shields.io/badge/Platforms-Windows%20%7C%20Android%20%7C%20Linux%20%7C%20iOS-green)
  ![License](https://img.shields.io/badge/License-AGPL--3.0-blue)
</div>

---

## ¿Qué es PrismHub?

PrismHub es una aplicación de entretenimiento multiplataforma que consume contenido a través de **extensiones JavaScript**. Soporta anime (video), manga, cómics y novelas ligeras mediante un motor de extensiones compatible con el formato Miru.

## Características

- Reproductor de video integrado (media_kit)
- Lector de manga/cómics con controles de página
- Lector de novelas
- Sistema de extensiones JS (instalar desde repo remoto o archivo local)
- Historial y favoritos persistentes (Isar)
- Soporte i18n (ES / EN)
- Tema claro/oscuro automático
- Navegación adaptativa (desktop rail / mobile bottom bar)

## Stack

| Área | Librería |
|------|----------|
| Estado / DI | GetX |
| Navegación | go_router |
| DB estructurada | Isar |
| KV / Config | shared_preferences / Hive |
| HTTP | Dio + cookie_jar |
| Motor extensiones | flutter_js |
| Video | media_kit |
| Scraping | html + xpath_selector |
| Ventana desktop | window_manager |
| i18n | flutter_i18n |

## Estructura del proyecto

```
lib/
├── core/
│   ├── config/        # Constantes globales (AppConfig)
│   ├── db/            # Isar (DatabaseService)
│   ├── router/        # go_router (AppRouter, AppRoutes)
│   ├── theme/         # Material3 themes
│   └── utils/         # Logger, AppStorage
├── data/
│   ├── models/        # Isar collections (.dart + .g.dart)
│   ├── providers/     # APIs externas (AniList, TMDB…)
│   └── services/
│       └── extension/ # Motor JS (ExtensionService)
├── modules/           # Feature modules (cada pantalla = carpeta)
│   ├── home/
│   ├── search/
│   ├── detail/
│   ├── player/        # Reproductor anime
│   ├── reader/        # Lector manga/comic/novela
│   ├── extensions/
│   └── settings/
└── shared/
    ├── widgets/       # AppShell, componentes reutilizables
    └── dialogs/
```

## Extensiones

Cada extensión es un archivo `.js` que expone:

| Función | Descripción |
|---------|-------------|
| `latest(page)` | Últimos contenidos |
| `search(keyword, page, filter)` | Búsqueda |
| `detail(url)` | Info detallada (título, episodios/capítulos) |
| `watch(url)` | URLs de reproducción / imágenes del capítulo |

## Ramas Git

| Rama | Uso |
|------|-----|
| `main` | Producción — solo merges de `develop` vía PR |
| `develop` | Rama de integración activa |
| `feature/*` | Features nuevas (se mergean a `develop`) |
| `fix/*` | Bugfixes (se mergean a `develop`) |

## Instalación / Desarrollo

```bash
# Clonar
git clone https://github.com/Litdemonick/Prism_Hub.git
cd Prism_Hub
git checkout develop

# Dependencias
flutter pub get

# Generar código Isar
dart run build_runner build --delete-conflicting-outputs

# Correr (Windows)
flutter run -d windows
```

## Licencia

AGPL-3.0 — ver [LICENSE](LICENSE).
