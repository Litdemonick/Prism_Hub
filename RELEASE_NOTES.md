## PrismHub v1.0.104 — El movimiento dentro de una fila lo decide la app

<!-- solo-plataforma: androidtv -->

> 📺 **Esta versión es solo para televisor.** Windows, Linux, teléfono y
> tablet siguen en la 1.0.97: nada de lo que cambia acá los toca, así que no
> tiene sentido hacerlos actualizar.

> ⚠️ **La app sigue en mantenimiento general.** Se la sigue reestructurando por
> dentro, así que es posible que te cruces con fallos o con cosas a medio
> terminar. Si encontrás algo roto, reportalo desde Ajustes → Reportar.

### 📺 Android TV

- **Al llegar al final de una fila, ya no se mueve nada: ni la selección ni
  la pantalla.** El arreglo anterior dejaba que el sistema hiciera el salto
  y después lo deshacía, y eso no alcanzaba por dos motivos.

  Primero, cuando el sistema salta, antes **desplaza la pantalla** para
  revelar el destino — devolver la selección a su sitio no deshace ese
  desplazamiento. Es el "la selección se queda quieta pero se mueven las
  tarjetas de abajo, como si moviera todo alrededor".

  Y segundo, deshacerlo dependía de ganarle una carrera al propio sistema,
  que en un televisor modesto no se gana siempre. De ahí que el mismo caso
  a veces se viera bien y a veces no.

  Ahora, dentro de una fila, el movimiento no se delega: se busca la
  tarjeta de al lado —la que pertenece a la misma fila y está en el mismo
  renglón— y se va ahí. Si no hay ninguna, no se hace nada en absoluto.

- **Desde la primera categoría del panel, la flecha arriba vuelve a llegar
  a los botones de arriba** (buscar, extensiones, favoritos, historial,
  ajustes). Se había roto en la versión anterior.

Las pruebas automáticas de navegación son ahora 16 casos, y comprueban
también que al toparse contra el final de una fila las tarjetas de abajo
no se muevan ni un píxel.
