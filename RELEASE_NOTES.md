## PrismHub v1.0.91 — El mando va a donde uno lo manda

> ⚠️ **La app sigue en mantenimiento general.** Se la sigue reestructurando por
> dentro, así que es posible que te cruces con fallos o con cosas a medio
> terminar. Si encontrás algo roto, reportalo desde Ajustes → Reportar.

### 📺 Android TV — la navegación con el mando

Estaban pasando tres cosas distintas a la vez, y por eso los intentos
anteriores no terminaban de arreglarlo.

- **Ir a la derecha ya no baja la lista.** Cada flecha mueve únicamente su
  eje: recorrer una fila de costado deja la pantalla exactamente donde
  estaba.
- **La cámara solo se mueve cuando hace falta.** Antes reposicionaba la lista
  en cada paso, incluso sobre una tarjeta que ya se veía entera — eso era el
  salto. Ahora, si lo que enfocás ya está a la vista, no se mueve nada; y
  cuando sí hace falta, avanza una tarjeta por vez dejando asomar la
  siguiente.
- **Se acabó el rebote al bajar.** Bajar y que la selección se volviera para
  arriba sola era una pulsación que provocaba dos movimientos de foco, y el
  segundo perdía la dirección por el camino.

### 🧭 Android TV — cada zona con sus límites

- **Estando en el panel de categorías, bajar se queda en el panel.** Ya no se
  escapa al contenido.
- **Estando en una zona, bajar se queda en la zona.** Ya no termina metido en
  el panel de la izquierda.
- Se cambia de una a otra yendo a los costados, que es un movimiento
  deliberado. Antes esto se decidía midiendo si el foco caía cerca del borde
  izquierdo, y esa cuenta solo acertaba con el panel plegado — justo lo
  contrario de cuando estás dentro de él, que es cuando se despliega.

### 📖 En el lector

- **La flechita que oculta las burbujas ahora recuerda cómo la dejaste.**
  Ocultarlas y cambiar de capítulo, saltar a otra obra o salir y volver a
  entrar las traía de vuelta desplegadas.
