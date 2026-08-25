## PrismHub v1.0.32 — Android TV, a que vaya fluido

> ⚡ **Si en el televisor iba lenta o se cerraba sola, era esto.**
> La causa de fondo: la app le pedía a la memoria de imágenes 220 MB en
> cualquier aparato, sin fijarse cuánta memoria tenía de verdad. En un
> televisor viejo o un stick barato, con menos de esos 220 MB para toda la
> app, eso terminaba en el sistema cerrándola. Ahora la app se fija primero
> qué tan potente es el televisor y le pide solo lo que le corresponde.
>
> De paso se encontraron y se corrigieron varias animaciones que quedaban
> corriendo para siempre de fondo sin que se viera nada en pantalla —cada
> una obligaba al televisor a dibujar cuadros al pedo, todo el rato— y se
> revisó a fondo qué se pinta de más en cada pantalla.

Esta versión es la continuación directa de la 1.0.29-1.0.31: ahí llegó
Android TV, acá se le hizo el trabajo de fondo para que ande bien en
cualquier televisor, no solo en los potentes.

> ⚠️ **La app sigue en mantenimiento general.** Se la sigue reestructurando
> por dentro, así que es posible que te cruces con fallos o con cosas a
> medio terminar, también en teléfono y en PC. Si encontrás algo roto,
> reportalo desde Ajustes → Reportar.

### ⚡ Rendimiento y estabilidad en Android TV

- **La causa de los cierres.** El techo de memoria para las portadas
  decodificadas ahora se ajusta solo según el aparato, en vez de pedir
  siempre lo mismo. Y si el sistema avisa que le falta memoria, la app
  ahora escucha ese aviso y suelta lo que no hace falta, en vez de esperar
  a que la cierren.
- **Menos trabajo dibujando de fondo.** Varias animaciones quedaban vivas
  aunque no se vieran —el menú lateral llegaba a montar zonas enteras que
  nunca se habían abierto—, y eso obligaba al televisor a trabajar sin
  necesidad, incluso con la pantalla quieta. Se apagaron.
- **Mover el foco con el mando ya no repinta de más.** Antes, pasar de una
  tarjeta a otra podía volver a dibujar la fila entera; ahora solo se
  redibuja lo que de verdad cambió.
- **Portadas más livianas.** Varias imágenes se decodificaban a resolución
  completa aunque se mostraran chicas — la que más pesaba, el fondo grande
  de la ficha.
- **El arranque ya no tranca.** El logo y la animación de carga tenían un
  efecto de sombra carísimo, recalculado sesenta veces por segundo, justo
  en el momento en que la app está más ocupada iniciando. Se reemplazó por
  algo que se ve igual y no cuesta nada.
- **Sin adornos que un control remoto no puede usar.** El brillo de
  "seguí deslizando" al final de una lista, o la transición de pantalla
  completa que desliza dos pantallas a la vez: ninguno de los dos tiene
  sentido con D-pad, y los dos costaban dibujado de más.

### 🧭 Cosas que el mando no podía alcanzar, y ahora sí

- **Los filtros del Inicio se podían marcar pero no aplicar.** La app le
  preguntaba al aparato "¿sos táctil?" para decidir si mostrar el botón de
  aplicar, y un televisor contesta que sí —es Android— aunque no tenga con
  qué deslizar. Quedaba el filtro marcado y sin botón para aplicarlo.
- **Con más de 5 extensiones instaladas, no se podía llegar a las demás.**
  La única forma de cambiar de página era deslizando o con unas flechitas
  pensadas para mouse — ninguna de las dos existe con un control remoto.
  Mismo problema en el Repositorio, con más de 4 extensiones por sección.
- **Con un mouse conectado al televisor, hacer clic en una tarjeta no
  abría nada.**

### 📺 Las pantallas de Android TV, terminadas

- **Biblioteca, Ajustes, Extensiones instaladas, Repositorio e Historial**
  ya tienen el mismo trato que el Inicio y la Ficha: tarjetas grandes,
  márgenes que no se recortan en televisores viejos, y todo alcanzable con
  el mando.
- **El menú lateral se contrae a solo íconos** y se despliega mostrando el
  nombre mientras el mando está parado ahí — como en Netflix o YouTube.
- **El buscador recuerda las últimas búsquedas** y las deja como botones
  arriba del teclado: elegir una vale por diez letras tecleadas de a una.
- **El televisor ya arranca apaisado y sin la barra de estado del
  sistema**, que ahí no tiene nada que mostrar.

### 🧩 En todas las plataformas

- Se corrigió un aviso de actualización que podía repetirse encima de una
  descarga que ya estaba en curso, si la conexión era lenta.

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
| **`PrismHub-setup-windows-v1.0.32.exe`** | **Instalador.** Lo normal: instala y crea el acceso directo |
| `PrismHub-v1.0.32-windows-x64.zip` | Portable: se descomprime y se ejecuta, sin instalar |

### 🐧 Linux

| Archivo | Para |
|---|---|
| `PrismHub-v1.0.32-linux-x64.tar.gz` | Se descomprime y se ejecuta |

> Los archivos que llevan la versión en el nombre (`v1.0.32`) quedan fijos en
> esta publicación. Los de Android que **no** la llevan apuntan siempre a la
> más nueva — son los que conviene usar para un enlace o un código que quede
> guardado.
