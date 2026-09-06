## PrismHub v1.0.106 — Ajustes se navega entero, y los bordes de fila ya no se comen las tarjetas

<!-- solo-plataforma: androidtv -->

> 📺 **Esta versión es solo para televisor.** Windows, Linux, teléfono y
> tablet siguen en la 1.0.97: nada de lo que cambia acá los toca, así que no
> tiene sentido hacerlos actualizar.

> ⚠️ **La app sigue en mantenimiento general.** Se la sigue reestructurando por
> dentro, así que es posible que te cruces con fallos o con cosas a medio
> terminar. Si encontrás algo roto, reportalo desde Ajustes → Reportar.

### 📺 Android TV

- **En Ajustes ya se puede pasar a las opciones de la derecha desde
  cualquier categoría.** Eran dos fallos encima del mismo síntoma. Por un
  lado, la regla que impide que la selección se escape de una fila de
  tarjetas se estaba aplicando también acá, donde no hay filas. Por el
  otro, el recorrido busca lo más cercano *a la misma altura*, así que
  estando en la última categoría —con el botón allá arriba— no encontraba
  nada.

  Ahora, al cruzar hacia la derecha se entra por **la primera opción** de
  esa columna, vengas de la altura que vengas. Vale igual para el
  repositorio de extensiones y el historial, que tienen la misma forma.

- **La pantalla ya no corta la fila por arriba al subir.** Lo que se traía
  a la vista era la tira de tarjetas, y el nombre de la extensión vive
  encima de ella: con la tira entrando justa, la cuenta decía "ya se ve" y
  la fila aparecía sin su título.

- **El difuminado de los bordes, ahora también en Películas, Series y
  Anime.** Estaba solo en Inicio, así que en las zonas la tarjeta del borde
  terminaba en un filo recto.

- **Y ese difuminado dejó de atenuar donde no hay nada más.** Cada lado se
  desvanece solo si por ahí sigue habiendo fila: la primera tarjeta al
  principio y la última al final se ven nítidas, con su marco entero.

Las pruebas automáticas de navegación son ahora 21 casos.
