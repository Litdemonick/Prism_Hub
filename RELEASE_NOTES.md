## PrismHub v1.0.57 — Historial ordenado, y el registro del televisor en tu bolsillo

> 🗑️ **Ya podés borrar lo guardado**, suelto o un día entero, y las aperturas
> se agrupan por día para encontrarlas cuando se acumulan. En televisor, PC,
> teléfono y tablet.

> ⚠️ **La app sigue en mantenimiento general.** Se la sigue reestructurando
> por dentro, así que es posible que te cruces con fallos o con cosas a medio
> terminar. Si encontrás algo roto, reportalo desde Ajustes → Reportar.

### 🗂️ El historial, ordenado y limpiable

- **Agrupado por día.** Se pidió partirlo «cada diez, como subcarpetas», y el
  bloque de diez tiene un problema: no significa nada — «las diez anteriores»
  cambia de contenido cada vez que abrís la app. El día sí, y es como se busca
  de verdad: «lo de anoche», «lo del martes».
- **Borrar una apertura, o todo un día.** Pregunta antes, porque no se puede
  deshacer. La sesión de ahora nunca se toca.
- El botón va dentro de la tarjeta y no deslizando: deslizar no existe con un
  mando, y una acción que en un aparato está y en otro no hace creer que a la
  app le falta algo.

### 📱 El registro del televisor, y qué hacer con él

- **Guardalo o compartilo** desde el teléfono o el PC: en teléfono sale por el
  menú de compartir del sistema (WhatsApp, correo, lo que tengas); en
  escritorio elegís dónde guardarlo.
- El archivo **dice de qué televisor es**. Sin eso saldría afirmando que el
  registro es de tu teléfono, y quien lo recibiera buscaría el fallo en el
  aparato equivocado.
- **Botón de refrescar**, además de la actualización automática cada 5
  segundos. Y ya no se pisan entre sí.
- **Barra de desplazamiento siempre visible, ancha y que se puede arrastrar.**
  La anterior se desvanecía y en PC ni siquiera se podía agarrar.
- **Si se corta la conexión, no se borra lo que ya llegó** — que es justo lo
  que hace falta si el televisor se cayó.

### 📺 Entrar y salir del reproductor, en televisor

- **Se quedaba en negro al salir.** Al cerrar se restauraba la interfaz del
  sistema —barra de estado, barra de navegación, orientaciones— que es lógica
  de teléfono: un televisor no tiene nada de eso. Y no solo sobraba: deshacía
  el bloqueo apaisado y le pedía a Android reconfigurar la ventana justo
  mientras el reproductor soltaba su superficie de vídeo. La ventana quedaba
  sin nada que dibujar, sin ningún error de por medio.
- **Sale más rápido y con menos tirones.** También se dejó de pedir el ajuste
  de orientación en cada cuadro, y de traer el cuadro actual desde la GPU para
  la miniatura de «Continuar viendo» en aparatos modestos — costaba hasta dos
  segundos justo al cerrar **y en televisor fallaba igual** (aparece en dos
  registros de dos aparatos distintos). La tarjeta se queda con la portada.

### 🐞 Corregido

- **Ya no parpadea en blanco al entrar.** Se buscaba en la red en el mismo
  cuadro en que la pantalla entra deslizándose.
- **Ya no se come el borde del logo de PrismHub.** Se tomaba la primera línea
  como cabecera sin comprobar que lo fuera.
- **Lo que se comparte coincide con lo que ves en el televisor**: mismas
  líneas, mismo orden, mismo filtro. Antes se enviaba el archivo exportado,
  repartido en secciones — y el orden en que pasaron las cosas *es* la
  información.
- **El registro dice cuándo es el primer arranque tras actualizar**, con la
  versión de la que venías. Es justo cuando aparecen los fallos de una
  versión nueva.
