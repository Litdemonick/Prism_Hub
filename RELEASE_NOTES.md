## PrismHub v1.0.38 — Android TV: el reproductor, al día

> 📺 **El reproductor de TV se pone a la altura de PC**, con episodios,
> volumen, velocidad de red y un aviso claro de pausa. Y se corrige un bug
> real: el propio salvapantallas del televisor podía tirar la app entera.

> ⚠️ **La app sigue en mantenimiento general.** Se la sigue reestructurando
> por dentro, así que es posible que te cruces con fallos o con cosas a
> medio terminar, también en teléfono y en PC. Si encontrás algo roto,
> reportalo desde Ajustes → Reportar.

### 📺 Android TV

- **Zonas (Películas/Series/Anime) con la misma grilla que PC** — cards
  intercaladas de todas las extensiones juntas, y el mismo panel de info
  (título, fecha, de qué extensión viene) que en PC aparece al pasar el
  mouse, ahora con el foco del mando.
- **El reproductor ya deja elegir episodio con el control remoto** —
  bajando con ▼ aparece la lista, igual que ya tenía Servidores.
- **Aviso de pausa**: un ícono grande se ve al pausar, y se desvanece solo
  al retomar — antes no había ninguna señal de que el video estaba en
  pausa y no colgado.
- **Avisos al avanzar/retroceder y al subir volumen** — un cartel breve
  confirma cuánto salta o a cuánto quedó el volumen.
- **Velocidad de red en pantalla**, arriba a la derecha, mientras se mira
  algo.
- **La app ya no se cerraba al volver del salvapantallas del propio
  televisor** — ahora la pantalla se mantiene encendida mientras el video
  reproduce de verdad, y se libera en pausa.
- **La actualización ya no pedía descargar dos veces** — algunas cajas de
  TV no tenían la pantalla de permisos que se probaba primero; ahora se
  prueban tres antes de rendirse, y si el archivo ya está completo en
  disco, no se vuelve a bajar.

---

## ⬇️ Cuál descargar

### 📺 Android TV, Fire TV y cajas Android

| Archivo | Para |
|---|---|
| **`PrismHub-androidtv-universal.apk`** | **Cualquier televisor.** Si no sabés cuál, es este |
| `PrismHub-androidtv-arm64-v8a.apk` | Televisores y cajas de 64 bits |
| `PrismHub-androidtv-armeabi-v7a.apk` | Aparatos de 32 bits (varios sticks económicos, como los onn) |
| `PrismHub-androidtv-x86_64.apk` | Emuladores y algunas cajas con procesador Intel |

> ⚠️ **Si el televisor dice «Esta app no es compatible con la TV», bajá el
> universal.** Android da ese mismo mensaje cuando el archivo no coincide con
> el procesador del aparato, así que parece un problema de la app cuando en
> realidad es el archivo equivocado. El universal trae las tres
> arquitecturas adentro y no falla.

> 💡 **Instalar en el televisor sin cables.** Con la app **Downloader** (la de
> Fire TV / Android TV), pegá este enlace y listo — apunta siempre a la última
> versión, así que sirve para siempre:
>
> ```
> https://github.com/Litdemonick/Prism_Hub/releases/latest/download/PrismHub-androidtv-universal.apk
> ```

### 📱 Android (teléfono y tablet)

| Archivo | Para |
|---|---|
| **`PrismHub-android-universal.apk`** | **Cualquier teléfono o tablet.** Si no sabés cuál, es este |
| `PrismHub-android-arm64-v8a.apk` | La mayoría de los teléfonos actuales |
| `PrismHub-android-armeabi-v7a.apk` | Teléfonos viejos, de 32 bits |
| `PrismHub-android-x86_64.apk` | Emuladores |

> Los de teléfono y los de televisor son **el mismo archivo**, con dos nombres:
> un solo APK sirve para todo Android y la app reconoce sola dónde está
> corriendo. Están separados solo para que se vea de un vistazo cuál bajar.

### 🪟 Windows

| Archivo | Para |
|---|---|
| **`PrismHub-setup-windows-v1.0.38.exe`** | **Instalador.** Lo normal: instala y crea el acceso directo |
| `PrismHub-v1.0.38-windows-x64.zip` | Portable: se descomprime y se ejecuta, sin instalar |

### 🐧 Linux

| Archivo | Para |
|---|---|
| `PrismHub-v1.0.38-linux-x64.tar.gz` | Se descomprime y se ejecuta |

> Los archivos que llevan la versión en el nombre (`v1.0.38`) quedan fijos en
> esta publicación. Los de Android que **no** la llevan apuntan siempre a la
> más nueva — son los que conviene usar para un enlace o un código que quede
> guardado.
