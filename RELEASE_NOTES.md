## PrismHub v1.0.47 — El registro empieza de cero cada vez

> 🗂️ **Ahora cada apertura de la app es una sesión.** «Ver registro» muestra
> solo la de ahora, empezando limpia, y las anteriores quedan en **Historial**
> con su fecha y su hora — que es donde hay que mirar cuando la app se cerró
> sola.

> ⚠️ **La app sigue en mantenimiento general.** Se la sigue reestructurando
> por dentro, así que es posible que te cruces con fallos o con cosas a medio
> terminar. Si encontrás algo roto, reportalo desde Ajustes → Reportar.

### 🗂️ Historial de sesiones (todas las plataformas)

- **El registro ya no arranca con lo de ayer pegado arriba.** El archivo es
  acumulativo y se mostraba entero, así que nunca empezaba desde cero ni había
  forma de ver dónde terminaba una apertura y empezaba la siguiente.
- **Botón «Historial»**: la lista de aperturas anteriores, la más reciente
  arriba, cada una con su fecha y su hora, y avisando cuáles traen fallos. El
  botón dice cuántas hay, así no se entra a una pantalla vacía.
- Al abrir una sesión se lee igual que el registro en vivo, y con las mismas
  herramientas: exportar en PC y Android, verla desde otro aparato en
  televisor.
- **Se acabaron las líneas repetidas.** El archivo y lo que hay en memoria se
  pisaban, y el tramo compartido salía dos veces.
- **Limpiar limpia todo** —las cuatro zonas y el historial— y deja el registro
  empezado de nuevo, con la presentación, en vez de una pantalla en blanco.

### 📺 La pantalla de registro, rehecha para el mando

- **Los botones ya no están arriba, sino en una columna al costado.** Con el
  dedo la barra superior está siempre ahí; con un mando había que llegar hasta
  ella, y desde el medio de tres mil líneas eso eran cientos de pulsaciones.
  Ahora **izquierda** salta directo a las acciones desde cualquier punto, y
  **derecha** vuelve al texto.
- **Se ve dónde estás parado.** Cada cosa elegible se ilumina con el foco,
  incluido el propio registro, que al ser una pared de texto no tenía forma de
  indicarlo. Y la letra es más grande: a la distancia de un sofá, el tamaño
  anterior no se leía.
- **Manteniendo apretado, el texto ya no se traba.** Cada repetición de la
  tecla cortaba la animación anterior y empezaba otra, así que avanzaba a
  saltos cortos y por momentos parecía frenarse. Sostenido ahora se mueve
  parejo.
- **Entrar es fluido, también la segunda vez.** Se leía el archivo entero
  —hasta diez megas— justo mientras corría la animación de entrada, y por eso
  fallaba recién en la segunda visita, cuando el archivo ya había crecido.
  Ahora se lee solo el final y después de que la pantalla terminó de entrar.
- **Y se acabó el tirón mientras se lee**: la lista filtrada se rearmaba
  entera cuatro veces por segundo.

### 🧯 Errores que ya no pasan desapercibidos

- Exportar, limpiar y el servidor de red fallaban en silencio: se apretaba el
  botón y no pasaba nada. Ahora cada uno avisa qué salió mal.
- El servidor de red dice **cuál** fue el problema. No es lo mismo que el
  televisor no esté conectado a la red que el sistema no deje abrir el puerto
  — llevan a arreglos distintos.
