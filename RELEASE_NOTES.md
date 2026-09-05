## PrismHub v1.0.95 — Al final de una fila, el mando se queda quieto

> ⚠️ **La app sigue en mantenimiento general.** Se la sigue reestructurando por
> dentro, así que es posible que te cruces con fallos o con cosas a medio
> terminar. Si encontrás algo roto, reportalo desde Ajustes → Reportar.

### 📺 Android TV

- **Al llegar al final de una fila y seguir apretando derecha, la selección
  se queda quieta** en vez de desaparecer.

  Las comprobaciones que ya había medían si el destino se PARECÍA a un
  vecino de la misma fila —altura similar—, y eso funciona casi siempre.
  Pero justo en el borde de verdad, sin ningún vecino real a la derecha,
  podía engancharse a cualquier otro foco de la pantalla que por pura
  coincidencia tuviera una altura parecida. Eso pasaba las comprobaciones
  sin ser un vecino de fila, y como no tiene la marca visual propia de las
  tarjetas, desde el sillón se veía como que la selección desaparecía.

  Ahora se confirma algo que no admite coincidencias: si los dos widgets
  cuelgan del mismo scroll horizontal, el de la fila en la que se está. Un
  vecino de verdad siempre lo comparte; cualquier otra cosa no puede
  compartirlo por casualidad.
