## PrismHub v1.0.64 — El televisor, otra vuelta

> ⚡ **La causa real del cierre al desplazarse rápido, encontrada y corregida.**
> Bajar rápido por una zona sin soltar el mando encadenaba una carga atrás de
> otra sin que la interfaz llegara a respirar. Ahora hay un piso de tiempo
> entre una carga y la siguiente.

> ⚠️ **La app sigue en mantenimiento general.** Se la sigue reestructurando por
> dentro, así que es posible que te cruces con fallos o con cosas a medio
> terminar. Si encontrás algo roto, reportalo desde Ajustes → Reportar.

### ⚡ Estabilidad — en todas las plataformas

- **Bajar rápido por una zona (Películas, Series, Anime) ya no encadena
  cargas sin parar.** Cada pedido de más contenido espera un momento antes
  de dejar salir el siguiente, así la interfaz siempre tiene un respiro —
  antes, en un aparato modesto, esa cadena sin cortes podía terminar en un
  cierre.
- **El tope de páginas por zona baja**, para no seguir pidiéndole contenido
  a todas las extensiones activas más de lo necesario.

### 📺 El televisor

- **El menú de categorías del Inicio ya no mueve nada al abrirse.** Antes
  empujaba las tarjetas hacia un costado, así que expandirse para mostrar
  el nombre de cada categoría achicaba la grilla. Ahora se dibuja encima,
  sin correr ni una tarjeta de lugar.
- **El mando ya no puede terminar en una zona que no se está viendo.** Al
  moverse por los bordes del menú, el foco podía saltar a una tarjeta de
  otra categoría que seguía viva por dentro aunque no se mostrara —y esa
  categoría arrancaba a cargar sin que nadie lo hubiera pedido. Ya no puede
  pasar.
- **"Volver" ya funciona en Extensiones y en Ajustes.** Antes no hacía nada
  en algunos casos, según desde dónde se hubiera entrado.
- **Los botones de las columnas laterales tienen más aire entre sí**, para
  que el resplandor de selección no se sienta apretado contra el de al
  lado.
- **Las acciones que tardan (activar todas, actualizar todas, instalar
  todas) ahora se ven cargando** mientras corren, en vez de quedar mudas.
- **El carrusel de las filas se desvanece en los bordes** en vez de cortar
  las tarjetas en seco.

### 🖥️ El destacado de Inicio

- **Se mueve solo.** Antes había que arrastrarlo o moverlo con el mando a
  mano; ahora avanza cada tanto por su cuenta, y tocarlo lo pausa un rato
  antes de retomar.

### 💻 Windows

- **El visor del registro ya no deja ver Ajustes por detrás.** Un fallo de
  fondo hacía que, al abrir "Ver registro", se llegaran a ver filas de
  Ajustes asomando debajo del contenido nuevo.
