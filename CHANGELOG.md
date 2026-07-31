# Historial de versiones

Notas de cada versión publicada de PrismHub, de la más nueva a la más vieja.

Este archivo existe porque en GitHub solo se mantienen publicadas las versiones
recientes: los releases anteriores se dan de baja para que nadie descargue por
error una versión que ya no se puede actualizar en el lugar. Las notas, en
cambio, se conservan acá enteras.

Los archivos de descarga de una versión dada de baja ya no están disponibles;
usá siempre la última desde
[Releases](https://github.com/Litdemonick/Prism_Hub/releases).

---

## PrismHub v1.0.13 — Zona +18, filtros del repositorio y actualizaciones

Versión de correcciones sobre la [1.0.12](https://github.com/Litdemonick/Prism_Hub/releases/tag/v1.0.12).
Los cambios grandes —seguimiento de lo que ves y leés, filtros del Historial y
el rediseño del Inicio— vinieron en la
[1.0.10](https://github.com/Litdemonick/Prism_Hub/releases/tag/v1.0.10).

### 🔞 Zona +18

- **«Explorar catálogo» ahora abre el catálogo +18.** Estando dentro de la
  Zona +18, ese botón llevaba al buscador **normal**: en Android cambiaba de
  pestaña y cerraba la zona entera, y en Windows y Linux iba a la búsqueda
  general. Ahora abre la búsqueda +18, **sin volver a pedir huella ni PIN** —ya
  los pusiste para entrar— y **volver atrás siempre te deja en el Inicio +18**,
  sin importar desde dónde hayas entrado.
- **Instalar o activar una extensión ya se nota al instante.** La búsqueda +18
  seguía diciendo «Sin extensiones instaladas» hasta que tocabas «Actualizar» a
  mano: el aviso de que algo cambió llegaba solo a la búsqueda normal, nunca a
  la de la zona.

### 🧩 Repositorio de extensiones

Filtros nuevos, en **Windows, Linux y Android** (en el teléfono la hoja de
filtros solo tenía tipo y nivel):

- **Contenido:** Todo · Sin +18 · Solo +18
- **Estado:** Todas · Instaladas · Sin instalar · **Nuevas**

«Nuevas» son las que no estaban la última vez que abriste el repositorio. Se
calcula contra lo que ya viste en **este** dispositivo, porque el catálogo no
guarda fecha de publicación. La primera vez no marca nada: anunciar el catálogo
entero como novedad no le serviría a nadie.

Los filtros de tipo (vídeo/lectura), nivel (estable/inestable) e idioma siguen
donde estaban.

### 🪟 Instalador de Windows

- **Ahora sale en tu idioma.** Salía siempre en inglés aunque Windows estuviera
  en español; ahora lo elige solo según el idioma del sistema.
- **Dice qué está haciendo.** Antes arrancaba directo en «elegí carpeta», sin
  aclarar nada. Ahora avisa si es una instalación nueva o una actualización,
  **con la versión que tenés y la que se va a instalar**, y recuerda que tu
  historial, favoritos y ajustes se conservan.

### 🔄 Actualizaciones

- **Aviso cuando una versión es demasiado vieja para actualizarse sola.** A
  partir de ahora cada versión puede declarar desde qué versión se puede
  instalar encima. Si la tuya es anterior, la app **ya no ofrece la
  actualización automática** —que fallaría al instalar sin explicar por qué— y
  te manda directo a descargar el instalador.

> **Sobre esto, con todas las letras:** la comprobación corre en la app que
> tenés instalada, así que solo la respetan las versiones que ya traen este
> código, o sea de la **1.0.13** en adelante. Una versión anterior va a seguir
> ofreciendo la actualización igual — eso no se puede cambiar desde una versión
> nueva. De la 1.0.12 en adelante todo se actualiza normal, sin bloqueos.

---

### 📱 Sobre actualizar en Android

> **Si ya tenés la 1.0.10 o posterior**, esta actualización se instala
> **encima**, sin desinstalar y sin perder nada.
>
> **Si venís de la 1.0.8 o la 1.0.9**, hay que **desinstalar la app una única
> vez** antes de instalar el APK. Esas versiones se publicaron firmadas con una
> llave de depuración distinta en cada compilación, y Android no permite
> reemplazar la firma de una app ya instalada. **Desinstalar borra el historial,
> los favoritos y los ajustes de ese teléfono.** De la 1.0.10 en adelante no
> vuelve a pasar.

En **Windows y Linux** nada de esto aplica: tus datos viven fuera de la carpeta
del programa y se conservan siempre.

---

### 📦 Descargas

| Archivo | Plataforma | Descripción |
|---|---|---|
| `PrismHub-setup-v1.0.13.exe` | Windows x64 | Instalador (recomendado) |
| `PrismHub-v1.0.13-windows-x64.zip` | Windows x64 | Portable, sin instalador |
| `PrismHub-v1.0.13-linux-x64.tar.gz` | Linux x64 | Binario precompilado |
| `PrismHub-v1.0.13-android-arm64-v8a.apk` | Android | ARM64 — teléfonos modernos |
| `PrismHub-v1.0.13-android-armeabi-v7a.apk` | Android | ARM32 — teléfonos antiguos |
| `PrismHub-v1.0.13-android-x86_64.apk` | Android | x86_64 — emuladores y tabletas |

### 🐧 Linux

```bash
curl -fsSL https://raw.githubusercontent.com/Litdemonick/Prism_Hub/main/install/install.sh | bash
```

También hay `PKGBUILD` para Arch y derivados en `install/`.

---

Proyecto de código abierto bajo AGPL-3.0. Reportá fallos y proponé mejoras en
[Issues](https://github.com/Litdemonick/Prism_Hub/issues).

**Changelog completo:** https://github.com/Litdemonick/Prism_Hub/compare/v1.0.12...v1.0.13

---

## PrismHub v1.0.12 — correcciones

Versión de correcciones sobre la [1.0.10](https://github.com/Litdemonick/Prism_Hub/releases/tag/v1.0.10),
que es la que trajo los cambios grandes: seguimiento de lo que ves y leés,
filtros en el Historial, huella dactilar en la Zona +18 y el rediseño del
Inicio.

### ▶️ «Continuar viendo» ahora funciona con vídeo

El arreglo más importante de esta versión.

**Ver un vídeo no dejaba rastro en «Continuar viendo».** Una obra se marcaba
como terminada mirando solo su posición en la lista de episodios, y el
historial se escribe apenas *arranca* la reproducción. O sea que abrir el
último episodio bastaba para darlo por visto y sacarlo de la fila mientras
todavía lo estabas mirando. Con una **película** era peor: tiene un único
episodio, así que quedaba completada en el segundo uno y **nunca** llegaba a
«Continuar». En lectura casi no se notaba porque uno abre un capítulo del medio
de una lista larga.

Ahora «al día» pide las dos cosas: estar en el último episodio **y** haberlo
terminado de verdad.

- **Se reparan los registros que quedaron mal.** Al abrir esta versión, lo que
  se marcó como visto sin haberse terminado vuelve solo a «Continuar». Solo se
  toca lo que se puede comprobar; nada se borra y nada se marca de más.
- **La tarjeta vuelve a mostrar el frame donde quedaste.** La captura no se
  estaba guardando nunca: se tomaba demasiado tarde, con el reproductor ya
  cerrándose. Ahora se toma antes, con límite de tiempo, así que no puede
  demorar el cierre. Vale para el reproductor nativo y para el de WebView.

### 🖼️ Historial

- **Las tarjetas de vídeo se quedaban sin imagen**, sobre todo en la Zona +18.
  Parecía que el botón de mostrar/ocultar imagen dejaba de responder, pero la
  portada nunca había podido cargar: el Historial trataba toda portada de vídeo
  como un archivo local, y cuando era una dirección de internet no cargaba nada.
- **«Ver todo» abre la pestaña que corresponde.** Antes los dos bloques de
  Favoritos caían en «Fav. Vídeo» y los de Continuar en «Todo», sin importar
  cuál tocaras. En los dos Inicios y en las tres plataformas.

### 🪟 Windows

- **La app se veía chica y pixelada dentro de la ventana** al abrirla, incluso
  en la pantalla de carga, y se arreglaba sola cerrando y volviendo a abrir. El
  tamaño se aplicaba antes de restaurar la posición: con dos monitores de
  distinta escala (100% y 150%, lo normal con un portátil y una pantalla
  externa), la ventana terminaba con una escala y el contenido dibujado con
  otra. Además, una posición guardada de un monitor que ya no está deja de abrir
  la ventana fuera de la pantalla.
- **Los diálogos se pueden mover.** Con la barra de título propia de la app, un
  diálogo dejaba la ventana clavada — el aviso de beta al arrancar ni siquiera
  se puede cerrar tocando afuera. Ahora se arrastra desde su título.

### 🔄 Actualizaciones

- **El aviso de versión nueva ya no es una columna angosta.** Las notas se leen
  en un ancho cómodo y **el scroll funciona**, en Windows, Linux y Android:
  había dos áreas desplazables anidadas peleándose el gesto.
- **Android: ya no hay que empezar de cero por el permiso.** Si faltaba el
  permiso de «instalar apps desconocidas», se abría Ajustes y ahí terminaba
  todo: el archivo recién descargado se perdía y el aviso de actualizando
  desaparecía sin dejar señal de que hubiera algo a medio instalar. Ahora la
  instalación **se retoma sola** al volver a la app.
- Desaparece el recuadro oscuro suelto debajo del diálogo de descarga.
- El aviso de versión beta tiene mejor espaciado.

---

### 📱 Sobre actualizar en Android

> **Si ya tenés la 1.0.10 o la 1.0.11**, esta actualización se instala
> **encima**, sin desinstalar y sin perder nada.
>
> **Si venís de la 1.0.8 o la 1.0.9**, hay que **desinstalar la app una única
> vez** antes de instalar el APK. Esas versiones se publicaron firmadas con una
> llave de depuración distinta en cada compilación, y Android no permite
> reemplazar la firma de una app ya instalada. **Desinstalar borra el historial,
> los favoritos y los ajustes de ese teléfono.** De la 1.0.10 en adelante no
> vuelve a pasar.

En **Windows y Linux** nada de esto aplica: tus datos viven fuera de la carpeta
del programa y se conservan siempre.

---

### 📦 Descargas

| Archivo | Plataforma | Descripción |
|---|---|---|
| `PrismHub-setup-v1.0.12.exe` | Windows x64 | Instalador (recomendado) |
| `PrismHub-v1.0.12-windows-x64.zip` | Windows x64 | Portable, sin instalador |
| `PrismHub-v1.0.12-linux-x64.tar.gz` | Linux x64 | Binario precompilado |
| `PrismHub-v1.0.12-android-arm64-v8a.apk` | Android | ARM64 — teléfonos modernos |
| `PrismHub-v1.0.12-android-armeabi-v7a.apk` | Android | ARM32 — teléfonos antiguos |
| `PrismHub-v1.0.12-android-x86_64.apk` | Android | x86_64 — emuladores y tabletas |

### 🐧 Linux

```bash
curl -fsSL https://raw.githubusercontent.com/Litdemonick/Prism_Hub/main/install/install.sh | bash
```

También hay `PKGBUILD` para Arch y derivados en `install/`.

---

Proyecto de código abierto bajo AGPL-3.0. Reportá fallos y proponé mejoras en
[Issues](https://github.com/Litdemonick/Prism_Hub/issues).

**Changelog completo:** https://github.com/Litdemonick/Prism_Hub/compare/v1.0.11...v1.0.12

---

## PrismHub v1.0.11 — correcciones

Versión de correcciones sobre la [1.0.10](https://github.com/Litdemonick/Prism_Hub/releases/tag/v1.0.10),
que es la que trajo los cambios grandes: seguimiento de lo que ves y leés,
filtros en el Historial, huella dactilar en la Zona +18 y el rediseño del
Inicio. Si venís de la 1.0.9 o antes, conviene leer esas notas también.

### 🩹 Qué se corrigió

**El botón «Ver historial» de la Zona +18 no abría nada en Windows y Linux.**
Mostraba una pantalla de error en vez del Historial. Apuntaba a una dirección
interna que no existe. En Android nunca falló, porque ahí la navegación va por
otro camino.

**Android: las tres versiones anteriores salieron con el mismo número interno
de versión.** Android no mira el «1.0.10» para decidir si acepta una
actualización, mira un número interno que quedó clavado en el mismo valor desde
la 1.0.8. Aunque la firma ya estaba corregida en la 1.0.10, repetir ese número
podía hacer que el instalador rechazara el archivo igual. Ahora sube en cada
versión, como corresponde.

---

### 📱 Sobre actualizar en Android

> **Si ya tenés la 1.0.10**, esta actualización se instala **encima**, sin
> desinstalar y sin perder tu historial, favoritos ni ajustes. Es justamente la
> primera versión que lo comprueba de punta a punta.
>
> **Si venís de la 1.0.8 o la 1.0.9**, todavía hay que **desinstalar la app una
> única vez** antes de instalar el APK. Esas versiones se publicaron firmadas
> con una llave de depuración distinta en cada compilación, y Android no permite
> reemplazar la firma de una app ya instalada. **Desinstalar borra el historial,
> los favoritos y los ajustes de ese teléfono** — no hay forma de evitarlo. De
> la 1.0.10 en adelante no vuelve a pasar.

En **Windows y Linux** nada de esto aplica: la actualización siempre fue
directa y tus datos se conservan (viven fuera de la carpeta del programa).

---

### 📦 Descargas

| Archivo | Plataforma | Descripción |
|---|---|---|
| `PrismHub-setup-v1.0.11.exe` | Windows x64 | Instalador (recomendado) |
| `PrismHub-v1.0.11-windows-x64.zip` | Windows x64 | Portable, sin instalador |
| `PrismHub-v1.0.11-linux-x64.tar.gz` | Linux x64 | Binario precompilado |
| `PrismHub-v1.0.11-android-arm64-v8a.apk` | Android | ARM64 — teléfonos modernos |
| `PrismHub-v1.0.11-android-armeabi-v7a.apk` | Android | ARM32 — teléfonos antiguos |
| `PrismHub-v1.0.11-android-x86_64.apk` | Android | x86_64 — emuladores y tabletas |

### 🐧 Linux

```bash
curl -fsSL https://raw.githubusercontent.com/Litdemonick/Prism_Hub/main/install/install.sh | bash
```

También hay `PKGBUILD` para Arch y derivados en `install/`.

---

Proyecto de código abierto bajo AGPL-3.0. Reportá fallos y proponé mejoras en
[Issues](https://github.com/Litdemonick/Prism_Hub/issues).

**Changelog completo:** https://github.com/Litdemonick/Prism_Hub/compare/v1.0.10...v1.0.11

---

## PrismHub v1.0.10 — anime, manga y series, sin límites

App multiplataforma (Windows · Linux · Android) para ver anime, leer manga y
acceder a series y películas mediante extensiones. Cada fuente es un script que
se instala y actualiza **por separado**, sin esperar una versión nueva de la app.

En **Windows y Linux** la actualización es directa y **tu historial, favoritos y
ajustes se conservan**: la base migra sola al abrir. En **Android** hace falta
una desinstalación por única vez — leé el aviso de abajo antes de actualizar.

> ## ⚠️ Importante para quien viene de la 1.0.8 o la 1.0.9 en Android
>
> Esta vez hay que **desinstalar la app antes de instalar el APK**, una única
> vez. Las versiones anteriores salieron firmadas por error con una llave de
> depuración que cambiaba en cada publicación, y Android no deja instalar
> encima cuando la firma no coincide — por eso la actualización nunca
> funcionaba y había que desinstalar siempre.
>
> **Desinstalar borra el historial, los favoritos y los ajustes de ese
> teléfono.** No hay forma de evitarlo: Android no permite reemplazar la firma
> de una app instalada. Lamento el trastorno, es un error que arrastraban las
> versiones anteriores.
>
> Ya está corregido: la 1.0.10 se firma con la llave definitiva del proyecto,
> así que **de acá en adelante las actualizaciones se instalan encima**, sin
> desinstalar y sin perder nada.
>
> En Windows y Linux no aplica: ahí siempre funcionó y se actualiza normal.

### 📦 Descargas

| Archivo | Plataforma | Descripción |
|---|---|---|
| `PrismHub-setup-v1.0.10.exe` | Windows x64 | Instalador (recomendado) |
| `PrismHub-v1.0.10-windows-x64.zip` | Windows x64 | Portable, sin instalador |
| `PrismHub-v1.0.10-linux-x64.tar.gz` | Linux x64 | Binario precompilado |
| `PrismHub-v1.0.10-android-arm64-v8a.apk` | Android | ARM64 — teléfonos modernos |
| `PrismHub-v1.0.10-android-armeabi-v7a.apk` | Android | ARM32 — teléfonos antiguos |
| `PrismHub-v1.0.10-android-x86_64.apk` | Android | x86_64 — emuladores y tabletas |

---

### 🩹 Lo que se rompía y ya no

**La app quedaba inutilizable si se corrompía el archivo de ajustes.** Una
escritura cortada —el sistema matando el proceso, por ejemplo al apagar la
pantalla durante la reproducción— dejaba la caja de ajustes ilegible. El manejo
de ese fallo caía a una caja temporal **sin cargar los valores por defecto**, así
que la app arrancaba con la URL del repositorio y el proxy en blanco: no cargaba
ninguna extensión y en pantalla se veía como si no hubiera internet. Y como la
caja temporal se pierde en cada arranque, se repetía para siempre.

**Pantallas muertas sin explicación.** En release, el widget de error de Flutter
es un rectángulo gris sin texto, así que cualquier fallo al construir la interfaz
se veía igual y no decía nada. Ahora muestra el error y dónde ocurrió.

**Un ajuste guardado en null tiraba la app entera.** Ahora nunca se devuelve null
si esa opción tiene valor de fábrica, y las claves que quedaron mal se reparan
solas.

**Se perdía el progreso al apagar la pantalla.** El lector y el reproductor
guardaban solo al cerrarse; si el sistema mataba la app en segundo plano se
perdía por dónde ibas. Ahora se vuelca al pasar a segundo plano.

---

### 🆕 Seguimiento de lo que ves y leés

La novedad más grande de esta versión.

- **Pendiente y Completado** se calculan solos: al ver el último episodio
  disponible, la obra queda al día y sale de «Continuar».
- **Cuando sale un capítulo nuevo, vuelve sola** a «Continuar», en segunda
  posición y con un distintivo que dice cuál es. Se comprueba cada 12 horas en
  segundo plano y se puede apagar desde Ajustes → General.
- **Botón «Marcar como finalizada»** en la ficha, para obras que ya no publican
  más. Aparece solo en contenido por capítulos, nunca en películas.
- Si marcaste algo finalizado y **llega un capítulo nuevo, la marca se quita
  sola**: que aparezca contenido demuestra que no había terminado.

### 🏠 Inicio y Zona +18

- **«Continuar» y «Favoritos» se parten en vídeo y lectura.** Cada tipo usa su
  forma de tarjeta: ancha 16:9 para vídeo, vertical para lectura. Mezclados, uno
  de los dos siempre quedaba recortado.
- Tarjetas rediseñadas: menú de tres puntos con ocultar y eliminar, distintivos
  sólidos que se leen sobre cualquier portada, y borde con el color de cada zona.
- **Las portadas ya no se deforman.**
- **«Quitar de Continuar» ya no borra nada.** Antes eliminaba el registro entero:
  perdías el progreso y la marca de finalizada por ordenar una fila.

### 📋 Historial

- Cinco pestañas: Todo, Vídeo, Lectura, **Fav. Vídeo** y **Fav. Lectura**.
- **Filtros por estado**: Pendiente, Completado, Finalizada.
- **Orden**: más reciente, más antiguo, A–Z, Z–A.
- Tarjetas con la forma del Home según el tipo.
- Nuevo en el menú: **«Devolver a Continuar»** y **«Marcar como visto»**.

### 🎬 Reproductor

- **Rueda de carga** mientras espera: al resolver el enlace, al saltar y cuando
  se vacía el buffer. Antes la imagen se congelaba sin ninguna señal.
- **Aviso del salto**: con las teclas I/J, las flechas o el doble toque aparece
  cuántos segundos se movió.
- En el teléfono, el **doble toque respeta el intervalo configurado** — antes
  estaba fijo en 10 segundos y el ajuste no hacía nada.
- El puntero del mouse se esconde junto con los controles.

### 🔞 Zona +18

- **Huella dactilar o Windows Hello antes del PIN.**
- **Confirmación de mayoría de edad** con fecha de nacimiento al activarla, una
  sola vez.
- **Freno a la fuerza bruta**: tras 5 intentos fallidos, espera que se duplica.
- Al reactivar el interruptor, **las extensiones +18 vuelven solas** — y solo las
  que la app había apagado, no las que apagaste vos.
- Zona separada de punta a punta: Inicio, Historial y Favoritos propios.

### 🔌 Extensiones

- **Filtros en Extensiones instaladas**: Todas, Normales, +18, Vídeo, Lectura,
  Desactivadas e Inestables.
- **El botón Actualizar ya funciona.** Antes «Actualización requerida» también
  salía cuando la extensión estaba marcada inestable, así que con la versión ya
  al día el botón reinstalaba lo mismo y no se iba nunca.
- **Una extensión inestable ya no bloquea la ficha**: se entra normal y el aviso,
  con su motivo, va dentro del detalle.
- Datos a prueba de fallos: un ítem mal formado ya no hace desaparecer todo el
  listado de esa extensión.

### ⚙️ Ajustes

- **Aviso de versión beta** al abrir por primera vez, con selector de idioma.
- **Aviso legal** propio, y enlaces al repositorio y a sugerencias.
- **Campos bloqueados** para que no queden inservibles: URL del repositorio y
  User-Agent. Si estaban mal, se reparan al arrancar.
- **«Saltar intervalo»** rediseñado en el teléfono.
- Los widgets del sistema —selector de fecha, menú de texto— **ya salen en
  español**.
- Solo inglés y español: se quitaron los idiomas a medio traducir.

### 🔍 Buscador

- Las extensiones **con resultados salen primero**; las que no encontraron nada
  quedaban mezcladas entre las que sí.
- Las que se saltearon por tener una consulta en curso **ahora se reintentan** en
  vez de quedarse vacías.

---

### 🔧 Correcciones de la 1.0.10

- **Firma de los APK de Android.** Ningún release estaba firmado de verdad: al
  faltar la llave, la compilación caía en silencio a una de depuración distinta
  en cada publicación. Ahora se firma con la llave definitiva, y si por lo que
  sea faltara, la publicación **falla en vez de salir** con un APK que nadie
  podría actualizar.
- **La actualización no se ofrece hasta que el release está completo.** Cada
  plataforma sube su archivo cuando termina de compilar, así que había una
  ventana en la que la versión ya figuraba pero el instalador que te toca aún
  no existía. Ahora se espera a que estén los de las tres.
- **«Quitar de Continuar» ya funciona.** La tarjeta desaparecía un momento y
  volvía al refrescar, porque el cambio se escribía sobre un registro que no
  era el de la base.
- **Botón «Ver historial»** cuando el Inicio está vacío, en las dos zonas. Con
  los estados nuevos, terminar todo deja el Inicio sin tarjetas aunque el
  Historial tenga contenido.
- **Filtros y pestañas centrados** en el Historial en el teléfono, y la barra
  del buscador se reacomoda en pantallas angostas en vez de recortar los
  filtros.
- **Selector de idioma** en el aviso de bienvenida, para cambiarlo sin buscar
  Ajustes.

---

### 🐧 Linux

```bash
curl -fsSL https://raw.githubusercontent.com/Litdemonick/Prism_Hub/main/install/install.sh | bash
```

También hay `PKGBUILD` para Arch y derivados en `install/`.

---

Proyecto de código abierto bajo AGPL-3.0. Reportá fallos y proponé mejoras en
[Issues](https://github.com/Litdemonick/Prism_Hub/issues).

**Changelog completo:** https://github.com/Litdemonick/Prism_Hub/compare/v1.0.9...v1.0.10

---

## PrismHub v1.0.9 — anime, manga y series, sin límites

App multiplataforma (Windows · Linux · Android) para ver anime, leer manga y
acceder a series y películas mediante extensiones. Cada fuente es un script que
se instala y actualiza **por separado**, sin esperar una versión nueva de la app.

Si venís de la 1.0.8, **tu historial, favoritos y ajustes se conservan**: la
base migra sola al abrir y no hay que reinstalar nada.

### 📦 Descargas

| Archivo | Plataforma | Descripción |
|---|---|---|
| `PrismHub-setup-v1.0.9.exe` | Windows x64 | Instalador (recomendado) |
| `PrismHub-v1.0.9-windows-x64.zip` | Windows x64 | Portable, sin instalador |
| `PrismHub-v1.0.9-linux-x64.tar.gz` | Linux x64 | Binario precompilado |
| `PrismHub-v1.0.9-android-arm64-v8a.apk` | Android | ARM64 — teléfonos modernos |
| `PrismHub-v1.0.9-android-armeabi-v7a.apk` | Android | ARM32 — teléfonos antiguos |
| `PrismHub-v1.0.9-android-x86_64.apk` | Android | x86_64 — emuladores y tabletas |

---

### 🩹 Lo que se rompía y ya no

**La app quedaba inutilizable si se corrompía el archivo de ajustes.** Una
escritura cortada —el sistema matando el proceso, por ejemplo al apagar la
pantalla durante la reproducción— dejaba la caja de ajustes ilegible. El manejo
de ese fallo caía a una caja temporal **sin cargar los valores por defecto**, así
que la app arrancaba con la URL del repositorio y el proxy en blanco: no cargaba
ninguna extensión y en pantalla se veía como si no hubiera internet. Y como la
caja temporal se pierde en cada arranque, se repetía para siempre.

**Pantallas muertas sin explicación.** En release, el widget de error de Flutter
es un rectángulo gris sin texto, así que cualquier fallo al construir la interfaz
se veía igual y no decía nada. Ahora muestra el error y dónde ocurrió.

**Un ajuste guardado en null tiraba la app entera.** Ahora nunca se devuelve null
si esa opción tiene valor de fábrica, y las claves que quedaron mal se reparan
solas.

**Se perdía el progreso al apagar la pantalla.** El lector y el reproductor
guardaban solo al cerrarse; si el sistema mataba la app en segundo plano se
perdía por dónde ibas. Ahora se vuelca al pasar a segundo plano.

---

### 🆕 Seguimiento de lo que ves y leés

La novedad más grande de esta versión.

- **Pendiente y Completado** se calculan solos: al ver el último episodio
  disponible, la obra queda al día y sale de «Continuar».
- **Cuando sale un capítulo nuevo, vuelve sola** a «Continuar», en segunda
  posición y con un distintivo que dice cuál es. Se comprueba cada 12 horas en
  segundo plano y se puede apagar desde Ajustes → General.
- **Botón «Marcar como finalizada»** en la ficha, para obras que ya no publican
  más. Aparece solo en contenido por capítulos, nunca en películas.
- Si marcaste algo finalizado y **llega un capítulo nuevo, la marca se quita
  sola**: que aparezca contenido demuestra que no había terminado.

### 🏠 Inicio y Zona +18

- **«Continuar» y «Favoritos» se parten en vídeo y lectura.** Cada tipo usa su
  forma de tarjeta: ancha 16:9 para vídeo, vertical para lectura. Mezclados, uno
  de los dos siempre quedaba recortado.
- Tarjetas rediseñadas: menú de tres puntos con ocultar y eliminar, distintivos
  sólidos que se leen sobre cualquier portada, y borde con el color de cada zona.
- **Las portadas ya no se deforman.**
- **«Quitar de Continuar» ya no borra nada.** Antes eliminaba el registro entero:
  perdías el progreso y la marca de finalizada por ordenar una fila.

### 📋 Historial

- Cinco pestañas: Todo, Vídeo, Lectura, **Fav. Vídeo** y **Fav. Lectura**.
- **Filtros por estado**: Pendiente, Completado, Finalizada.
- **Orden**: más reciente, más antiguo, A–Z, Z–A.
- Tarjetas con la forma del Home según el tipo.
- Nuevo en el menú: **«Devolver a Continuar»** y **«Marcar como visto»**.

### 🎬 Reproductor

- **Rueda de carga** mientras espera: al resolver el enlace, al saltar y cuando
  se vacía el buffer. Antes la imagen se congelaba sin ninguna señal.
- **Aviso del salto**: con las teclas I/J, las flechas o el doble toque aparece
  cuántos segundos se movió.
- En el teléfono, el **doble toque respeta el intervalo configurado** — antes
  estaba fijo en 10 segundos y el ajuste no hacía nada.
- El puntero del mouse se esconde junto con los controles.

### 🔞 Zona +18

- **Huella dactilar o Windows Hello antes del PIN.**
- **Confirmación de mayoría de edad** con fecha de nacimiento al activarla, una
  sola vez.
- **Freno a la fuerza bruta**: tras 5 intentos fallidos, espera que se duplica.
- Al reactivar el interruptor, **las extensiones +18 vuelven solas** — y solo las
  que la app había apagado, no las que apagaste vos.
- Zona separada de punta a punta: Inicio, Historial y Favoritos propios.

### 🔌 Extensiones

- **Filtros en Extensiones instaladas**: Todas, Normales, +18, Vídeo, Lectura,
  Desactivadas e Inestables.
- **El botón Actualizar ya funciona.** Antes «Actualización requerida» también
  salía cuando la extensión estaba marcada inestable, así que con la versión ya
  al día el botón reinstalaba lo mismo y no se iba nunca.
- **Una extensión inestable ya no bloquea la ficha**: se entra normal y el aviso,
  con su motivo, va dentro del detalle.
- Datos a prueba de fallos: un ítem mal formado ya no hace desaparecer todo el
  listado de esa extensión.

### ⚙️ Ajustes

- **Aviso de versión beta** al abrir por primera vez, con selector de idioma.
- **Aviso legal** propio, y enlaces al repositorio y a sugerencias.
- **Campos bloqueados** para que no queden inservibles: URL del repositorio y
  User-Agent. Si estaban mal, se reparan al arrancar.
- **«Saltar intervalo»** rediseñado en el teléfono.
- Los widgets del sistema —selector de fecha, menú de texto— **ya salen en
  español**.
- Solo inglés y español: se quitaron los idiomas a medio traducir.

### 🔍 Buscador

- Las extensiones **con resultados salen primero**; las que no encontraron nada
  quedaban mezcladas entre las que sí.
- Las que se saltearon por tener una consulta en curso **ahora se reintentan** en
  vez de quedarse vacías.

---

### 🐧 Linux

```bash
curl -fsSL https://raw.githubusercontent.com/Litdemonick/Prism_Hub/main/install/install.sh | bash
```

También hay `PKGBUILD` para Arch y derivados en `install/`.

---

Proyecto de código abierto bajo AGPL-3.0. Reportá fallos y proponé mejoras en
[Issues](https://github.com/Litdemonick/Prism_Hub/issues).

**Changelog completo:** https://github.com/Litdemonick/Prism_Hub/compare/v1.0.8...v1.0.9

---

### PrismHub v1.0.8 — anime, manga y series, sin límites

App multiplataforma (Windows · Linux · Android) para ver anime, leer manga y acceder a series/películas mediante un sistema de **extensiones JavaScript**. Cada fuente de contenido es un script que se instala o actualiza por separado, sin depender de una actualización de la app.

#### 📦 Assets disponibles

| Archivo | Plataforma | Descripción |
|---------|-----------|------------|
| `PrismHub-setup-v1.0.8.exe` | Windows x64 | Instalador (recomendado) |
| `PrismHub-v1.0.8-windows-x64.zip` | Windows x64 | Versión portable (sin instalador) |
| `PrismHub-v1.0.8-linux-x64.tar.gz` | Linux x64 | Binario precompilado |
| `PrismHub-v1.0.8-android-arm64-v8a.apk` | Android | ARM64 (teléfonos modernos — **recomendado**) |
| `PrismHub-v1.0.8-android-armeabi-v7a.apk` | Android | ARM32 (teléfonos antiguos) |
| `PrismHub-v1.0.8-android-x86_64.apk` | Android | x86_64 (emuladores / tabletas x86) |

#### 🧩 Novedades de v1.0.8

##### 🎬 **Reproductor de video — estabilidad**
- ✅ Reparado: la imagen no se veía (solo audio) al abrir un capítulo en algunos servidores
- ✅ Reparado: cerrar el reproductor podía dejarlo abierto con los controles sin responder
- ✅ Reparado: crash al tocar play/pausa/cambiar de servidor después de cerrar el reproductor
- ✅ Reparado: reabrir un capítulo justo después de cerrarlo podía dejar la pantalla nueva sin responder (bug de identificador interno compartido entre sesiones)
- ✅ Apagado del reproductor con límite de tiempo — nunca vuelve a colgar la apertura del siguiente capítulo

##### 🎨 **Animaciones y transiciones (Windows/Linux)**
- ✅ Todas las pantallas de escritorio ahora animan al navegar (antes no había ninguna transición — cambio instantáneo)
- ✅ "Descubre tu próxima obsesión" en Home ahora hace crossfade entre portadas en vez de cambiar de golpe
- ✅ Flechas de scroll en Home animadas también en escritorio (antes solo en móvil)

##### 📋 **Historial**
- ✅ Reparado: el botón de ocultar una tarjeta no refrescaba la vista en la sección Historial
- ✅ Tarjetas ocultas muestran el logo de PrismHub a pantalla completa en vez de una caja oscura recortada
- ✅ Capturas de video en las tarjetas (Continuar/Historial) ahora llenan la tarjeta correctamente en vez de verse achicadas con barras negras

##### 📲 **Sistema de actualización**
- ✅ Reparado (Android): si faltaba el permiso "instalar apps desconocidas", el mensaje que explica cómo habilitarlo se perdía detrás de un error técnico confuso — ahora se ve el mensaje correcto
- ✅ Auditado de punta a punta en Windows, Linux y Android: nombres de assets, permisos y flujo de instalación verificados contra lo que publica este mismo pipeline

##### 🎯 **Características anteriores**
- 🎬 Reproductor con failover automático entre servidores
- 📖 Lector de manga con modo paginado y modo cascada (webtoon)
- 📋 Historial y favoritos con progreso guardado localmente
- 🔄 Auto-actualización en Windows y Linux
- 🔌 Repositorio de extensiones **prism+** preinstalado

#### 🐧 Linux

```bash
## Instalación automática (recomendada)
curl -fsSL https://raw.githubusercontent.com/Litdemonick/Prism_Hub/main/install/install.sh | bash
```

También disponible PKGBUILD para Arch/derivados en `install/PKGBUILD`.

Proyecto **open source bajo AGPL-3.0**. Reportá bugs en [Issues](https://github.com/Litdemonick/Prism_Hub/issues).
### What's Changed
* feat(beta): 1.0.1 develop version - estabilidad, diseño, nuevas exten… by @Litdemonick in https://github.com/Litdemonick/Prism_Hub/pull/1

### New Contributors
* @Litdemonick made their first contribution in https://github.com/Litdemonick/Prism_Hub/pull/1

**Full Changelog**: https://github.com/Litdemonick/Prism_Hub/commits/v1.0.8

---
