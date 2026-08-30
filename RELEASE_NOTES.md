## PrismHub v1.0.45 — Los registros, hechos de nuevo

> 🔍 **Ahora se puede saber qué pasó.** Si la app se cierra sola o algo va
> mal, el registro guarda todo y se lee desde la propia app: qué estaba
> haciendo, en qué aparato y con qué extensión.

> ⚠️ **La app sigue en mantenimiento general.** Se la sigue reestructurando
> por dentro, así que es posible que te cruces con fallos o con cosas a medio
> terminar. Si encontrás algo roto, reportalo desde Ajustes → Reportar.

### 🔍 Registros

- **Se guardan siempre.** Había un interruptor para activarlos, y estaba al
  revés de lo que hace falta: el archivo es lo único que explica un cierre —lo
  que estaba en memoria se va con la app— así que ese interruptor solo servía
  para que, justo cuando algo falla, no hubiera nada que mirar.
- **Se ve el historial completo, no solo lo de ahora.** Antes el visor
  arrancaba vacío en cada apertura, y lo anterior se perdía. Ahora al abrirlo
  está todo, incluidas las sesiones anteriores.
- **Si la app se cerró sola, dice qué estaba haciendo.** Se anota sobre la
  marcha, así que al volver a abrirla queda el recorrido de los últimos pasos:
  a qué zona fuiste, qué servidor abriste, si llegó a verse imagen.
- **Cada sesión empieza indicando el aparato**: versión, si es televisor,
  teléfono o PC, y qué tan potente lo considera la app.
- **Filtros por área** — Todo, Fallos, Extensiones, Reproductor — con botones
  grandes en televisor y compactos en teléfono. Un archivo de miles de líneas
  se vuelve buscable.
- **Colores** para las líneas que se buscan a propósito: el comienzo de cada
  sesión, el resultado de cada servidor y el último rastro antes de un cierre.
- **Exportar** sigue estando en PC y en Android. En televisor no aparece,
  porque ahí no hay a dónde exportar — se lee desde la app.

### 🔒 Seguridad

- **El registro se puede compartir sin exponer nada tuyo.** Se auditó y no se
  saneaba: las direcciones se escribían enteras, y ahí viajan las credenciales
  con las que se firma el vídeo y el nombre de lo que estabas viendo. Ahora se
  conserva el servidor y el formato —que es lo que sirve para arreglar— y se
  va todo lo demás, incluido tu nombre de usuario del sistema.
- **Las pantallas de error también.** El mensaje de un fallo arrastra lo que
  estaba en juego cuando ocurrió; y esa pantalla es justamente la que uno
  fotografía para reportar.
- **Los favoritos del contenido para adultos ya no pueden asomarse** por una
  ruta interna que no filtraba.

### 📺 Android TV

- **El aviso rojo en Ajustes desapareció.** Salía en la sección de contenido
  para adultos. Y detrás había otro fallo tapado: al activar ese contenido, el
  botón para entrar a la zona no aparecía hasta salir y volver a entrar.
- **El registro se recorre con el control remoto** — flechas, y los botones de
  salto rápido mueven de a una pantalla.

### 🖥️ Windows, Linux y Android

- **Ya no salen dos avisos de la misma versión.** Había dos caminos que
  avisaban de una actualización y ninguno sabía del otro, así que cuando una
  publicación terminaba de subirse los dos aparecían a la vez.

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
| **`PrismHub-setup-windows-v1.0.45.exe`** | **Instalador.** Lo normal: instala y crea el acceso directo |
| `PrismHub-v1.0.45-windows-x64.zip` | Portable: se descomprime y se ejecuta, sin instalar |

### 🐧 Linux

| Archivo | Para |
|---|---|
| `PrismHub-v1.0.45-linux-x64.tar.gz` | Se descomprime y se ejecuta |

> Los archivos que llevan la versión en el nombre (`v1.0.45`) quedan fijos en
> esta publicación. Los de Android que **no** la llevan apuntan siempre a la
> más nueva — son los que conviene usar para un enlace o un código que quede
> guardado.
