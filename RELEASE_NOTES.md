## PrismHub v1.0.71 — Menos tirones y el destacado como corresponde

> ⚠️ **La app sigue en mantenimiento general.** Se la sigue reestructurando por
> dentro, así que es posible que te cruces con fallos o con cosas a medio
> terminar. Si encontrás algo roto, reportalo desde Ajustes → Reportar.

### ⚡ Estabilidad

- **Se corrigió un fallo que introdujo la versión anterior.** El nuevo tope de
  motores de extensión podía soltar el motor de una extensión que todavía
  estaba trabajando, y eso rompía la consulta. Ahora solo suelta los que
  llevan un rato sin usarse.
- **Y se acabó el ir y venir**: soltaba un motor cada dos segundos y lo volvía
  a levantar enseguida, y cada vez que se levanta hay que volver a leer 148 KB
  de código. Buena parte de la lentitud era eso.

### 📺 El televisor

- **El destacado de Inicio ya llena su tarjeta entera.** Quedaba la imagen
  arriba y un hueco debajo.
- **Los botones del menú lateral son más grandes y con más aire entre ellos**,
  y al llegar con el mando ya no se les dibuja el recuadro rosado alrededor:
  queda solo el resplandor, limpio.
