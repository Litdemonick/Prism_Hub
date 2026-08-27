## PrismHub v1.0.35 — Android TV: el reproductor ya deja elegir servidor

> ⚠️ **La app sigue en mantenimiento general.** Se la sigue reestructurando
> por dentro, así que es posible que te cruces con fallos o con cosas a
> medio terminar, también en teléfono y en PC. Si encontrás algo roto,
> reportalo desde Ajustes → Reportar.

### 📺 Android TV

- **El reproductor ya deja elegir servidor con el control remoto.** Al
  desplegar la lista (flecha abajo), el mando quedaba "mudo": no dejaba
  moverse entre servidores ni confirmar ninguno con OK — así que un video
  con varios servidores nunca llegaba a reproducirse. Era un problema real
  de foco, no del video en sí.
- **La lista de servidores se despliega hacia abajo**, no empujando el
  título y el progreso hacia arriba como antes.
- **La selección con el mando se nota más.** El resplandor rosado era muy
  sutil sobre portadas oscuras — ahora es más intenso y suma un borde
  nítido, solo en televisor (en PC el hover del mouse queda igual que
  siempre).
- **El logo de arranque ya no sale gigante.** Tenía un tamaño que dependía
  de cada pantalla; ahora es siempre el mismo, sin importar el televisor.
- **Pantalla de arranque nueva**, con un banner fijo en vez de la animación
  anterior.
- **La actualización ya no se sentía "cancelada" la primera vez.** Al volver
  del permiso de instalar, el reintento automático se rendía demasiado
  rápido para navegar esa pantalla con el control remoto — ahora espera lo
  que haga falta.
- **Nada de manga ni novela en Biblioteca ni en Historial**, reforzando lo
  que Inicio y Buscar ya bloqueaban — la regla de Android TV sigue siendo
  "solo video, streaming".

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
| **`PrismHub-setup-windows-v1.0.35.exe`** | **Instalador.** Lo normal: instala y crea el acceso directo |
| `PrismHub-v1.0.35-windows-x64.zip` | Portable: se descomprime y se ejecuta, sin instalar |

### 🐧 Linux

| Archivo | Para |
|---|---|
| `PrismHub-v1.0.35-linux-x64.tar.gz` | Se descomprime y se ejecuta |

> Los archivos que llevan la versión en el nombre (`v1.0.35`) quedan fijos en
> esta publicación. Los de Android que **no** la llevan apuntan siempre a la
> más nueva — son los que conviene usar para un enlace o un código que quede
> guardado.
