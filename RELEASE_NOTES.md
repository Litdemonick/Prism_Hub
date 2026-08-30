## PrismHub v1.0.53 — ExoPlayer, ahora de verdad

> 🎬 **Vuelve el selector de motor de vídeo**, y esta vez funciona. Antes
> cambiar a ExoPlayer dejaba la pantalla en negro con el audio sonando: la
> vista era la suya, pero quien reproducía por debajo seguía siendo el otro.
> Ya está conectado de punta a punta.

> ⚠️ **La app sigue en mantenimiento general.** Se la sigue reestructurando
> por dentro, así que es posible que te cruces con fallos o con cosas a medio
> terminar. Si encontrás algo roto, reportalo desde Ajustes → Reportar.

### 🎬 El motor de vídeo (Ajustes)

- **Podés elegir entre mpv y ExoPlayer**, en PC y en televisor. Es un
  interruptor **temporal y para probar**: cada extensión tiene sus servidores y
  cada servidor su formato, y cuál conviene solo se sabe probando en aparatos
  reales. Cuando esté decidido por plataforma y formato, se saca.
- **En Android, ExoPlayer ahora dibuja en superficie nativa.** Es la razón de
  tenerlo: con textura, cada cuadro pasa por el decodificador, el contexto
  gráfico y una textura antes de que la app lo componga — dos pasadas de GPU
  por cuadro. Un televisor decodifica vídeo de sobra, pero su GPU dibujando
  interfaz es floja, y eso es justo lo que se paga.
- Con ExoPlayer se pierde parte de la información de diagnóstico del registro
  (la que sale de mpv) pero no la reproducción.
- **Si algo no te va con un motor, probá el otro y contámelo** con el registro:
  es exactamente para eso.

### 🗂️ Historial

- **Fecha completa en vez de «Ayer»**, con segundos. Estas fechas se leen al
  revés de como se escriben: alguien dice cuándo le falló algo y hay que
  encontrar esa apertura — con «Ayer» hay que ir calculando.
- **La hora, en el formato de tu aparato**: si lo tenés en 12 horas, se ve en
  12 horas. Mismo criterio que el reloj de la pantalla de inicio.
- La primera tarjeta ya no queda pegada al borde de arriba.

### 📺 Ver desde otro aparato

- **La página dice qué está compartiendo**: si es el registro de ahora o una
  apertura guardada (con su fecha), de qué zona, y cuántas líneas trae. Antes
  decía «todo el registro» pasara lo que pasara, y una sesión vieja se leía
  como si fuera lo de ahora.
- Queda anotado en el registro al encender y al apagar, para poder comprobar
  después qué se estuvo compartiendo.

### 🧠 Rendimiento y diagnóstico

- **En aparatos con poca memoria, la app reacciona antes.** Medido en un
  televisor de 0,9 GB: cuatro avisos del sistema en siete minutos, y el umbral
  para aliviar era seis — no se disparaba nunca.
- Al salir del reproductor con el mando queda anotado, y también cualquier
  tecla que llegue y no se use. Sirve para distinguir un botón EXIT que la app
  recibe de uno que atiende el televisor por su cuenta.
