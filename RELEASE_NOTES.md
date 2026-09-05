## PrismHub v1.0.92 — Sin rayas en la lectura, y el actualizador que se deja usar

> ⚠️ **La app sigue en mantenimiento general.** Se la sigue reestructurando por
> dentro, así que es posible que te cruces con fallos o con cosas a medio
> terminar. Si encontrás algo roto, reportalo desde Ajustes → Reportar.

### 📖 La rayita oscura entre páginas

- **Se van las líneas negras que cruzaban la lectura** en la cascada, en
  sitios donde la imagen original no tiene nada.

  Cada página se muestra al ancho de la pantalla y su alto sale de la
  proporción de la imagen, o sea un número con decimales. Puestas una debajo
  de la otra, el borde entre dos caía a mitad de un píxel de la pantalla: ese
  píxel no lo pintaba entera ninguna de las dos y por el hueco se asomaba el
  fondo oscuro del lector. Ahora cada página se dibuja tapando ese píxel que
  comparte con la de abajo, sin cambiar nada de lo que ocupa.

  Vale para PC y Android, y para cualquier extensión de lectura.

### ⬆️ El actualizador

- **En el televisor ya se ve qué botón está elegido.** El principal viene
  relleno del color de acento y el secundario se pintaba de ese mismo color
  al enfocarse, así que con el mando los dos se veían igual. Ahora el foco
  invierte el botón —fondo claro, texto oscuro y un aro alrededor—, así que
  el elegido y el otro nunca se parecen. En teléfono y en escritorio, donde
  hay dedo y cursor, los botones quedan como estaban.
- **Si no querés actualizar, no se insiste.** Al elegir "Ahora no" se te
  recuerda que podés hacerlo cuando quieras desde Ajustes → Buscar
  actualizaciones, y por qué conviene: cada versión trae arreglos y las
  extensiones dependen de eso.
- **El botón ahora dice "Instalar la nueva versión"**, que es lo que hace.
- **Y en el televisor que bajaba la actualización sin abrir el instalador**:
  se preguntaba a ciegas, y en algunas cajas de Android TV la primera forma
  de pedirlo se acepta sin protestar y no abre nada, así que la segunda no
  llegaba a probarse nunca. Ahora se consulta antes quién puede atenderla.

### 📺 Android TV — la selección

- **La selección ya no desaparece al llegar al último card de una fila.**
  Al frenar ahí, el foco pasaba un instante por una tarjeta fuera de la
  vista y podía quedarse sin nadie enfocado. La flecha siguiente entonces
  buscaba el primer enfocable que hubiera, y eso se veía como que la derecha
  bajaba sola por las tarjetas de abajo. Las dos cosas eran el mismo fallo.
