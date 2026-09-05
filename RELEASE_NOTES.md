## PrismHub v1.0.94 — El scroll de las filas de extensiones

> ⚠️ **La app sigue en mantenimiento general.** Se la sigue reestructurando por
> dentro, así que es posible que te cruces con fallos o con cosas a medio
> terminar. Si encontrás algo roto, reportalo desde Ajustes → Reportar.

### 📺 Android TV

- **La lista ya no se vuelve arriba sola** al moverse por las filas de las
  extensiones.

  Una tarjeta vive dentro de una fila que se desliza de costado, y esa fila
  dentro de la lista que se desliza hacia abajo: son dos desplazamientos, uno
  adentro del otro. Al acomodar el de la lista se usaban medidas tomadas
  contra el de la fila —que para ella no significan nada—, y el destino que
  salía de ahí terminaba recortado contra el principio de la lista. De ahí el
  salto hasta arriba. Ahora cada uno se acomoda con lo suyo: para la lista, lo
  que tiene que entrar en pantalla es la fila entera, no la tarjeta suelta.

- **La selección ya no se queda invisible.** Cuando el desplazamiento sacaba
  de la vista la tarjeta seleccionada, la lista la reciclaba y la selección
  desaparecía hasta que se apretara otra flecha. Ahora vuelve al instante, y
  al sitio donde estaba — no al primero que aparezca, que era lo que la hacía
  saltar lejos.
