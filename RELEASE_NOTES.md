## PrismHub v1.0.112 — Las tarjetas entran enteras, y el fondo es el mismo en todas partes

<!-- solo-plataforma: androidtv -->

> 📺 **Esta versión es solo para televisor.** Windows, Linux, teléfono y
> tablet siguen en la 1.0.97: nada de lo que cambia acá los toca, así que no
> tiene sentido hacerlos actualizar.

> ⚠️ **La app sigue en mantenimiento general.** Se la sigue reestructurando por
> dentro, así que es posible que te cruces con fallos o con cosas a medio
> terminar. Si encontrás algo roto, reportalo desde Ajustes → Reportar.

### 📺 Android TV

- **Las tarjetas de la primera fila ya no salen cortadas por abajo, y esta
  vez de raíz.** El tamaño del póster salía solo del ancho de la pantalla:
  se elegía lo que entraba a lo ancho, sin preguntarse si entraba a lo
  alto. Por eso cada arreglo aguantaba hasta que cambiaba algo del reparto
  de arriba. Ahora la cuenta mira cuánto alto queda libre debajo del
  destacado y ajusta el póster a eso — si el destacado crece, los pósters
  se achican lo justo para seguir entrando enteros.

- **El fondo de "ver todo" de una extensión, igual que el resto.** Era la
  única pantalla de televisor sin el gris carbón: armaba su fondo con un
  color plano y encima el panel de la derecha traía otro, así que se veían
  dos tonos partidos por la mitad.

- **El difuminado de los bordes, arreglado.** Estaba medido en porcentaje
  del ancho de la fila: en Inicio son unos pocos puntos y se ve como un
  borde suave, pero en el panel angosto del buscador ese mismo porcentaje
  se comía una tarjeta entera y quedaba como una sombra plana encima. Ahora
  es una medida fija y se ve igual en cualquier fila.

- **Aire entre las opciones del filtro**, que el marco de la enfocada
  llegaba pisando la fila de abajo.

- **El panel de categorías ya no salta al abrir la app.** La comprobación
  del primer cuadro corría cuando todavía no había nada seleccionado, así
  que el panel se contraía y volvía a abrirse un instante después.
