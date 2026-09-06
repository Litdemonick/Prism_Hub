## PrismHub v1.0.114 — Subir y bajar ya no mueve las filas ni salta de columna

<!-- solo-plataforma: androidtv -->

> 📺 **Esta versión es solo para televisor.** Windows, Linux, teléfono y
> tablet siguen en la 1.0.97: nada de lo que cambia acá los toca, así que no
> tiene sentido hacerlos actualizar.

> ⚠️ **La app sigue en mantenimiento general.** Se la sigue reestructurando por
> dentro, así que es posible que te cruces con fallos o con cosas a medio
> terminar. Si encontrás algo roto, reportalo desde Ajustes → Reportar.

### 📺 Android TV

- **Las filas ya no se descentran al subir o bajar.** Al revelar la tarjeta
  de destino, el sistema desplazaba esa fila de costado — así que subiendo
  y bajando las filas se iban corriendo solas. Ahora la tarjeta de destino
  se elige directamente: la de la fila de al lado que está más alineada, y
  nada se mueve de costado.

- **Un salto vertical ya no cambia de columna.** En Extensiones instaladas,
  al llegar al final de la lista de la derecha, lo más cercano hacia arriba
  era un botón de la columna izquierda, y la selección se iba ahí
  arrastrando su barra.

- **El difuminado de los bordes, con una curva suave.** Subía de golpe y
  sobre una portada clara se leía como una banda oscura pegada al borde en
  vez de un degradado.

- **El panel de categorías arranca contraído**, que abierto tapaba el
  contenido a medio dibujar mientras la app carga.

Las pruebas automáticas de navegación son ahora 31 casos.
