## PrismHub v1.0.43 — Android TV: fluidez

<!-- solo-plataforma: androidtv -->

> 📺 **Esta versión es solo para televisor.** Windows, Linux, teléfono y
> tablet siguen en la 1.0.42: nada de lo que cambia acá los toca, así que no
> tiene sentido hacerlos actualizar.

> ⚠️ **La app sigue en mantenimiento general.** Se la sigue reestructurando
> por dentro, así que es posible que te cruces con fallos o con cosas a medio
> terminar. Si encontrás algo roto, reportalo desde Ajustes → Reportar.

### 📺 Que la interfaz vaya fluida

Se venía notando que la app va a tirones en el televisor — **también en
televisores potentes**. Que falle igual en un aparato bueno descarta que sea
falta de fuerza, y apunta a otra cosa: un televisor es potente
**decodificando vídeo**, que es para lo que está hecho. Su parte gráfica,
componiendo menús y tarjetas, es más floja que la de un teléfono de gama
media. Pero la app solo le aligeraba el trabajo a los aparatos más modestos,
así que un televisor normal recibía casi todo igual que un teléfono.

- **El foco ya no crece al moverse.** Con un control remoto el foco *salta*
  de tarjeta en tarjeta, no se desliza: el resplandor ya dice dónde estás
  parado, y el crecido animado obligaba a repintar la tarjeta y lo de
  alrededor en cada pulsación del mando.
- **Sin fundido al cambiar de zona.** El contenido aparece puesto. Componer
  media pantalla con transparencia era de lo más caro que hacía la interfaz,
  y en un televisor no se extraña.
- **Al abrir la app ya no debería sentirse pesada al principio.** Había una
  tarea que le pedía sus datos a cada extensión instalada apenas arrancaba, y
  cada una levanta su propio motor — con doce extensiones, doce motores
  compitiendo por el procesador justo mientras la pantalla se dibuja y bajan
  las portadas. Ahora esa tarea espera a que la app asiente.

### 🔍 Para encontrar por qué algunos títulos van mal

Si algunos animes van lentísimos o llegan a cerrar la app y otros van bien, el
reproductor no es el culpable — algo particular de ese vídeo lo es. La
sospecha es que en esos casos el televisor **no puede decodificar ese formato
por hardware** y lo hace por software, que es algo que su procesador no da.

Ahora eso queda anotado en el registro: qué códec es y quién lo está
decodificando de verdad. **Si te pasa, exportá el registro desde Ajustes y
compartilo** — con eso se puede confirmar y arreglar.

### 🔧 Corregido de la 1.0.42

- **El selector de motor de vídeo se retiró.** Salió sin terminar: al elegir
  el motor nuevo se escuchaba el audio pero la pantalla quedaba en negro.
  Vuelve cuando esté completo.

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
| **`PrismHub-setup-windows-v1.0.43.exe`** | **Instalador.** Lo normal: instala y crea el acceso directo |
| `PrismHub-v1.0.43-windows-x64.zip` | Portable: se descomprime y se ejecuta, sin instalar |

### 🐧 Linux

| Archivo | Para |
|---|---|
| `PrismHub-v1.0.43-linux-x64.tar.gz` | Se descomprime y se ejecuta |

> Los archivos que llevan la versión en el nombre (`v1.0.43`) quedan fijos en
> esta publicación. Los de Android que **no** la llevan apuntan siempre a la
> más nueva — son los que conviene usar para un enlace o un código que quede
> guardado.
