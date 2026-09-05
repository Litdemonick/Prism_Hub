## PrismHub v1.0.101 — Encontrado: por qué la selección se bajaba sola

<!-- solo-plataforma: androidtv -->

> 📺 **Esta versión es solo para televisor.** Windows, Linux, teléfono y
> tablet siguen en la 1.0.97: nada de lo que cambia acá los toca, así que no
> tiene sentido hacerlos actualizar.

> ⚠️ **La app sigue en mantenimiento general.** Se la sigue reestructurando por
> dentro, así que es posible que te cruces con fallos o con cosas a medio
> terminar. Si encontrás algo roto, reportalo desde Ajustes → Reportar.

### 📺 Android TV

- **La selección ya no se va bajando de fila sola al insistir con la
  derecha.** Es el fallo que más veces volvió, y hasta ahora se venía
  arreglando a ciegas: el comportamiento del mando no se podía comprobar
  sin un televisor delante. Ahora sí se puede, y eso cambió el
  diagnóstico por completo.

  Los topes de la fila estaban **bien**. El que fallaba era el mecanismo
  que rescata el foco cuando se pierde: al desplazarse, la lista destruye
  la tarjeta que tenía la selección, y ahí el rescate buscaba "el
  siguiente enfocable" — que en orden de lectura es la **primera tarjeta de
  la fila de abajo**. De ahí que insistir con la derecha fuera bajando fila
  por fila.

  Ahora se recuerdan los últimos sitios donde estuvo la selección y se
  vuelve al más reciente que siga existiendo: la tarjeta de al lado, en la
  misma fila. Quedan siete casos cubiertos por pruebas automáticas, así
  que este fallo no puede volver sin que se note antes de publicar.

- **Aire alrededor de las tarjetas, para que el marco de foco no se
  corte.** Reportado en los cuatro lados: la primera tarjeta de cada fila
  contra el panel de categorías, la última contra el borde derecho, y las
  de arriba y abajo contra el recorte de la lista. El marco no se dibuja
  dentro de la tarjeta sino por fuera, con un resplandor todavía más
  ancho, así que donde el contenido llegaba justo al filo quedaba mordido.
  Ahora el contenido entero tiene margen propio, en vez de parches por
  tarjeta que además dejaban el destacado desalineado con las filas de
  abajo.
