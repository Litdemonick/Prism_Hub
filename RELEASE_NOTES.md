## PrismHub v1.0.41 — Android TV: correcciones del reproductor

> 🔧 **Corrige tres problemas introducidos o detectados en la 1.0.40**: el
> video que se veía cuadro por cuadro, los controles que no respondían, y
> el reproductor que quedaba esperando sin salida.

> ⚠️ **La app sigue en mantenimiento general.** Se la sigue reestructurando
> por dentro, así que es posible que te cruces con fallos o con cosas a
> medio terminar, también en teléfono y en PC. Si encontrás algo roto,
> reportalo desde Ajustes → Reportar.

### 📺 Android TV — reproductor

- **El video ya no debería verse cuadro por cuadro.** En la 1.0.40 se
  activó un descarte de imagen demasiado agresivo que, al saltear cuadros
  que otros necesitan como referencia, dejaba la imagen pegada y avanzando
  a tirones. Se revirtió.
- **Los controles vuelven a responder.** El indicador de velocidad de red
  consultaba al motor de video cada 2 segundos, compitiendo con él en el
  mismo hilo del que dependen la imagen y las teclas del mando. Ahora solo
  consulta cuando los controles están a la vista.
- **Dar play con el servidor ya elegido.** Si ya había un servidor
  seleccionado, había que bajar hasta la lista y volver a confirmarlo para
  que arrancara. Ahora el botón OK arranca directamente.
- **"Continuar viendo" ya no puede dejar el reproductor trabado.** Ese
  aviso bloqueaba todo hasta responderlo, y en televisor podía quedar sin
  recibir el control remoto. Ahora retoma solo y avisa sin bloquear —
  con la flecha izquierda volvés al principio.
- **Colchón de descarga menos recortado**, para que un video pesado no se
  quede sin datos.

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
| **`PrismHub-setup-windows-v1.0.41.exe`** | **Instalador.** Lo normal: instala y crea el acceso directo |
| `PrismHub-v1.0.41-windows-x64.zip` | Portable: se descomprime y se ejecuta, sin instalar |

### 🐧 Linux

| Archivo | Para |
|---|---|
| `PrismHub-v1.0.41-linux-x64.tar.gz` | Se descomprime y se ejecuta |

> Los archivos que llevan la versión en el nombre (`v1.0.41`) quedan fijos en
> esta publicación. Los de Android que **no** la llevan apuntan siempre a la
> más nueva — son los que conviene usar para un enlace o un código que quede
> guardado.
