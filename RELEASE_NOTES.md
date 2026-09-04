## PrismHub v1.0.86 — Burbujas para cambiar de obra en el lector, y arreglos de televisor

> ⚠️ **La app sigue en mantenimiento general.** Se la sigue reestructurando por
> dentro, así que es posible que te cruces con fallos o con cosas a medio
> terminar. Si encontrás algo roto, reportalo desde Ajustes → Reportar.

### ✨ Nuevo

- **Burbujas para saltar a otra obra sin salir del lector.** Mientras leés un
  manga, manhwa o novela, podés tocar la burbuja de otra obra que tenés en
  Continuar leyendo y pasar directo a ella — el lector actual se cierra y el
  otro se abre donde habías quedado, sin volver a Inicio. No mantiene nada
  abierto en paralelo (no son pestañas de navegador): apenas se necesita
  memoria de sobra, mucho menos que tener varios lectores vivos a la vez.
  Aparece solo si tenés más de una obra en Continuar, y una flechita
  chiquita permite ocultarla por un rato sin apagar la función entera.
  **Apagada por defecto** — se activa desde Ajustes → "Burbujas de
  'Continuar leyendo' en el lector".

### 📺 Televisor

- **La navegación con el mando ya no depende de la resolución de la
  pantalla.** Reportado con detalle: al llegar al final de una fila y seguir
  apretando derecha, la selección empezaba a bajar sola; apretando abajo, a
  veces rebotaba de vuelta para arriba. Los controles que ya existían medían
  cuánto se solapan dos tarjetas contra un porcentaje fijo, pensado para una
  resolución en particular — en otra podía fallar. Ahora hay una regla que
  siempre se cumple, sin importar el tamaño de la pantalla: si apretaste
  derecha, lo que se enfoca tiene que estar más a la derecha que antes (y lo
  mismo para las otras tres flechas). Si no lo está, el salto se deshace.
- **Las tarjetas "medianas" de Inicio (las anchas, debajo del carrusel) ya
  no quedan apretadas contra el panel izquierdo.** No tenían ningún margen
  reservado antes de la primera, a diferencia de las filas de pósters; al
  ser más anchas, el marco de foco casi no tenía aire contra el rail de
  categorías.
- Revertido el fondo del panel desplegado que se había agregado en la
  1.0.85 — nació de un reporte que en realidad era sobre las tarjetas, no
  sobre el panel. Sigue transparente, como ya se había decidido antes.

### 📖 Lector

- **"Anterior"/"Siguiente" seguía cortándose** en celulares angostos de
  verdad o con la fuente del sistema agrandada. Ahora, en vez de cortar la
  palabra, se achica lo necesario para que se lea completa siempre.
- **En PC, los botones de capítulo pasan al centro de toda la barra**, no
  solo al centro del grupo de botones de la derecha.
