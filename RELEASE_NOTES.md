## PrismHub v1.0.27 — El lector a pantalla completa, y el modo claro que por fin se ve

Versión de pulido sobre la [1.0.26](https://github.com/Litdemonick/Prism_Hub/releases/tag/v1.0.26).
Casi todo lo de esta tanda son detalles de uso diario: leer sin nada alrededor,
que el zoom no te mueva de lugar y que el modo claro deje de comerse la hora y
la batería.

### 📖 Lector de manga, manhwa y novelas

- **Llenar pantalla, de verdad.** El botón nuevo esconde la barra de arriba del
  teléfono y la de navegación de abajo, igual que hace el reproductor de vídeo:
  la página usa la pantalla entera. Está en el panel de ajustes del lector, al
  lado de «Modo de lectura», y **también llegó a las novelas**.
- **El doble toque ya no te mueve de lugar.** Antes, alejar o acercar te dejaba
  mirando otra parte de la página. Ahora el zoom se queda clavado **en el punto
  exacto donde tocaste**: ves lo mismo, más cerca o más lejos.
- **El zoom se mantiene al cambiar de página.** Se guardaba por página, así que
  alejabas en la 20 y la 21 aparecía otra vez grande. Ahora es uno solo para
  todo el lector: se respeta al pasar de página, al cambiar de capítulo y al
  pasar de cascada a paginado.
- **En paginado, el doble toque acerca.** En una página de manga no hacía
  absolutamente nada.
- **Deslizar para bajar ya no se confunde con pasar de página.** Los dos gestos
  usaban el mismo umbral y competían: un deslizamiento apenas torcido se lo
  quedaba el cambio de página. Y tocar mientras la página se estaba asentando
  la dejaba a mitad de camino y a veces saltaba sola a la otra.
- **En PC, las flechas de arriba y abajo bajan la página** en vez de cambiarla.
  Pasar de página queda para las flechas de los costados.
- **El contador de página** ya no va pegado al vértice de la pantalla.
- **La barra de arriba llega hasta el borde**, sin esa franja suelta encima.

### 🎬 Reproductor de vídeo

- **Barra de volumen siempre visible**, en PC y en Android, con el porcentaje al
  lado y sin tener que abrir ningún menú. Reemplaza al gesto de deslizar arriba
  y abajo, que se disparaba sin querer. Sigue pudiendo pasar del 100 %.
- **Tocar la bocina silencia** y vuelve a poner el volumen exacto que tenías.
- **Botón grande de pausa en el centro** en el teléfono.
- **Los controles ya no se esconden a mitad de un arrastre**, ni en PC ni en
  Android: mover la barra de progreso o la de volumen ya no se corta por el
  temporizador.
- **Se dejaba de escuchar mal al salir.** Si salías con el botón o el gesto de
  atrás del sistema —no con la flecha del reproductor— el audio seguía sonando.
- **Llenar pantalla llega hasta la cámara** y la barra de arriba ya no deja un
  hueco de vídeo por encima.
- El botón de pantalla completa en Android **quedó más a mano** en la fila de
  botones.
- **Tutorial actualizado** con los gestos que de verdad existen ahora.

### 🎨 Modo claro

- **La barra de estado por fin se ve.** La hora, la señal y la batería quedaban
  invisibles: Android pintaba esa franja en negro por su cuenta e ignoraba el
  color que pedía la app. Ahora el color lo manda PrismHub.
- **Se van las sombras sucias.** Las portadas del carrusel y las de las filas
  llevaban una sombra negra pensada para el fondo oscuro; sobre fondo claro se
  leía como un halo gris alrededor de cada tarjeta.
- **El fondo deja de salir teñido de rosa.** Se notaba con el teléfono
  acostado, en la franja del menú lateral.
- Salir del lector a pantalla completa **ya no dejaba los iconos del sistema
  invisibles**.

### 🔎 Búsqueda

- **La búsqueda general dejó de rendirse antes de tiempo** con las extensiones
  lentas: cortaba la espera antes de terminar de probar.

---

Gracias por probar y por reportar cada detalle. Si algo no anda,
[abrí un issue](https://github.com/Litdemonick/Prism_Hub/issues) y lo miramos.
