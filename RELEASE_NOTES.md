## PrismHub v1.0.61 — PrismHub+: la app se adapta a tu aparato

> ⚡ **Nuevo: PrismHub+.** La app ahora mira en qué aparato está corriendo
> —televisor, teléfono, tablet o PC— y se ajusta a lo que ese aparato puede dar.
> Está en **Ajustes → PrismHub+**, con todo a la vista: qué detectó, qué cambió
> por eso, y un interruptor para apagarlo.

> ⚠️ **La app sigue en mantenimiento general.** Se la sigue reestructurando por
> dentro, así que es posible que te cruces con fallos o con cosas a medio
> terminar. Si encontrás algo roto, reportalo desde Ajustes → Reportar.

### ⚡ PrismHub+

Hasta ahora la app pedía lo mismo en todos lados: 1080p de vídeo, todas las
peticiones a la vez, todos los efectos. Eso está bien en un teléfono nuevo y es
demasiado en un televisor de 1 GB.

- **Pide la calidad que tu aparato puede mostrar y sostener.** En un televisor
  de 720p pedir 1080p es decodificar un tercio más de imagen de la que se ve y
  descargar casi el doble de datos para tirarlos. Es un **techo**, no un
  objetivo: si la fuente solo tiene 720p, se ve 720p.
- **Si el vídeo se corta dos veces, baja un escalón de calidad solo.** Ni el
  aparato ni la pantalla dicen cuánto está llegando por la red en este momento;
  eso solo lo dice que el vídeo se corte.
- **Reparte las peticiones al abrir la app.** Todas las zonas piden sus
  carruseles a la vez, y en un televisor con cuatro núcleos eso son más de cien
  peticiones en catorce segundos peleándose entre ellas.
- **Los carruseles construyen menos de más al deslizarse**, y los efectos caros
  —el desenfoque del fondo, el crecido de las tarjetas— se ajustan al aparato.
- **Y si la app va a tirones de todos modos, baja el nivel sola** y lo recuerda
  para la próxima vez. Ya medíamos cada cuadro; ahora eso sirve para algo.

Apagado, todo vuelve a comportarse como antes, y se dice bien claro tanto en la
pantalla como en el registro.

### 🖥️ Ahora se mide el aparato en todas las plataformas

Antes esto solo se calculaba en televisores. Un portátil de dos núcleos recibía
el mismo trato que una máquina nueva, y un teléfono de 2 GB el mismo que uno de
12.

- Se miran la **memoria** y los **núcleos**, y ahora también los **físicos**:
  ocho lógicos pueden ser cuatro reales, y dos hilos del mismo núcleo no
  decodifican vídeo en paralelo.
- **Un televisor potente ya puede contar como capaz.** Antes ninguno pasaba de
  «medio», así que un Fire TV 4K recibía el mismo trato que un stick de 1 GB.
- **«Pedir siempre la máxima calidad»** queda bloqueado, con el motivo, en los
  aparatos donde solo puede romper la reproducción.

### 📡 El registro de otro aparato ya no se pierde

Al abrir el registro de un televisor caído decía «se cortó la conexión, lo de
abajo es lo último que llegó» y abajo no había nada.

Ahora se guarda en disco lo último que llegó de cada aparato y se muestra
apenas se abre la pantalla, con una franja que dice **de qué día y hora es** —un
registro viejo que parece de ahora lleva a mirar el fallo equivocado.

### 🔎 Diagnóstico

- **Se mide el desfase entre el audio y el vídeo**, con los milisegundos, hacia
  qué lado, el códec, si decodifica por hardware y por dónde sale el audio.
- El registro dice qué decidió PrismHub+ al arrancar, y avisa fuerte si está
  apagado.
