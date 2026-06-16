# PrismHub Installer

Instalador universal para PrismHub con detección automática de plataforma y arquitectura.

## Instalación rápida

### Linux / macOS
```bash
curl -fsSL https://raw.githubusercontent.com/Litdemonick/Prism_Hub/main/install/install.sh | bash
```

### Windows (PowerShell)
```powershell
irm https://raw.githubusercontent.com/Litdemonick/Prism_Hub/main/install/install.ps1 | iex
```

### Arch Linux (PKGBUILD)
```bash
cd install
makepkg -si
```

## Dependencias (Linux)

| Distribución | Comando |
|---|---|
| Arch Linux / derivados | `pacman -S gtk3 mpv` |
| Debian / Ubuntu | `apt-get install libgtk-3-0 mpv` |
| Fedora / RHEL | `dnf install gtk3 mpv` |
| openSUSE | `zypper install gtk3 mpv` |

## Assets en GitHub Releases

| Plataforma | Asset |
|---|---|
| Linux x64 | `PrismHub-<tag>-linux-x64.tar.gz` |
| Linux arm64 | `PrismHub-<tag>-linux-arm64.tar.gz` |
| Windows x64 | `PrismHub-<tag>-windows-x64.zip` |

