## PrismHub v1.0.105 — Aire para el marco al subir, y el mando queda registrado

<!-- solo-plataforma: androidtv -->

> 📺 **Esta versión es solo para televisor.** Windows, Linux, teléfono y
> tablet siguen en la 1.0.97: nada de lo que cambia acá los toca, así que no
> tiene sentido hacerlos actualizar.

> ⚠️ **La app sigue en mantenimiento general.** Se la sigue reestructurando por
> dentro, así que es posible que te cruces con fallos o con cosas a medio
> terminar. Si encontrás algo roto, reportalo desde Ajustes → Reportar.

### 📺 Android TV

- **Al subir a las tarjetas grandes, la pantalla ahora se corre lo que
  falta para que el marco se vea entero.** La cuenta que decidía si algo
  "ya se ve" miraba el rectángulo de la tarjeta, y el marco de selección no
  vive ahí dentro: se dibuja unos píxeles por fuera. Con la tarjeta pegada
  al borde, la tarjeta entraba pero el marco quedaba mordido.

- **Cada flecha del mando queda anotada en el registro.** Dice qué camino
  tomó y por qué: si se fue a la tarjeta de al lado, si era el final de la
  fila y no se movió nada, o si el movimiento se deshizo. El recorrido con
  el mando es lo que más veces volvió, y hasta ahora cada vuelta se iba en
  adivinar qué había pasado — desde el sillón solo se ve "se movió raro".
  Ahora se reproduce el fallo, se exporta el registro desde Ajustes y ahí
  está escrito.
