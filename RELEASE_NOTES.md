## PrismHub v1.0.52 — Que «Fallos» muestre fallos

> 🧹 **La zona de Fallos estaba enterrada bajo avisos que no son fallos.** En
> un registro real había catorce errores de verdad perdidos entre doscientos
> cuarenta y nueve avisos. Ahora se ven.

> ⚠️ **La app sigue en mantenimiento general.** Se la sigue reestructurando
> por dentro, así que es posible que te cruces con fallos o con cosas a medio
> terminar. Si encontrás algo roto, reportalo desde Ajustes → Reportar.

### 🧠 El aviso de memoria decía «0.0 MB» siempre

- Aparecía cientos de veces y parecía que la app no soltaba nada cuando el
  sistema pedía memoria. **Era la medición, no el comportamiento**: Flutter
  vacía él mismo la caché de imágenes *antes* de avisarle a la app, así que
  cuando la app iba a medir ya estaba vacía por definición.
- Lo que esta parte sí aporta es soltar las imágenes **en uso** —las que están
  en pantalla, las más grandes, que Flutter no toca— y los registros de
  portadas. Eso es lo que se cuenta ahora, y es un número que dice algo.
- **Y ahora la app reacciona.** Si el sistema insiste media docena de veces en
  una sesión, está diciendo con hechos que el aparato va justo *hoy* —puede
  ser un teléfono capaz con otras diez apps abiertas— así que se le baja un
  escalón al techo de imágenes para lo que queda de sesión. Un escalón y no
  más: bajarlo al mínimo cambiaría un problema de memoria por uno de fluidez.
- Los avisos llegaban de a pares porque Android manda varios niveles a la vez;
  ahora cuentan como uno solo.

### 🎯 Los botones ya no se quedan encendidos

- En la columna del televisor quedaban **varios botones marcados a la vez**, y
  con tres luces puestas no se sabe cuál se va a activar al pulsar. Por eso
  parecía que «a veces cuesta»: el mando respondía bien, lo que estaba mal era
  dónde parecía estar el foco.
- La causa: la columna cambia de largo —«volver al final» solo está cuando te
  fuiste del fondo— y al aparecer o desaparecer, cada botón heredaba el estado
  del que tenía al lado.
- Corregido también en las filas de zonas de PC y Android y en la lista del
  historial, donde hoy no se notaba pero podía aparecer en cualquier momento.

### 🧹 «Fallos» vuelve a servir

- Que el sistema pida memoria es normal —pasa cada vez que abrís otra app— y
  que la app la suelte es la app funcionando bien. Ya no figura como fallo.
- **Los tirones**: a 60 Hz pasarse de 50 ms es perder tres cuadros; molesta,
  pero pasa constantemente y no es un fallo. Ahora avisa a partir de un cuarto
  de segundo, que ya es un parpadeo que cualquiera nota.
- **No se pierde ninguno**: los demás se siguen registrando como información y
  en la zona «Reproductor» están todos.
