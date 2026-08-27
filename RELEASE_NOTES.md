## PrismHub v1.0.33 — Películas, Series, Anime y Mangas, de verdad

> 🎬 **Las zonas de navegación ya no son un Inicio con otro nombre.**
> Películas, Series, Anime y Mangas pasan a ser catálogos propios: entrás y
> ves TODO lo que tus extensiones activas tienen para esa categoría, en
> tarjetas grandes, con orden y sin mezclar. Una extensión con contenido
> normal y +18 a la vez (ShadeManga, ManhwaWeb) solo muestra acá su parte
> normal — lo demás vive donde corresponde, en la Zona +18.

> ⚠️ **La app sigue en mantenimiento general.** Se la sigue reestructurando
> por dentro, así que es posible que te cruces con fallos o con cosas a
> medio terminar, también en teléfono y en PC. Si encontrás algo roto,
> reportalo desde Ajustes → Reportar.

### 🎬 Las zonas, como catálogo real

- **Películas, Series, Anime y Mangas** ya muestran una grilla completa con
  todo lo que tus extensiones activas declaran para esa categoría, no una
  fila cortada del Inicio.
- **La Zona +18 también.** "Explorar" ahora abre el catálogo completo de
  extensiones +18 en tarjetas, en vez de mandarte al buscador vacío.
- **Continuar viendo/leyendo y Favoritos quedan bien separados.** Lo que
  guardás desde la Zona +18 va SIEMPRE a la biblioteca +18, nunca a la
  general — y al revés. Antes una extensión mixta podía filtrarse a la
  biblioteca equivocada sin que se notara.
- **Botón de refrescar en PC** en cada zona (en Android ya existe deslizando
  hacia abajo), y las zonas vacías por falta de conexión ahora sí dejan
  volver a intentar deslizando.

### 🔍 Buscar

- **Buscar dentro de UNA extensión puntual**, en PC y en Android, sin tener
  que revisar los resultados de todas — con sus propios botones, arriba de
  la pantalla. En Android TV el buscador se queda simple a propósito: ahí
  se busca en todo de una, sin ese paso extra que con un control remoto
  sobra.
- **Errores de verdad, no "sin resultados".** Si una extensión puntual está
  caída, ahora se dice y se ofrece reintentar, en vez de mostrar el mismo
  cartel que cuando de verdad no hay nada.
- **El teclado ya no se cierra solo** al escribir la primera letra en el
  buscador de Android.

### 🧭 Navegación en PC y Android

- **Panel lateral de PC rediseñado**, con íconos circulares y sin scrollbar
  interno en ventanas chicas.
- **Desborde corregido en la barra de abajo de Android**, tanto de pie como
  acostado.
- **Zona de TV en vivo**, dejada lista en el menú de las tres plataformas
  para cuando haya extensiones de streaming — hoy queda vacía a propósito.
- **Tocar una card en Android** entra directo a la ficha; mantenerla
  presionada muestra la info sin navegar.

### 📺 Android TV

- **El vídeo ya reproduce en televisores que antes se quedaban en negro**
  (Fire TV y cajas Android genéricas): la detección de "esto es un
  televisor" dependía de una sola señal del sistema que esos aparatos no
  siempre dan bien, y sin ella la app entraba con controles pensados para
  dedo, que un control remoto no puede tocar.
- **La Zona +18 pide solo el PIN de la app**, sin pasar por huella ni por
  ningún bloqueo del sistema — ninguno de los dos tiene sentido con un
  mando.
- **La selección con el mando ahora se ve como el mouse en PC**: un
  resplandor con el color de acento, no un borde blanco suelto.

### 🧩 Extensiones instaladas y Repositorio

- **Filtros por zona** (Películas/Series/Anime/Mangas), además de los de
  Video/Lectura — para saber de un vistazo qué extensión aporta a cada
  categoría, en las tres plataformas.
- **Menos botones sueltos en PC**: las cuatro acciones en bloque
  (activar/desactivar/actualizar/desinstalar todas) y los cinco filtros del
  Repositorio se juntan cada uno en un solo botón con menú.
- **Desinstalar todas ahora también alcanza a las +18**, avisando antes
  cuántas de esas se van a borrar.
- **La grilla del Repositorio ya no salta de lugar** al instalar una
  extensión marcada inestable.
- **Cards más grandes en Android TV**, en las dos pantallas.

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
| **`PrismHub-setup-windows-v1.0.33.exe`** | **Instalador.** Lo normal: instala y crea el acceso directo |
| `PrismHub-v1.0.33-windows-x64.zip` | Portable: se descomprime y se ejecuta, sin instalar |

### 🐧 Linux

| Archivo | Para |
|---|---|
| `PrismHub-v1.0.33-linux-x64.tar.gz` | Se descomprime y se ejecuta |

> Los archivos que llevan la versión en el nombre (`v1.0.33`) quedan fijos en
> esta publicación. Los de Android que **no** la llevan apuntan siempre a la
> más nueva — son los que conviene usar para un enlace o un código que quede
> guardado.
