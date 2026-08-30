## PrismHub v1.0.55 — Registros limpios y una pantalla menos que se rompe

> 🧾 **Actualizá para poder reportar bien.** Esta versión arregla un fallo que
> rompía un trozo de la pantalla en algunos televisores, hace que el registro
> empiece limpio cada vez que volvés a la app, y dice **por qué** se cerró
> cuando se cierra sola.

> ⚠️ **La app sigue en mantenimiento general.** Se la sigue reestructurando
> por dentro, así que es posible que te cruces con fallos o con cosas a medio
> terminar. Si encontrás algo roto, reportalo desde Ajustes → Reportar.

### 📺 Un trozo de pantalla que se rompía en televisor

- En algunos televisores aparecía un rectángulo de error en medio del
  reproductor. La causa: widgets pensados para la versión de escritorio que se
  montan igual en Android, donde les falta el tema que necesitan — y en vez de
  arreglárselas, se caían.
- Ahora, si les falta, usan un tema por defecto. En PC no cambia nada.

### 🧾 El registro empieza limpio

- En televisor «cerrar la app» casi nunca la cierra: Android la deja en segundo
  plano y volver retoma el mismo proceso. El registro seguía escribiendo sobre
  la misma sesión, así que al abrirlo aparecían las líneas de hace horas.
- Ahora, si volvés después de un rato, empieza una **sesión nueva**. La
  anterior no se pierde: pasa al Historial, como siempre.
- No se mata la app al salir a propósito: eso haría lento el siguiente
  arranque, que es lo que más se nota en un televisor.

### ❓ Y dice por qué se cerró

- Cuando la app se cierra sola no hay error que mostrar: o reventó algo nativo
  o el sistema la cerró por falta de memoria. **Se ven idénticos desde fuera y
  llevan a arreglos opuestos.**
- Ahora los avisos de memoria quedan en el rastro, así que el propio registro
  lo distingue: si el rastro termina en varios «el sistema pidió memoria», fue
  lo segundo.

### 🗂️ Menos ruido, sin perder nada

- **Una apertura de la app = una entrada en el Historial.** Se partía en varias
  porque la cabecera podía escribirse más de una vez.
- **Cada pedido de una extensión se anotaba dos veces**, cada línea con media
  verdad. Ahora es una sola con todo: extensión, servidor, código y tiempo. En
  la carga del inicio son 150 líneas donde había 300.
