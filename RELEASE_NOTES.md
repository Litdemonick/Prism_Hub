## PrismHub v1.0.59 — Cada plataforma con el motor que le corresponde

> 🎬 **Se acabó elegir motor de vídeo.** En Android —teléfono y televisor— va
> **ExoPlayer**, el del sistema. En PC y Linux va **mpv**. Y si alguna fuente
> se le resiste a ExoPlayer, la app cae a mpv sola sin que te enteres.

> ⚠️ **La app sigue en mantenimiento general.** Se la sigue reestructurando
> por dentro, así que es posible que te cruces con fallos o con cosas a medio
> terminar. Si encontrás algo roto, reportalo desde Ajustes → Reportar.

### 🎬 El motor, decidido por plataforma

- **Por qué ExoPlayer en Android**: dibuja en una capa nativa del sistema, así
  que el vídeo y la interfaz van por carriles separados — la interfaz se
  redibuja solo cuando algo cambia y el vídeo avanza a su ritmo. Con el camino
  anterior compartían carril: **cada cuadro de vídeo era una pasada de dibujado
  de toda la interfaz**. Es lo mismo que hacen las apps de vídeo del sistema.
- **Y ExoPlayer ya reconoce las listas del relay.** Fallaban todas con «Source
  error»: el relay servía sus direcciones sin extensión, y ExoPlayer decide qué
  es cada cosa por ahí — tomaba una lista de reproducción por un archivo de
  vídeo y se caía al leerla.
- **Con reserva automática**: si una fuente no abre con ExoPlayer, se abre con
  mpv y queda anotado. Nadie se queda sin ver nada.

### 📡 Ver el registro de un televisor

- **Se recuerdan los televisores**, con la fecha y hora en que se los vio. Si
  uno deja de compartir —o **si la app se le cayó**— sigue en la lista, aparte
  y marcado como sin conexión. Antes desaparecía como si nunca hubiera estado.
- Se ven **enseguida al entrar**, antes de que termine la búsqueda.
- **La barra de desplazamiento** ya no se agranda y achica sola, y **el
  refresco ya no te devuelve arriba**: sigue el final, que es donde está lo
  último, y solo si ya estabas abajo.
- El registro va dentro de un panel con contorno, y podés **guardarlo o
  compartirlo** desde el teléfono o el PC.

### 🔎 Diagnóstico

- **Los cuadros lentos ahora dicen en qué pantalla pasaron.** «build=490ms» no
  decía si fue el catálogo, la ficha o el reproductor.
- El registro dice **cuándo es el primer arranque después de actualizar**, con
  la versión de la que venías.
