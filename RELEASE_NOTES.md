## PrismHub v1.0.42 — El reproductor, por dentro

> 📺 **Dos cambios apuntan al vídeo en televisor**, que es lo que peor
> andaba: la pantalla ahora se pone a la frecuencia del vídeo, y se suma un
> segundo motor de reproducción que se puede elegir a mano para probarlo.

> ⚠️ **La app sigue en mantenimiento general.** Se la sigue reestructurando
> por dentro, así que es posible que te cruces con fallos o con cosas a
> medio terminar, también en teléfono y en PC. Si encontrás algo roto,
> reportalo desde Ajustes → Reportar.

### 📺 El vídeo en televisor

- **La pantalla se pone a la frecuencia del vídeo.** Casi todo el anime y
  las películas van a 24 cuadros por segundo, y un televisor va a 60. Sin
  pedirle que cambie, esos 24 cuadros se reparten en 60 refrescos: unos
  duran dos y otros tres, y eso se ve como un tirón en cualquier
  movimiento de cámara. No era falta de potencia — las cuentas no daban.
  Ahora se le pide el modo que corresponde al abrir el vídeo, y se lo
  devuelve al salir. Si el televisor no deja cambiarlo, se reproduce igual
  que antes.
- **El dibujado se ajusta al aparato.** Hasta ahora el televisor más
  modesto y la PC más nueva recibían exactamente la misma configuración.
  Ahora un aparato de gama baja dibuja a una resolución acotada, que se
  nota mucho menos que una imagen a tirones.

### 🔧 Segundo motor de reproducción (para probar)

En **Ajustes → Reproductor** aparece, solo en Android, la opción de elegir
con qué motor se reproduce: el de siempre o **ExoPlayer**, el nativo de
Android.

- Queda en **Automático**, que usa el de siempre. El nuevo se elige a mano.
- Está para probar: si un servidor va mal con uno, cambiás y volvés a abrir
  el episodio.
- Dos motivos para que exista: ExoPlayer sabe saltar en listas donde el
  motor actual se queda clavado, y dibuja sobre una superficie del sistema
  en vez de pasar por dos capas de gráficos.

> Es temporal. Cuando esté claro cuál conviene en cada caso, la app va a
> elegir sola y el ajuste desaparece.

### 📖 Lectura

- **Se corrigió el salto hacia atrás al desplazar en modo cascada.** El
  hueco que se reservaba para cada página no tenía relación con el alto que
  la página iba a tener, así que al terminar de cargar el contenido se
  reacomodaba de golpe. Pasaba en cualquier extensión de lectura.

### 🧹 Limpieza

- **Se retiró la transmisión a otros aparatos** (el botón de enviar el
  vídeo a un televisor o Chromecast). Eran más de seis mil líneas que
  complicaban el reproductor por dentro y hacían más difícil arreglar lo
  que de verdad se usa. Puede volver más adelante, ya sobre una base
  ordenada.

### 🛠️ Por dentro

- **Si la app se cierra sola, ahora queda registrado.** Un cierre por un
  fallo del sistema no dejaba ningún rastro, así que no había forma de
  perseguirlo. Ahora el arranque siguiente lo anota con cuánto duró la
  sesión y en qué aparato. Si te pasa, exportá el registro desde Ajustes.
- **Cada servidor deja anotado cómo le fue**: si reprodujo de forma nativa
  o hizo falta el navegador interno, y cuánto tardó en aparecer la imagen.
  Sirve para ir revisando extensión por extensión cuáles conviene mejorar.
- **Las actualizaciones pueden publicarse por plataforma.** Una corrección
  que solo toca Android ya no obliga a Windows y Linux a actualizar por un
  archivo que no cambió para ellos.

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
| **`PrismHub-setup-windows-v1.0.42.exe`** | **Instalador.** Lo normal: instala y crea el acceso directo |
| `PrismHub-v1.0.42-windows-x64.zip` | Portable: se descomprime y se ejecuta, sin instalar |

### 🐧 Linux

| Archivo | Para |
|---|---|
| `PrismHub-v1.0.42-linux-x64.tar.gz` | Se descomprime y se ejecuta |

> Los archivos que llevan la versión en el nombre (`v1.0.42`) quedan fijos en
> esta publicación. Los de Android que **no** la llevan apuntan siempre a la
> más nueva — son los que conviene usar para un enlace o un código que quede
> guardado.
