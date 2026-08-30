## PrismHub v1.0.60 — Vuelven los subtítulos en Android

> 🔤 **Si estás en Android y no veías subtítulos, era esto.** La 1.0.59 cambió
> el motor de vídeo de Android y con ese motor los subtítulos no llegaban a
> pantalla: la app los descargaba y no los mostraba. Tampoco se podía elegir
> pista de audio. Volvimos al motor de siempre y las dos cosas andan otra vez.

> ⚠️ **La app sigue en mantenimiento general.** Se la sigue reestructurando por
> dentro, así que es posible que te cruces con fallos o con cosas a medio
> terminar. Si encontrás algo roto, reportalo desde Ajustes → Reportar.

### 🔤 El motor de vídeo, uno solo otra vez

- **Android vuelve a mpv**, el mismo que usan Windows y Linux. Con eso vuelven
  los **subtítulos** —los del archivo y los que trae la extensión aparte— y la
  **elección de pista de audio**, que en la 1.0.59 no estaban.
- **Se fue el selector de motor de Ajustes.** No queda nada que elegir: hay uno
  y es el mismo en todas las plataformas.

El cambio de la 1.0.59 buscaba sacar el vídeo del dibujado de la interfaz, y en
eso funcionó: medido en un teléfono, el tiempo de dibujar cada cuadro bajó de
unos 140 ms a menos de 40. Pero se llevó puestas demasiadas cosas que dependían
del motor anterior, y aparecían de a una. Preferimos volver a lo probado y
retomarlo con más cuidado.

### 🐞 Correcciones

- **El recuadro rojo de error encima del vídeo, en el teléfono.** Aparecía al
  abrir el reproductor y se redibujaba en cada cuadro. Era el control de volumen
  pidiéndole al sistema que vigilara algo que no cambiaba nunca.
- **La rueda de carga y el botón de pausa ya no se dibujan uno encima del otro.**
  Los dos van al centro exacto de la pantalla y ninguno miraba al otro.
- **Mientras dice «Obteniendo enlace…» ya no gira nada más.** El cartel del
  centro y el botón de abajo daban la misma noticia dos veces, a destiempo.
- **Al salir del reproductor o cambiar de servidor, el vídeo se detiene de
  verdad.** Había caminos por los que seguía sonando.

### ⚡ Empieza antes

- **Cuando el servidor tiene varios nodos y algunos están caídos**, ahora se
  prueban solapados en vez de uno detrás de otro. Antes, a cada nodo muerto se
  le esperaban ocho segundos: con cinco caídos seguidos eran cuarenta segundos
  mirando una rueda para terminar bajando de uno que contestaba en dos.
- No se descarga nada dos veces: se suma otro nodo solo mientras ninguno dé
  señales de vida, y en cuanto uno empieza a mandar datos se lo espera a él.

### 🔎 Diagnóstico

Para poder arreglar lo que falla en televisores sin ir a ciegas:

- **Se mide el desfase entre el audio y el vídeo.** Es el reporte que más se
  repite en televisores y hasta ahora se hablaba de él sin un número. Ahora el
  registro dice cuántos milisegundos, hacia qué lado, con qué códec, si está
  decodificando por hardware y **por dónde sale el audio** —no es lo mismo el
  altavoz del televisor que una barra por HDMI, que suma su propio retardo—.
- **Los errores dicen dónde pasaron.** Antes, en la app compilada, quedaban
  como «Instance of FlutterErrorDetails» y había que adivinar.
- **Los cuadros lentos dicen en qué pantalla ocurrieron.** El dato estaba
  puesto pero no salía nunca en Android.
