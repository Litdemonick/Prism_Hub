## PrismHub v1.0.113 — La izquierda rápida, y el panel quieto al arrancar

<!-- solo-plataforma: androidtv -->

> 📺 **Esta versión es solo para televisor.** Windows, Linux, teléfono y
> tablet siguen en la 1.0.97: nada de lo que cambia acá los toca, así que no
> tiene sentido hacerlos actualizar.

> ⚠️ **La app sigue en mantenimiento general.** Se la sigue reestructurando por
> dentro, así que es posible que te cruces con fallos o con cosas a medio
> terminar. Si encontrás algo roto, reportalo desde Ajustes → Reportar.

### 📺 Android TV

- **Yendo rápido con la flecha izquierda ya no se entra al panel a mitad de
  fila.** Y esta vez con la causa real: una lista destruye las tarjetas que
  salen de la vista, así que al volver rápido las del principio todavía no
  se habían rehecho. No había vecina a la izquierda — pero tampoco era el
  principio de la fila, y eso se leía como "se acabó".

  Ahora se mira el desplazamiento de la fila, que sí sabe la verdad: si
  queda recorrido hacia ese lado, hay más tarjetas aunque no estén puestas.
  Se acerca la fila para que se construyan y la selección se queda donde
  está. Queda cubierto por una prueba automática que, sin el arreglo, falla
  en la décima pulsación.

- **El panel de categorías ya no se mueve al abrir la app.** Nace
  desplegado y se acomoda cuando se sabe dónde quedó la selección; ese
  acomodo iba animado y se veía como que el panel se movía solo justo
  mientras la app cargaba. Ahora aparece directamente donde va, y la
  animación queda para cuando se abre y se cierra con el mando.
