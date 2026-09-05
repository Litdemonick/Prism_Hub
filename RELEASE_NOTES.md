## PrismHub v1.0.103 — Los topes del mando nunca se estaban ejecutando

<!-- solo-plataforma: androidtv -->

> 📺 **Esta versión es solo para televisor.** Windows, Linux, teléfono y
> tablet siguen en la 1.0.97: nada de lo que cambia acá los toca, así que no
> tiene sentido hacerlos actualizar.

> ⚠️ **La app sigue en mantenimiento general.** Se la sigue reestructurando por
> dentro, así que es posible que te cruces con fallos o con cosas a medio
> terminar. Si encontrás algo roto, reportalo desde Ajustes → Reportar.

### 📺 Android TV

- **La selección ya no se va bajando de fila al insistir con la derecha.**
  Y esta vez se encontró el motivo de fondo, que explica por qué ninguno de
  los arreglos anteriores cambiaba nada.

  Flutter no mueve la selección en el momento en que se aprieta la flecha:
  anota el pedido y lo aplica un instante después. El código que pone los
  topes preguntaba "¿a dónde se movió?" **antes de que se hubiera movido**,
  así que siempre recibía la misma respuesta —"a ningún lado"— y se iba sin
  revisar nada. Los topes existían pero no llegaban a ejecutarse nunca.

  Ahora la revisión espera a que el movimiento esté aplicado. Recorrer una
  fila de quince tarjetas y seguir apretando la derecha se queda clavado en
  la última, como corresponde.

- **Al deshacer un movimiento, la selección vuelve aunque su tarjeta se
  haya reciclado.** Al desplazarse, la lista destruye lo que sale de la
  vista, y a veces eso incluía la tarjeta a la que había que volver.

- **Se va el esqueleto de bloques grises.** En Inicio, en las zonas y en
  cada fila, mientras carga se ve solo el giro en el centro sobre el fondo
  limpio; las tarjetas aparecen cuando están de verdad.

- **Subir y bajar dentro del panel de categorías ya no saca de ahí**, y la
  izquierda llega al panel desde cualquier fila.

Las pruebas automáticas de navegación pasan de ocho a catorce casos.
