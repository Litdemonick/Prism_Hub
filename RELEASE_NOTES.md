## PrismHub v1.0.110 — El buscador: bordes con aire, difuminado y teclado centrado

<!-- solo-plataforma: androidtv -->

> 📺 **Esta versión es solo para televisor.** Windows, Linux, teléfono y
> tablet siguen en la 1.0.97: nada de lo que cambia acá los toca, así que no
> tiene sentido hacerlos actualizar.

> ⚠️ **La app sigue en mantenimiento general.** Se la sigue reestructurando por
> dentro, así que es posible que te cruces con fallos o con cosas a medio
> terminar. Si encontrás algo roto, reportalo desde Ajustes → Reportar.

### 📺 Android TV

- **En el buscador, el marco de selección ya no se corta.** La fila de
  resultados iba sin nada de lo que el resto de las filas ya tenía:
  recortaba contra sus propios bordes y la primera tarjeta arrancaba pegada
  al filo, así que el marco quedaba mordido arriba, abajo y a la izquierda.

- **Difuminado en los bordes de esa fila**, igual que en Inicio y las
  zonas: la tarjeta del costado se atenúa en vez de cortarse en seco, y
  solo del lado por donde de verdad queda más.

- **La columna del teclado, centrada.** Arrancaba pegada arriba y dejaba
  media pantalla vacía debajo.

- **La flecha izquierda vuelve al teclado.** El tope de fila buscaba el
  panel de categorías para salir por la izquierda, y el buscador no tiene
  panel: la tecla se quedaba muerta.

Las pruebas automáticas de navegación son ahora 28 casos.
