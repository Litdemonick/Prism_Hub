## PrismHub v1.0.107 — Topes también a la izquierda, en el panel y arriba

<!-- solo-plataforma: androidtv -->

> 📺 **Esta versión es solo para televisor.** Windows, Linux, teléfono y
> tablet siguen en la 1.0.97: nada de lo que cambia acá los toca, así que no
> tiene sentido hacerlos actualizar.

> ⚠️ **La app sigue en mantenimiento general.** Se la sigue reestructurando por
> dentro, así que es posible que te cruces con fallos o con cosas a medio
> terminar. Si encontrás algo roto, reportalo desde Ajustes → Reportar.

### 📺 Android TV

Tres sitios donde la selección todavía se movía sola, y los tres eran el
mismo agujero que ya se había tapado del lado derecho: se dejaba que el
sistema decidiera el salto, y ese intento **ya desplaza la pantalla**
aunque la selección después vuelva a su sitio.

- **La izquierda al principio de una fila** ahora entra al panel de
  categorías directo, por el botón que esté a la misma altura de donde
  venías — así no se pierde el sitio. Nada se desplaza.

- **Dentro del panel, insistir con la izquierda ya no saca de ahí.** A la
  izquierda del panel no hay nada, pero el sistema enganchaba una tarjeta
  del contenido y arrastraba la zona entera hacia abajo.

- **Los destacados de arriba tienen los mismos topes que las filas.** Los
  dos grandes y las medianas no son filas que se desplazan sino bloques
  fijos, así que quedaban fuera del mecanismo que ya frenaba a las filas de
  pósters.

Y un efecto secundario que cierra un fallo viejo: con el panel desplegado
ahora también se puede entrar. Antes no —sus botones quedaban descartados
por anchos— y eso se mordía la cola: sin poder entrar nunca recibía la
selección, sin selección no se enteraba de que tenía que contraerse, y
desplegado seguía siendo inalcanzable.

Más aire contra el borde derecho, donde el marco de selección se veía
cortado.

Las pruebas automáticas de navegación son ahora 25 casos.
