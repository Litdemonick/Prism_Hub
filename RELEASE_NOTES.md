## PrismHub v1.0.44 — Android TV: se cerraba al salir, y va más fluido

> 📺 **Corrige un fallo que cerraba la app entera**: en televisor, salir del
> reproductor mientras se estaba viendo algo sacaba al usuario de la app. Era
> un problema introducido en la 1.0.42.

> ⚠️ **La app sigue en mantenimiento general.** Se la sigue reestructurando
> por dentro, así que es posible que te cruces con fallos o con cosas a medio
> terminar. Si encontrás algo roto, reportalo desde Ajustes → Reportar.

### 📺 Android TV — corregido

- **Ya no se cierra al salir del reproductor.** La app devolvía la pantalla a
  su modo normal al mismo tiempo que liberaba el vídeo, y en un televisor ese
  cambio de modo hace renegociar la conexión con la pantalla justo mientras
  el vídeo se está soltando. Las dos cosas cruzándose cerraban la app de
  golpe, sin ningún mensaje. Ahora el modo se devuelve al final, cuando ya no
  queda nada del reproductor.
- **El aviso de versión nueva ya se puede leer con el control remoto.** Esa
  pantalla usaba la disposición de teléfono, que se desplaza con el dedo: con
  un mando no había forma de bajar, y todo lo que no entrara quedaba sin
  leerse. Y como ese aviso bloquea la app, había que decidir a ciegas. Ahora
  las flechas desplazan el texto.

### ⚡ Android TV — fluidez

Segunda tanda de mejoras sobre la misma idea de la 1.0.43: un televisor es
potente **decodificando vídeo**, que es para lo que está hecho, pero su parte
gráfica es más floja que la de un teléfono de gama media.

- **El resplandor del foco cuesta mucho menos.** Cada tarjeta pintaba tres
  sombras difuminadas y las hacía aparecer con una transición en cada
  movimiento del mando. Ahora en televisor es una sola, y aparece puesta —
  con un control remoto el foco *salta* de tarjeta en tarjeta, así que la
  transición no aportaba nada y se pagaba en cada pulsación.
- **Las tarjetas no enfocadas ya no dejan una capa vacía.** Antes cada una
  mantenía su resplandor invisible; ahora, de todas las que hay en pantalla,
  solo la enfocada existe.

### 🛠️ Por dentro

- **El reproductor pasa a hablarle a su motor a través de una capa
  intermedia.** No cambia nada de cómo se ve ni de cómo funciona: por debajo
  corre el mismo motor de siempre. Es el trabajo previo para poder usar un
  motor distinto en Android, que es lo que va a corregir el salto en ciertos
  formatos y el desfase de audio en televisor.
- **Los avisos de versión pueden dirigirse a una plataforma concreta**, para
  que una corrección que solo toca al televisor no haga actualizar a quienes
  usan Windows o Linux.

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
| **`PrismHub-setup-windows-v1.0.44.exe`** | **Instalador.** Lo normal: instala y crea el acceso directo |
| `PrismHub-v1.0.44-windows-x64.zip` | Portable: se descomprime y se ejecuta, sin instalar |

### 🐧 Linux

| Archivo | Para |
|---|---|
| `PrismHub-v1.0.44-linux-x64.tar.gz` | Se descomprime y se ejecuta |

> Los archivos que llevan la versión en el nombre (`v1.0.44`) quedan fijos en
> esta publicación. Los de Android que **no** la llevan apuntan siempre a la
> más nueva — son los que conviene usar para un enlace o un código que quede
> guardado.
