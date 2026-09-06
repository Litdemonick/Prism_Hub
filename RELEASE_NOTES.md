## PrismHub v1.0.116 — Fluidez al recorrer con el mando, y el actualizador que sí instala

<!-- solo-plataforma: androidtv -->

> 📺 **Esta versión es solo para televisor.** Windows, Linux, teléfono y
> tablet siguen en la 1.0.97 — salvo el arreglo del actualizador, que les
> llega en la próxima versión de cada uno.

> ⚠️ **La app sigue en mantenimiento general.** Se la sigue reestructurando por
> dentro, así que es posible que te cruces con fallos o con cosas a medio
> terminar. Si encontrás algo roto, reportalo desde Ajustes → Reportar.

### 📺 Android TV

- **Recorrer las filas con el mando ya no se traba en televisores
  modestos.** Para saber a qué fila pertenece cada tarjeta, la app
  preguntaba de una forma que además *suscribe* a quien pregunta a los
  cambios de esa lista — y eso se hacía por cada tarjeta de la pantalla y
  en cada pulsación. El resultado era un árbol lleno de suscripciones que
  se despertaban con cada desplazamiento. Ahora la misma búsqueda se hace
  de solo lectura.

  Cuadra con lo que se veía: en el buscador, con una fila y pocas tarjetas,
  iba fluido; en Inicio, con el destacado, las medianas y una fila por
  extensión, se notaba.

### 🔄 Actualizaciones (Android y Android TV)

- **Al conceder el permiso de instalar, la instalación arranca sola.** Todo
  el proceso colgaba de un único aviso del sistema —"volviste a la app"—
  que no siempre llega: en varias cajas de televisor la pantalla de
  permisos no se abre como una ventana aparte, así que la app nunca se
  enteraba de la vuelta y había que darle a Actualizar por segunda vez.
  Ahora, además de ese aviso, el permiso se comprueba cada segundo y medio
  mientras dura la espera.
