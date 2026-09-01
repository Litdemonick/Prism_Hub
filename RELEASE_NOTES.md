## PrismHub v1.0.72 — La app arranca liviana

> ⚠️ **La app sigue en mantenimiento general.** Se la sigue reestructurando por
> dentro, así que es posible que te cruces con fallos o con cosas a medio
> terminar. Si encontrás algo roto, reportalo desde Ajustes → Reportar.

### ⚡ Por qué se ponía lenta y se cerraba

El registro del televisor dejó ver que **el sistema ya pedía memoria a los
siete segundos de abrir la app**, sin que nadie hubiera tocado nada. El motivo:
la app armaba **ocho pantallas de una sola vez** al abrirse — el Inicio, los
cuatro catálogos de zona, la Biblioteca, Extensiones y Ajustes. Y cada catálogo
de zona le pedía contenido a todas sus extensiones apenas nacía.

- **Ahora cada pantalla se arma la primera vez que entrás.** Volver a una que ya
  visitaste la encuentra igual que la dejaste.
- **Y en los televisores más modestos se suelta la anterior** al cambiar, para
  devolverle esa memoria al sistema. Volver es instantáneo: usa lo que ya está
  cargado, sin pedir nada por internet otra vez.
- **Las zonas piden de a una extensión.** Antes, entrar a Películas le pedía
  contenido a las diez extensiones a la vez. Ahora cada fila pide lo suyo cuando
  te vas acercando a ella — lo que no se mira, no se pide.
- **Y cuando el sistema avisa que le falta memoria**, la app suelta lo que no
  estás mirando en vez de aguantarlo.
