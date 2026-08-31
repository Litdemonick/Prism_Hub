## PrismHub v1.0.62 — Arranca liviano, y el televisor por fin se siente un televisor

> ⚡ **La app ya no levanta todo al abrirse.** Cada extensión corre en su propio
> motor de JavaScript, y hasta ahora se levantaban TODOS al arrancar. Con
> diecinueve instaladas eran diecinueve motores antes de que vieras nada. Ahora
> se levanta el de una extensión cuando de verdad la usás, y se suelta cuando
> dejás de usarla.

> ⚠️ **La app sigue en mantenimiento general.** Se la sigue reestructurando por
> dentro, así que es posible que te cruces con fallos o con cosas a medio
> terminar. Si encontrás algo roto, reportalo desde Ajustes → Reportar.

### ⚡ Arranque y memoria — en todas las plataformas

- **Los motores se levantan al usarse, no al arrancar.** Cada uno carga unos
  148 KB de librerías, así que con muchas extensiones el arranque era una
  tormenta. Medido en un televisor de 0,9 GB: el sistema pedía memoria cuatro
  veces en los primeros cuarenta segundos.
- **Y se sueltan solos** cuando llevás un rato sin usar esa extensión —un minuto
  en un aparato modesto, cinco en uno capaz—. Recorrer cinco zonas ya no deja
  cinco motores vivos.
- **Apagar o desinstalar una extensión devuelve su memoria** al momento.
- **El fondo del Inicio ya no le pregunta a todas.** Le preguntaba a las
  diecinueve para elegir una imagen; ahora a dos o cinco según el aparato.
- **Y al buscar no se paga esa espera**: los motores se van preparando mientras
  escribís, que es tiempo en que nadie espera nada.

### 📺 El televisor

- **Las tarjetas ya no se cortan.** Al mover el foco, la app desplazaba lo
  mínimo y lo seleccionado quedaba pegado al borde. Ahora queda con aire
  alrededor, y por debajo se ve que la lista sigue.
- **La flecha derecha ya no baja de fila sola** al llegar al final. Derecha es
  derecha, en todas las zonas.
- **El contorno de selección se ve.** En el carrusel del Inicio no se dibujaba
  ninguno, y en Extensiones era el gris de Material, invisible desde el sillón.
- **Se recupera casi una fila de pantalla**: el margen de seguridad se llevaba
  el 5 % de arriba y de abajo, donde no protege de nada.
- **Las filas llegan puestas.** Pedían su contenido justo al entrar en pantalla,
  así que se veía el nombre de la extensión y debajo nada. Ahora piden una
  pantalla antes.
- **Películas, series y anime con tarjetas de televisor**: más grandes y como
  mucho cuatro por fila, en vez de cinco o seis estampillas.
- **La Zona +18 tiene su propia cabecera**, con botones grandes y el nombre
  escrito al lado del icono.
- **El PIN de la Zona entra en una pantalla**, apaisado y sin desplazar.
- **La barra de espacio del teclado va a la derecha**, alcanzable desde
  cualquier fila con una sola pulsación.

### 🔎 Buscar

- **Ya no dice «sin extensiones instaladas» cuando sí las tenés.** Confundía una
  búsqueda sin resultados con no tener ninguna extensión, y mandaba a instalar
  algo que ya estaba.
- **La pantalla vacía invita a escribir** en vez de parecer colgada, y cuenta
  qué va a pasar: que busca en todas tus extensiones a la vez y que los
  resultados van apareciendo a medida que cada una contesta.
