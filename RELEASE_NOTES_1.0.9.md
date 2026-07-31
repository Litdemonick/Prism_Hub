# PrismHub 1.0.9

Actualización grande. Si venís de la 1.0.8, **tu historial, favoritos y ajustes
se conservan**: la base migra sola al abrir y no hay que reinstalar nada.

---

## Lo que se rompía y ya no

**La app quedaba inutilizable si se corrompía el archivo de ajustes.** Una
escritura cortada —el sistema matando el proceso, por ejemplo al apagar la
pantalla durante la reproducción— dejaba la caja de ajustes ilegible. Y el
manejo de ese fallo caía a una caja temporal **sin cargar los valores por
defecto**, así que la app arrancaba con la URL del repositorio y el proxy en
blanco: no cargaba ninguna extensión y en pantalla se veía como si no hubiera
internet. Como la caja temporal se pierde en cada arranque, se repetía para
siempre.

Ahora la caja ilegible se aparta y se crea una limpia, y los valores por
defecto se cargan pase lo que pase.

**Pantallas muertas sin explicación.** En release, el widget de error de
Flutter es un rectángulo gris sin texto: cualquier fallo al construir la
interfaz se veía igual, sin decir nada. Ahora muestra el error, su origen y
dónde ocurrió.

**Un ajuste guardado en null tiraba la app entera.** `getSetting` devolvía
`null` y quien lo usara como texto o booleano reventaba. Ahora nunca devuelve
null si esa opción tiene valor de fábrica, y las claves que quedaron en null se
reparan solas.

**Se perdía el progreso al apagar la pantalla.** El lector y el reproductor
guardaban solo al cerrarse, así que si el sistema mataba la app en segundo
plano se perdía por dónde ibas. Ahora se vuelca al pasar a segundo plano.

**Linux:** corregido el cierre inesperado al abrir, por una colisión de
símbolos entre el motor de extensiones y libmpv.

---

## Seguimiento de lo que ves y leés

La novedad más grande de esta versión.

- **Pendiente y Completado** se calculan solos. Al ver el último episodio
  disponible, la obra queda al día y sale de "Continuar".
- **Cuando sale un capítulo nuevo, vuelve sola** a "Continuar", en segunda
  posición y con un distintivo que dice cuál es el nuevo. Se comprueba cada 12
  horas en segundo plano, y se puede apagar desde **Ajustes → General**.
- **Botón "Marcar como finalizada"** en la ficha, para las obras que ya no
  publican más. Aparece solo en contenido por capítulos, nunca en películas.
- Si marcaste algo finalizado y **llega un capítulo nuevo, la marca se quita
  sola**: que aparezca contenido demuestra que no había terminado.

## Inicio y Zona +18

- **"Continuar" y "Favoritos" se parten en vídeo y lectura.** Cada tipo usa la
  forma de tarjeta que le corresponde: ancha 16:9 para vídeo, vertical para
  lectura. Mezclados, uno de los dos siempre quedaba recortado.
- Tarjetas rediseñadas: menú de tres puntos con ocultar y eliminar, distintivos
  con color sólido para que se lean sobre cualquier portada, y borde con el
  color de cada zona.
- **Las portadas ya no se deforman.** Se pasaba al decodificador un ancho y un
  alto a la vez, y así el resultado ignora el aspecto original de la imagen.
- **"Quitar de Continuar" ya no borra nada.** Antes eliminaba el registro
  entero: perdías el progreso y la marca de finalizada por ordenar una fila. El
  borrado real vive en el Historial.

## Historial

- Cinco pestañas: Todo, Vídeo, Lectura, **Fav. Vídeo** y **Fav. Lectura**.
- **Filtros por estado**: Pendiente, Completado, Finalizada.
- **Orden**: más reciente, más antiguo, A–Z, Z–A.
- Tarjetas con la forma del Home según el tipo.
- Nuevo en el menú: **"Devolver a Continuar"** y **"Marcar como visto"**.

## Reproductor

- **Rueda de carga** mientras espera: al resolver el enlace, al saltar y cuando
  se vacía el buffer. Antes la imagen se congelaba sin ninguna señal.
- **Aviso del salto**: al usar las teclas I/J, las flechas o el doble toque en
  el teléfono aparece cuántos segundos se movió.
- En el teléfono, el **doble toque respeta el intervalo configurado** — antes
  estaba fijo en 10 segundos y el ajuste no hacía nada.
- El puntero del mouse se esconde junto con los controles.

## Zona +18

- **Huella o Windows Hello antes del PIN.**
- **Confirmación de mayoría de edad** con fecha de nacimiento al activarla, una
  sola vez.
- **Freno a la fuerza bruta**: tras 5 intentos fallidos, espera que se duplica.
- Al reactivar el interruptor, **las extensiones +18 vuelven a activarse solas**
  — y solo las que la app había apagado.

## Extensiones

- **Filtros en Extensiones instaladas**: Todas, Normales, +18, Vídeo, Lectura,
  Desactivadas e Inestables.
- **El botón Actualizar ya funciona.** Antes "Actualización requerida" se
  mostraba también cuando la extensión estaba marcada inestable, así que con la
  versión ya al día el botón reinstalaba lo mismo y no se iba nunca. Ahora una
  cosa y la otra se tratan por separado.
- **Una extensión inestable ya no bloquea la ficha.** Se entra normal y el
  aviso, con su motivo, va dentro del detalle.
- Datos de extensiones a prueba de fallos: un ítem mal formado ya no hace
  desaparecer todo el listado de esa extensión.

## Ajustes

- **Aviso de versión beta** al abrir por primera vez, con selector de idioma.
- **Aviso legal** propio, y enlaces al repositorio y a sugerencias.
- **Campos bloqueados** para que no se puedan dejar inservibles: URL del
  repositorio y User-Agent. Si quedaron mal, se reparan al arrancar.
- **"Saltar intervalo"** rediseñado en el teléfono, con solo los valores que el
  doble toque usa de verdad.
- Los widgets del sistema —selector de fecha, menú de texto— **ya salen en
  español**.
- Solo inglés y español: se quitaron los idiomas a medio traducir.

## Buscador

- Las extensiones **con resultados salen primero**. Las que no encontraron nada
  quedaban mezcladas entre las que sí.
- Las que se saltearon por tener una consulta anterior en curso **ahora se
  reintentan** en vez de quedarse vacías para siempre.
