## PrismHub v1.0.39 — Android TV: Ajustes propios, y el reproductor sin sustos

> 🛠️ **Se corrige un cierre inesperado del reproductor en televisor**: abrir
> un video que ya habías empezado tiraba la app entera. Apareció recién
> ahora porque hasta la versión pasada el video no llegaba a reproducir, así
> que nunca había progreso guardado que ofrecer retomar.

> ⚠️ **La app sigue en mantenimiento general.** Se la sigue reestructurando
> por dentro, así que es posible que te cruces con fallos o con cosas a
> medio terminar, también en teléfono y en PC. Si encontrás algo roto,
> reportalo desde Ajustes → Reportar.

### 📺 Android TV

- **Ajustes rediseñado por completo**, con categorías a un lado y sus
  opciones al otro, botones grandes y solo lo que sirve en un televisor. Se
  fueron los enlaces a páginas web (sugerencias, GitHub) y los ajustes que
  no hacían nada acá.
- **La selección ya no tapa la portada.** El resplandor del foco se pintaba
  *encima* de la card y la dejaba rosada y borrosa; ahora va por detrás, con
  un borde nítido encima.
- **El panel de info de una card no cubre el póster entero**, solo la mitad
  de abajo — con un mando, la card enfocada es justamente la que estás
  mirando.
- **La rueda de carga ya no se superpone al ícono de pausa**, y las dos
  quedaron centradas en el mismo lugar.
- **Subir con el mando dentro de las opciones del reproductor** ahora pasa
  de Servidores a Episodios, en vez de cerrar todo el panel.
- **Todo va más fluido.** Se quitaron dos trabajos que corrían todo el
  tiempo sin que se vieran: el contador de red reconstruía el reproductor
  entero cada 2 segundos, y la barra inferior seguía actualizándose varias
  veces por segundo aun estando oculta.
- **Las zonas avisan en qué estado están** al bajar: si viene más, si está
  cargando, o si ya no queda nada.
- **Inicio y las zonas se enteran de una extensión nueva.** Antes había que
  cerrar la app: en un televisor no existe ni deslizar para refrescar ni
  botón de actualizar. El carrusel no se resortea por esto — sigue igual
  hasta la próxima vez que abras la app.
- **Selector de fecha de nacimiento propio** para la Zona +18, navegable con
  el control remoto — el anterior era el de Android y se cortaba en pantalla.
- **La velocidad de red** solo se ve junto con los controles, no todo el
  tiempo.
- **Contador "3 / 24"** en las listas de episodios y servidores.

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
| **`PrismHub-setup-windows-v1.0.39.exe`** | **Instalador.** Lo normal: instala y crea el acceso directo |
| `PrismHub-v1.0.39-windows-x64.zip` | Portable: se descomprime y se ejecuta, sin instalar |

### 🐧 Linux

| Archivo | Para |
|---|---|
| `PrismHub-v1.0.39-linux-x64.tar.gz` | Se descomprime y se ejecuta |

> Los archivos que llevan la versión en el nombre (`v1.0.39`) quedan fijos en
> esta publicación. Los de Android que **no** la llevan apuntan siempre a la
> más nueva — son los que conviene usar para un enlace o un código que quede
> guardado.
