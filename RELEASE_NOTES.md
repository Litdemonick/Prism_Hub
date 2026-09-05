## PrismHub v1.0.93 — Bajar es bajar, y los ajustes dicen la verdad

> ⚠️ **La app sigue en mantenimiento general.** Se la sigue reestructurando por
> dentro, así que es posible que te cruces con fallos o con cosas a medio
> terminar. Si encontrás algo roto, reportalo desde Ajustes → Reportar.

### 📺 Android TV — bajar ya no sube

- **La flecha abajo baja.** Estaba deshaciendo movimientos perfectamente
  válidos y devolviendo la selección a la tarjeta anterior, así que bajar se
  sentía como subir.

  La comprobación que decide si un movimiento vale comparaba dos medidas
  tomadas en momentos distintos: la de origen antes de mover el foco y la de
  destino después. Entre una y otra, la lista se desplaza para traer a la
  vista lo que se acaba de enfocar, así que todo cambia de sitio en pantalla
  — y bajando, la tarjeta nueva termina dibujada más arriba de donde estaba
  la anterior. Comparadas así, un salto hacia abajo legítimo parecía ir hacia
  arriba. Ahora las dos se miden en el mismo momento.

- **Y cuando un movimiento sí se frena, la pantalla tampoco se corre.** Antes
  la selección se quedaba quieta (bien) pero la lista igual se había
  desplazado (mal), que era la otra mitad de la sensación de que se mueve
  sola.

### ⚙️ Los interruptores de Ajustes

- **Ya no mienten.** Apagar la búsqueda automática de actualizaciones se
  guardaba de verdad —al salir y volver a entrar aparecía apagada— pero en
  pantalla el interruptor seguía encendido.

  Se redibujaba antes de que el cambio llegara a guardarse, y en los ajustes
  que preguntan «¿seguro?» eso significaba dibujar con el valor viejo y no
  volver a dibujar nunca. Ahora se espera al guardado y recién ahí se
  refresca, así que lo que ves es siempre lo que está guardado. Vale para
  todos los interruptores, no solo ese.

- Con la búsqueda automática apagada, el aviso de versión nueva no aparece
  solo: se comprueba desde **Ajustes → Buscar actualizaciones**, cuando vos
  quieras.
