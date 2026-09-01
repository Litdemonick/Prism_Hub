## PrismHub v1.0.69 — La causa de los cierres, encontrada en el registro

> ⚠️ **La app sigue en mantenimiento general.** Se la sigue reestructurando por
> dentro, así que es posible que te cruces con fallos o con cosas a medio
> terminar. Si encontrás algo roto, reportalo desde Ajustes → Reportar.

### ⚡ Por qué se cerraba sola en televisores modestos

El registro de un televisor de 893 MB lo dijo con todas las letras: **doce
motores de extensión vivos a la vez** justo antes de que el sistema matara la
app. Cada extensión que usás levanta su propio motor de JavaScript, y hasta
ahora solo se soltaban después de un rato sin usarse — así que abrir el Inicio
y pasear por las zonas los iba acumulando todos.

- **Ahora hay un tope**: en los aparatos más modestos se mantienen vivos como
  mucho tres, y se suelta el que hace más rato que no se usa. Ninguno que esté
  trabajando.
- **El Inicio ya no levanta cinco de golpe** al abrirse, sino dos.
- **Las portadas ocupan casi la mitad**: se descargan a un tamaño un poco menor,
  imperceptible a la distancia a la que se mira un televisor, y así entran casi
  el doble sin que la app tenga que estar tirando y volviendo a pedir las mismas
  imágenes todo el rato.

### 🧾 Y ahora sí queda anotado por qué se cerró

- **Cuando la app se cierra sola, el motivo queda escrito en el registro.**
  Antes no aparecía nada: el diagnóstico se calculaba al arrancar, pero unos
  instantes *antes* de que el registro existiera, así que se escribía en el
  vacío. Justo en el caso donde más falta hace, porque un cierre por falta de
  memoria no deja ningún error que mostrar.

### 📺 El televisor

- **El resplandor de la tarjeta seleccionada ya no aparece cortado** contra el
  menú lateral.
