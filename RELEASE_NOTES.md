## PrismHub v1.0.100 — El panel izquierdo ya entra y sale sin trabarse

<!-- solo-plataforma: androidtv -->

> 📺 **Esta versión es solo para televisor.** Windows, Linux, teléfono y
> tablet siguen en la 1.0.97: nada de lo que cambia acá los toca, así que no
> tiene sentido hacerlos actualizar.

> ⚠️ **La app sigue en mantenimiento general.** Se la sigue reestructurando por
> dentro, así que es posible que te cruces con fallos o con cosas a medio
> terminar. Si encontrás algo roto, reportalo desde Ajustes → Reportar.

### 📺 Android TV

- **Entrar y salir del panel izquierdo con el mando ya no se deshace
  solo.** Estando pegado del todo a la izquierda del contenido, apretar
  izquierda no entraba al panel de categorías; y al revés, una vez adentro
  no se podía volver al contenido — el panel se quedaba desplegado, con el
  nombre de cada categoría a la vista. La causa: el chequeo que evita que
  una fila "se escape" a otra parte de la pantalla no distinguía cruzar a
  propósito hacia el panel de categorías (que no es una fila de tarjetas)
  de escaparse por error. Ahora ese cruce, en cualquiera de los dos
  sentidos, se reconoce como lo que es.

- **El indicador del carrusel ya no se sobrepone al título.** La píldora
  de puntitos que marca en qué imagen del carrusel se está, centrada y
  pegada abajo, quedaba a la misma altura que el título — que también vive
  abajo, pero a la izquierda — y con un título largo terminaba encima de
  las letras. Se movió a la esquina superior derecha, donde ningún título
  llega nunca.

- **El marco de foco del hero y las medianas ya no se corta contra el
  borde.** El secundario de arriba y la última "mediana" llegan hasta el
  borde de verdad de la pantalla — a propósito, para que las filas que se
  desplazan dejen asomar la tarjeta siguiente —, pero esos dos bloques son
  fijos, no filas: el marco rosado, que se dibuja apenas por fuera de la
  tarjeta al seleccionarla, quedaba mordido contra el filo. Ahora tienen su
  propio margen, sin tocar el de las filas de pósters.
