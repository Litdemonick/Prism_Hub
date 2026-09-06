## PrismHub v1.0.108 — Las medianas con tope, y aire para que nada se corte

<!-- solo-plataforma: androidtv -->

> 📺 **Esta versión es solo para televisor.** Windows, Linux, teléfono y
> tablet siguen en la 1.0.97: nada de lo que cambia acá los toca, así que no
> tiene sentido hacerlos actualizar.

> ⚠️ **La app sigue en mantenimiento general.** Se la sigue reestructurando por
> dentro, así que es posible que te cruces con fallos o con cosas a medio
> terminar. Si encontrás algo roto, reportalo desde Ajustes → Reportar.

### 📺 Android TV

- **Las cuatro tarjetas medianas de arriba ya frenan al final.** El
  destacado grande estaba marcado como fila y ellas no, así que seguían
  saltando abajo con la flecha derecha. Ahora esa marca viaja dentro de la
  propia fila, para que no vuelva a quedarse ninguna afuera.

- **Ya no se pierde un paso al apretar rápido.** El sistema aplica el
  cambio de selección al final del cuadro, así que manteniendo la flecha la
  tecla siguiente llegaba antes y se calculaba desde la tarjeta que ya
  habías dejado. Por eso "yendo lento" llegabas al panel y apurando no.

- **Al entrar a una zona se empieza por la primera tarjeta**, no donde
  hubiera quedado la vez anterior.

- **El buscador vuelve a ocupar toda la pantalla.** Se encogía contra el
  borde de arriba y abajo quedaba una franja muerta.

- **Aire alrededor de todo lo que se puede seleccionar.** El marco de
  selección se dibuja por fuera de la tarjeta, así que donde el contenido
  llegaba justo al filo quedaba mordido — y eso volvía una y otra vez en un
  sitio distinto: la primera de la fila, la última contra el borde derecho,
  la de arriba, la de abajo. Ahora es un mínimo con nombre que respetan
  todas las pantallas, en vez de un número puesto a mano en cada sitio.

Las pruebas automáticas de navegación son ahora 26 casos.
