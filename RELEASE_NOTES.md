## PrismHub v1.0.89 — El lector: burbujas que se leen, y "Ver detalle" que llega

> ⚠️ **La app sigue en mantenimiento general.** Se la sigue reestructurando por
> dentro, así que es posible que te cruces con fallos o con cosas a medio
> terminar. Si encontrás algo roto, reportalo desde Ajustes → Reportar.

### 🫧 Burbujas de "Continuar leyendo"

- **Tocar una burbuja va directo a esa obra.** Ya no hay paso intermedio.
- **Manteniéndola presionada** se agranda en el **centro del lector**, con la
  portada y el título completos, para mirar antes de decidir: desde ahí,
  tocarla confirma y tocar en cualquier otro lado cierra sin hacer nada.
  Mientras esa vista está abierta, el resto de la interfaz se esconde sola.
- **El título ya se lee.** Antes se achicaba hasta entrar en un renglón, así
  que cuanto más largo el nombre, más diminuto se veía. Ahora la letra mide
  siempre lo mismo y lo que sobra se corta con puntos suspensivos.
- **Y ya no desaparece sobre una página blanca**: va sobre un fondo oscuro
  sólido, en la fila y en la vista agrandada.
- **Se van las rayas amarillas debajo del texto.** No eran un corte de texto,
  como parecía: era el aviso que Flutter le pone al texto que dibuja fuera de
  cierto contexto. Se veía solo en Android.
- Las burbujas son **más grandes** en las dos plataformas, y la fila va de
  punta a punta de la pantalla.
- **La flechita de ocultarlas** se centra contra todo el lector (antes quedaba
  corrida hacia un lado) y, como las de correr la fila, ahora tiene fondo
  sólido: sobre el fondo oscuro del lector eran negro sobre negro.
- En PC, esas flechitas **ya no quedan encima de la barra de desplazamiento**.
- **Las portadas dejan de recargarse solas.** La fila se desarmaba entera cada
  vez que el panel de controles se ocultaba —cosa que pasa con solo
  desplazarse— y al volver, la portada tenía que pedirse de nuevo. Ahora se
  queda cargada.

### 🐛 Otros arreglos del lector

- **"Ver detalle" ya no te deja en la Biblioteca.** Cerraba el lector y, a
  veces, la ficha nunca llegaba a abrirse. Saltando de una obra a otra desde
  una burbuja fallaba siempre.
- **Los botones de capítulo siguiente/anterior** del final de la cascada
  dejan de quedar tapados por la franja de abajo: ahora el hueco que se les
  reserva se mide de verdad, en vez de ser un número fijo que se quedaba
  corto según el aparato o el tamaño de letra.
- **Los ajustes del lector (la tuerca) se pueden subir hasta arriba.** En
  horizontal la hoja quedaba cortada a media pantalla y no había forma de
  llegar a las opciones de abajo.
- **La lista de capítulos en PC ya no se pasa de la ventana** con una obra
  larga: se desplaza por dentro.
