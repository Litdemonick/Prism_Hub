# PrismHub Installer

Instalador universal para PrismHub con detección automática de plataforma y
arquitectura, interfaz CLI y soporte multilingüe.

## Comandos

### Linux / macOS
```bash
curl -fsSL https://raw.githubusercontent.com/jephersonRD/prismhub/main/jiru-install/install.sh | bash
```

### Windows (PowerShell)
```powershell
irm https://raw.githubusercontent.com/jephersonRD/prismhub/main/jiru-install/install.ps1 | iex
```

## Dependencias del Sistema

El instalador detecta automáticamente tu distribución e instala las dependencias
necesarias (gtk3, mpv). Si ya están instaladas, las salta.

| Distribución | Comando |
|---|---|
| Arch Linux / derivados | `pacman -S gtk3 mpv` |
| Debian / Ubuntu / derivados | `apt-get install libgtk-3-0 mpv` |
| Fedora / RHEL / derivados | `dnf install gtk3 mpv` |
| openSUSE | `zypper install gtk3 mpv` |

Si el instalador no detecta tu distribución, te mostrará un aviso para que
instales las dependencias manualmente.

### Instalación nativa en Arch Linux (PKGBUILD)

```bash
cd jiru-install
makepkg -si
```

## Assets esperados en GitHub Releases

El instalador busca automáticamente estos assets en la última release:

| Plataforma | Asset |
|-----------|-------|
| Linux x64 | `PrismHub-<tag>-linux-x64.tar.gz` o `PrismHub-<tag>-linux.tar.gz` |
| Linux arm64 | `PrismHub-<tag>-linux-arm64.tar.gz` |
| Windows x64 | `PrismHub-<tag>-windows-x64.zip` o `PrismHub-<tag>-windows.zip` |
| macOS x64 | `PrismHub-<tag>-mac-x64.tar.gz` o `PrismHub-<tag>-mac.tar.gz` |

Los assets son generados automáticamente por el CI al crear un tag `v*`.

## Rutas de instalación

### Linux
```
~/.local/share/prismhub/         ← Archivos de la app (binario, data/, lib/)
~/.local/bin/PrismHub             ← Symlink al ejecutable
~/.local/share/applications/     ← .desktop entry
~/.local/share/prismhub/version  ← Versión actual
~/.local/share/prismhub/logs/    ← Logs del instalador
```

### Windows
```
%LOCALAPPDATA%\PrismHub\          ← Archivos de la app
%APPDATA%\...\Start Menu\...\PrismHub.lnk  ← Acceso directo
%LOCALAPPDATA%\PrismHub\version   ← Versión actual
%LOCALAPPDATA%\PrismHub\logs\     ← Logs del instalador
```

## Funciones

- **Instalar**: descarga el asset correcto según SO/arquitectura, extrae, copia,
  crea symlink (Linux) o acceso directo (Windows)
- **Actualizar**: compara versión local con la última release, descarga e
  instala si hay cambios
- **Desinstalar**: elimina todos los archivos, symlinks y accesos directos
- **Español / English**: menú de idioma al inicio
- **Reintentos**: hasta 3 intentos con backoff exponencial en caso de fallo de red
