## PrismHub v1.0.84 — Menos memoria de sobra, capítulo siguiente en el lector

> ⚠️ **La app sigue en mantenimiento general.** Se la sigue reestructurando por
> dentro, así que es posible que te cruces con fallos o con cosas a medio
> terminar. Si encontrás algo roto, reportalo desde Ajustes → Reportar.

### 🧠 Memoria

- **Al entrar al lector o al reproductor, ahora sí se suelta todo lo que no
  se está usando.** Antes solo se soltaban imágenes, y solo en aparatos
  flojos. Si mirabas el Inicio y paseabas un par de zonas antes de abrir un
  capítulo, los motores de esas extensiones seguían vivos justo cuando el
  lector necesita toda la memoria para bajar y decodificar página tras
  página. Ahora se sueltan siempre, sin costo si el aparato tiene de sobra.
- **Minimizar la app (o cambiar a otra en Android) ya libera memoria por sí
  solo.** Antes nada reaccionaba a que la app entera pasara a segundo plano
  — solo a que el sistema avisara que anda corto. En un aparato con memoria
  de sobra ese aviso puede no llegar nunca, así que quedaba gastando RAM sin
  que nadie la mirara. En Android esto es además la causa real detrás de
  "se pierde la posición al volver a entrar": no es que se pierda el dato,
  es que el sistema mata el proceso mientras está afuera. No corre en
  Android TV, que ya tiene su propio mecanismo.

### 📖 Lector

- **Flechas de capítulo anterior/siguiente**, arriba junto a ajustes y al
  pie de la cascada apenas se termina de leer la última página. Antes la
  única forma de cambiar de capítulo era abrir la lista entera de episodios.
- **Arreglado el salto al final al cambiar de capítulo en modo cascada.**
  El capítulo nuevo heredaba el scroll de donde había quedado el anterior;
  si el nuevo era más corto, quedaba pegado contra su propio final. Se ve
  como si el lector "saltara solo" apenas se abre un capítulo.
- **Arreglado un cierre del lector en PC** al abrir una ventana angosta o
  redimensionarla (la barra de scroll dividía por un espacio casi nulo).

### 📥 Importar

- **Un enlace pegado sin `https://` ya no engancha una extensión al azar**
  para importar desde ahí. Antes terminaba en un error que no explicaba
  nada; ahora avisa qué falta en el enlace.
- Arreglado un cierre ocasional al pegar el portapapeles si el diálogo se
  había cerrado mientras tanto.

### 🔄 Actualizar y avisos

- **Actualizar ya no se queda mudo en algunas cajas de Android TV.** Si el
  aparato no tiene registrada la forma moderna de abrir el instalador (pasa
  en ROMs de fabricante recortadas), ahora prueba una segunda forma antes de
  avisar que hay que instalar el APK a mano.
- Arreglado un botón "Ya actualicé" que en algunas pantallas de Android no
  hacía nada al tocarlo, sin ningún error visible.

### 📺 Televisor

- **El botón de texto (por ejemplo en Actualizar) ya se distingue al
  enfocarlo con el mando** — el resaltado anterior era casi invisible contra
  el rosa de acento.
- **Las tarjetas ya no se dibujan encima del panel lateral ni tapan los
  botones de categoría** al desplazarse una fila. Eran el mismo problema
  visto desde dos ángulos distintos.
- Esquinas de las tarjetas parejas con las del Inicio, margen de vuelta para
  el reloj de la barra superior, y los botones del panel lateral pasan a
  fondo sólido en vez de un tinte que se volvía ilegible sobre una portada.
- **Arreglado que la fila de una zona no dejaba bajar el foco**, y que
  llegar al final de una fila a veces saltaba a la fila de arriba en lugar
  de quedarse quieto.
