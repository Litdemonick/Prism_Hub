# Contribuir a PrismHub

## Flujo de ramas

```
main          ← producción (solo PRs desde develop)
develop       ← integración (base de trabajo)
feature/xxx   ← nueva funcionalidad → PR a develop
fix/xxx       ← corrección de bug   → PR a develop
```

**Regla:** nunca hacer commits directos a `main`. Todo pasa por `develop` vía Pull Request.

---

## Desarrollo Flutter (app)

### Requisitos

- Flutter 3.44+ (`flutter --version`)
- Dart 3.12+

### Setup

```bash
git checkout develop
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run -d windows
```

### Pasos para contribuir

1. `git checkout develop && git pull`
2. `git checkout -b feature/nombre-descriptivo`
3. Escribe tu código
4. `dart run build_runner build --delete-conflicting-outputs` (si tocaste modelos Isar)
5. `flutter analyze` → sin errores
6. `dart format .`
7. Push → PR a `develop`

### Patrón de módulos

Cada módulo en `lib/modules/` sigue:

```
modules/mi_modulo/
├── mi_modulo_page.dart         # Solo UI (StatelessWidget o GetView)
├── mi_modulo_controller.dart   # Lógica de negocio (GetxController)
└── widgets/                    # Widgets privados del módulo
```

---

## Desarrollo de extensiones (TypeScript)

### Requisitos

- Node.js 20+
- `npm install`

### Crear una extensión nueva

```bash
npm run new mi-extension
```

Esto copia el template a `extensions/mi-extension/index.ts`.

### Estructura de una extensión

```typescript
// extensions/mi-extension/index.ts

import type { PrismItem, PrismDetail, PrismWatch } from '../types/prism'

export const meta = {
  name: 'Mi Extensión',
  package: 'com.prismhub.mi-extension',
  version: '1.0.0',
  author: 'tu-usuario',
  type: 'anime' as const,
  icon: 'https://...',
  baseUrl: 'https://...',
}

export async function latest(page: number): Promise<PrismItem[]> { ... }
export async function search(keyword: string, page: number): Promise<PrismItem[]> { ... }
export async function detail(url: string): Promise<PrismDetail> { ... }
export async function watch(url: string): Promise<PrismWatch> { ... }
```

### Compilar

```bash
npm run build -- --extension=mi-extension   # una sola
npm run build:all                            # todas
```

El bundle compilado queda en `extensions/dist/mi-extension.js`.

> **Nota:** La carpeta `extensions/dist/` es lo que la app descarga y ejecuta. Commítala cuando la extensión esté lista para publicar.

### Verificar tipos

```bash
npm run typecheck    # TypeScript sin compilar
npm run lint         # ESLint con reglas TS estrictas
```

---

## Convenciones de commits

Seguimos [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: agrega lector de novelas
fix: corrige crash al instalar extensión sin icono
refactor: extrae lógica de paginación
docs: actualiza guía de extensiones TypeScript
chore: actualiza esbuild a 0.25
```

## Code style

- Flutter: `flutter analyze` sin warnings · `dart format .`
- TypeScript: `npm run typecheck` · `npm run lint`
- Sin comentarios obvios; documenta solo el "por qué"
