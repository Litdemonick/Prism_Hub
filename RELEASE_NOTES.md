## PrismHub v1.0.29 — Ahora sí se instala en el televisor

PrismHub llega a **Android TV**: aparece en el menú de aplicaciones del
televisor y se maneja de punta a punta con el control remoto.

> 🔧 **Si probaste la 1.0.28 y tu televisor decía «Esta app no es compatible
> con la TV», era esto.** El sistema la rechazaba antes de abrirla porque, por
> el permiso de huella digital que usa la Zona +18, daba por hecho que la app
> exigía un lector de huella — y ningún televisor tiene. Ya está corregido:
> **usá esta versión, no la 1.0.28.**

Todo lo demás de esta versión venía de la
[1.0.28](https://github.com/Litdemonick/Prism_Hub/releases/tag/v1.0.28), que
quedó sin poder instalarse en televisores.

> ⚠️ **La app está en mantenimiento general.**
> Se la está reestructurando por dentro mientras se suma el soporte para
> televisores, así que es posible que te cruces con fallos o con cosas a medio
> terminar, también en teléfono y en PC. Si encontrás algo roto, reportalo
> desde Ajustes → Reportar: es lo que hace que se arregle rápido.

### 📺 Android TV

- **Se instala y aparece como cualquier app de TV**, con su ícono en el menú
  del televisor.
- **Inicio propio**, con el menú de zonas a la izquierda (Inicio, TV en vivo,
  Biblioteca, Películas, Series, Anime) y el catálogo al lado. Las zonas que
  todavía no existen se muestran igual, diciendo que están en construcción: así
  se sabe qué viene, en vez de que aparezcan un día de la nada.
- **Buscar con teclado en pantalla.** En un televisor no hay teclado, y el del
  sistema tapa media pantalla justo cuando querés ver los resultados. Acá el
  teclado es parte de la pantalla y los resultados quedan siempre a la vista,
  actualizándose con cada letra.
- **La ficha, en dos paneles**: portada, datos y acciones a un lado; los
  episodios al otro. Desde un episodio llegás a «Ver ahora» con una sola flecha.
- **El reproductor dice qué hace cada tecla** —OK pausa, ◀ ▶ mueven, ▼ abre los
  servidores— porque en un mando, lo que no está escrito no se descubre.
- **Todo se recorre con el control**: extensiones, repositorio, ajustes,
  biblioteca, historial y filtros. Y si el foco se pierde por algún motivo, la
  primera flecha lo recupera en vez de dejar la app trabada.
- **Lo que no tiene sentido en un televisor, no está**: el envío a otra pantalla
  (ya lo estás viendo en el televisor), los botones de ventana y el tutorial de
  gestos táctiles.

### 🔞 Zona +18

- **Se terminó la pregunta de «¿esto es contenido +18?».** Salía al abrir
  cualquier título nuevo —en One Piece, en lo que fuera— y justo al tocar «ver»,
  que es el peor momento para frenar a alguien con una pregunta que casi nunca
  aplica.
- Ahora se resuelve solo, con lo que la app ya sabe: si la extensión está
  marcada +18 en el catálogo, o si estás explorando con su filtro de adultos, es
  +18; el resto es contenido normal. Cada cosa sigue yendo a su zona, sin
  preguntarte nada.

### 🧩 En todas las plataformas

- El listado de extensiones instaladas dejó de tirar avisos en consola por cada
  extensión de la lista.
- Ajustes suma accesos directos a **Extensiones instaladas** y al
  **Repositorio**.

---

## ⬇️ Cuál descargar

### 📺 Android TV, Fire TV y cajas Android

| Archivo | Para |
|---|---|
| **`PrismHub-androidtv-arm64-v8a.apk`** | **La mayoría de los televisores** y cajas actuales |
| `PrismHub-androidtv-armeabi-v7a.apk` | Aparatos viejos, de 32 bits |
| `PrismHub-androidtv-x86_64.apk` | Emuladores y algunas cajas con procesador Intel |

> 💡 **Instalar en el televisor sin cables.** Con la app **Downloader** (la de
> Fire TV / Android TV), pegá este enlace y listo — apunta siempre a la última
> versión, así que sirve para siempre:
>
> ```
> https://github.com/Litdemonick/Prism_Hub/releases/latest/download/PrismHub-androidtv-arm64-v8a.apk
> ```

### 📱 Android (teléfono y tablet)

| Archivo | Para |
|---|---|
| **`PrismHub-android-arm64-v8a.apk`** | **La mayoría de los teléfonos** y tablets |
| `PrismHub-android-armeabi-v7a.apk` | Teléfonos viejos, de 32 bits |
| `PrismHub-android-x86_64.apk` | Emuladores |

> Los de teléfono y los de televisor son **el mismo archivo**, con dos nombres:
> un solo APK sirve para todo Android y la app reconoce sola dónde está
> corriendo. Están separados solo para que se vea de un vistazo cuál bajar.

### 🪟 Windows

| Archivo | Para |
|---|---|
| **`PrismHub-setup-windows-v1.0.29.exe`** | **Instalador.** Lo normal: instala y crea el acceso directo |
| `PrismHub-v1.0.29-windows-x64.zip` | Portable: se descomprime y se ejecuta, sin instalar |

### 🐧 Linux

| Archivo | Para |
|---|---|
| `PrismHub-v1.0.29-linux-x64.tar.gz` | Se descomprime y se ejecuta |

> Los archivos que llevan la versión en el nombre (`v1.0.29`) quedan fijos en
> esta publicación. Los de Android que **no** la llevan apuntan siempre a la
> más nueva — son los que conviene usar para un enlace o un código que quede
> guardado.
