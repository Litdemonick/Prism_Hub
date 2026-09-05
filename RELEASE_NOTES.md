## PrismHub v1.0.102 — El panel de categorías se bloqueaba a sí mismo

<!-- solo-plataforma: androidtv -->

> 📺 **Esta versión es solo para televisor.** Windows, Linux, teléfono y
> tablet siguen en la 1.0.97: nada de lo que cambia acá los toca, así que no
> tiene sentido hacerlos actualizar.

> ⚠️ **La app sigue en mantenimiento general.** Se la sigue reestructurando por
> dentro, así que es posible que te cruces con fallos o con cosas a medio
> terminar. Si encontrás algo roto, reportalo desde Ajustes → Reportar.

### 📺 Android TV

- **El panel de categorías ya no queda abierto ni bloquea su propia
  entrada.** Los dos fallos reportados juntos —"queda abierto todo el rato"
  y "no me deja ni entrar"— resultaron ser el mismo, y se
  retroalimentaban:

  Para mover la selección a la izquierda, Flutter exige que el centro del
  destino quede más a la izquierda que el borde de donde venís. Con el
  panel desplegado sus botones son anchos, así que su centro cae a la
  derecha del borde de las tarjetas y deja de contar como destino válido:
  el panel se vuelve inalcanzable. Y como no se puede entrar, nunca recibe
  la selección; como nunca la recibe, nunca se entera de que tiene que
  contraerse; y desplegado sigue siendo inalcanzable.

  El panel arrancaba desplegado dando por sentado que la selección inicial
  iba a caer ahí, y eso puede no pasar. Ahora lo comprueba contra la
  realidad en vez de darlo por hecho. De paso se arregla el otro síntoma:
  abierto tapaba la primera tarjeta de cada fila, que es el "se corta a la
  izquierda" de las fotos.

- **Aire propio para el destacado de arriba.** Su borde de selección lo
  dibuja el carrusel al ras de la tarjeta, sin margen de por medio, así
  que se cortaba contra el borde de arriba y el de la derecha.

- **Las pruebas de navegación ahora corren en modo televisor.** Estaban
  corriendo con la detección de TV apagada y con widgets de prueba en vez
  de las tarjetas reales — o sea, comprobando una versión de la app que no
  es la que corre en el televisor. Con eso corregido son ocho casos, y son
  los que encontraron este fallo.
