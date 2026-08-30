## PrismHub v1.0.46 — El registro, terminado

> 🔍 **Se puede leer el registro del televisor desde el PC.** El televisor
> muestra una dirección, la escribís en el navegador de tu PC o tu teléfono
> conectados a la misma red, y ahí está el registro para buscar y copiar.

> ⚠️ **La app sigue en mantenimiento general.** Se la sigue reestructurando
> por dentro, así que es posible que te cruces con fallos o con cosas a medio
> terminar. Si encontrás algo roto, reportalo desde Ajustes → Reportar.

### 📺 Ver el registro desde otro aparato (televisor)

- En un televisor no hay a dónde exportar un archivo ni con qué abrirlo, así
  que el registro solo se podía mirar en la propia pantalla, línea por línea
  con el mando. Para un fallo corto alcanza; para rastrear un cierre hacia
  atrás, no.
- Ahora el televisor puede levantar un servidor chico en tu red y mostrar una
  dirección. La escribís en el navegador de cualquier PC o teléfono de la
  misma casa y tenés el registro entero, para buscarlo y copiarlo.
- **Muestra la misma zona que estés mirando en el televisor** — Todo, Fallos,
  Extensiones o Reproductor. Si cambiás el filtro en la tele, el navegador se
  actualiza solo.
- Cerrado por defecto: se enciende a mano y solo para esa sesión, la
  dirección lleva un código al azar (estar en el mismo wifi no alcanza: hay
  que estar viendo la pantalla), se apaga solo a los quince minutos, es de
  solo lectura y no funciona fuera de una red de casa.

### 🔍 Registros

- **El registro se explica solo.** Ahora abre diciendo qué es, para qué
  sirve, qué **no** lleva (nada de qué estuviste viendo, ni credenciales, ni
  tu nombre, tu cuenta o el de tu equipo) y que el archivo se queda en tu
  aparato salvo que vos decidas compartirlo. Va dentro del propio archivo,
  así que sigue estando si lo exportás.
- **Los filtros ya se ven en PC.** Estaban puestos donde solo aparecían con
  el registro pausado, así que en escritorio no salían nunca.
- **El scroll llega al principio y se queda.** En teléfono y televisor parecía
  repetirse en vez de llegar arriba: eran las líneas nuevas empujando el
  texto mientras leías. Ahora, mientras estés leyendo hacia arriba, la
  pantalla se queda quieta.
- **Exportar exporta la zona que estás viendo.** Si mirás Fallos y exportás,
  sale eso — y no dos mil líneas más que ya habías descartado.
- **Lo de las extensiones entra en el registro de siempre.** En escritorio
  había una ventana aparte que había que acordarse de abrir *antes* de que
  fallara nada, y que no guardaba lo que anotaba; en teléfono y televisor
  directamente no existía. Ahora lo que dice cada extensión —y qué respondió
  cada servidor— queda escrito siempre, junto al resto. Esa ventana ya no
  está.

### 🔒 Seguridad

- De los pedidos de red de las extensiones se anota una sola línea: método,
  servidor y código de respuesta. **Ni cabeceras ni contenido**, a propósito:
  eso es lo que lleva cookies y credenciales.
- El registro que se sirve por la red es el mismo ya saneado de siempre: sin
  direcciones completas, sin credenciales y sin tu nombre de usuario.
