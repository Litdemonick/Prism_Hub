# Contribuir a PrismHub

## Flujo de ramas

```
main          ← producción (solo PRs desde develop)
develop       ← integración (base de trabajo)
feature/xxx   ← nueva funcionalidad
fix/xxx       ← corrección de bug
```

**Regla:** nunca hacer commits directos a `main`. Todo pasa por `develop` vía Pull Request.

## Pasos para contribuir

1. `git checkout develop && git pull`
2. `git checkout -b feature/nombre-descriptivo`
3. Escribe tu código + tests si aplica
4. `dart run build_runner build --delete-conflicting-outputs` (si tocaste modelos Isar)
5. `flutter analyze` — sin errores
6. Push y abre PR hacia `develop`

## Convenciones de commits

Seguimos [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: agrega lector de novelas
fix: corrige crash al instalar extensión sin icono
refactor: extrae lógica de paginación a helper
docs: actualiza README con instrucciones iOS
```

## Estructura de módulos

Cada módulo en `lib/modules/` sigue el patrón:

```
modules/mi_modulo/
├── mi_modulo_page.dart       # Widget (solo UI)
├── mi_modulo_controller.dart # GetX controller (lógica)
└── widgets/                  # Widgets privados del módulo
```

## Code style

- `flutter analyze` debe pasar sin warnings
- Dart format: `dart format .`
- Sin comentarios obvios; documenta solo el "por qué", no el "qué"
