## PrismHub v1.0.40 — Android TV: el reproductor, blindado

> ⚡ **Trabajo grande de estabilidad y fluidez en el reproductor de
> televisor**: se ataca el cierre inesperado al saltar en el video, la
> desincronización del audio y los tirones.

> ⚠️ **La app sigue en mantenimiento general.** Se la sigue reestructurando
> por dentro, así que es posible que te cruces con fallos o con cosas a
> medio terminar, también en teléfono y en PC. Si encontrás algo roto,
> reportalo desde Ajustes → Reportar.

### 📺 Android TV — reproductor

- **La app ya no debería cerrarse al saltar en el video.** El colchón de
  descarga estaba fijado en un valor pensado para un teléfono con 6-8 GB de
  RAM; en un televisor de 1-2 GB competía con el video y con el sistema, y
  saltar —que vacía y vuelve a llenar ese colchón— era el momento justo del
  cierre. Ahora se ajusta al aparato.
- **Se libera la memoria de las portadas al abrir un video.** Venías de
  recorrer el catálogo con la memoria llena de imágenes; ahora se suelta
  antes de que el reproductor pida la suya.
- **Audio y video sincronizados.** El reloj lo manda el audio y, si el
  televisor no da abasto, se descartan cuadros de imagen en vez de
  entrecortar el sonido. En aparatos modestos se descarta antes, lo que
  además baja la temperatura.
- **Saltar con el mando es un solo salto.** Apretar la flecha varias veces
  seguidas se juntaba en varios saltos reales, y cada uno es un pico de
  memoria; ahora una ráfaga de toques es un único salto al punto final.

### 📺 Android TV — detalles visuales

- **El resplandor de selección ya no lava el texto** de la card en
  Historial, Biblioteca y demás: ahora rodea solo la portada.
- **El panel de info de una card ya no corta el texto**, se ajusta a lo que
  necesita mostrar.

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
| **`PrismHub-setup-windows-v1.0.40.exe`** | **Instalador.** Lo normal: instala y crea el acceso directo |
| `PrismHub-v1.0.40-windows-x64.zip` | Portable: se descomprime y se ejecuta, sin instalar |

### 🐧 Linux

| Archivo | Para |
|---|---|
| `PrismHub-v1.0.40-linux-x64.tar.gz` | Se descomprime y se ejecuta |

> Los archivos que llevan la versión en el nombre (`v1.0.40`) quedan fijos en
> esta publicación. Los de Android que **no** la llevan apuntan siempre a la
> más nueva — son los que conviene usar para un enlace o un código que quede
> guardado.
