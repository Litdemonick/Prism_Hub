## PrismHub v1.0.50 — Saber en qué aparato pasó

> 🩺 **El registro ahora abre con la ficha del aparato**: sistema, marca,
> modelo, memoria, procesador y pantalla. Es lo primero que hace falta para
> entender un fallo, y va también en cada archivo que exportes.

> ⚠️ **La app sigue en mantenimiento general.** Se la sigue reestructurando
> por dentro, así que es posible que te cruces con fallos o con cosas a medio
> terminar. Si encontrás algo roto, reportalo desde Ajustes → Reportar.

### 🐞 Se caía al abrir el registro en el teléfono

- La pantalla no llegaba a abrirse. La causa estaba en el propio registro que
  se pudo exportar: los manejadores de selección —los dos círculos con los que
  se ajusta la selección con el dedo— se caen cuando la lista se rehace, y esta
  se rehace cuatro veces por segundo mientras entran líneas.
- La selección de texto queda en escritorio, que es donde de verdad se usa y
  donde ese problema no existe. En teléfono y televisor ya está exportar.

### 🩺 La ficha del aparato

- Antes decía solo el identificador de compilación del sistema — ni marca, ni
  modelo, ni memoria. Ahora: **sistema y versión completa** (Windows 11 Pro con
  su compilación, Android con su API), **marca y modelo**, **memoria**,
  **núcleos**, **perfil**, **resolución de pantalla** e **idioma**.
- Va al abrir la app y encabeza cada archivo exportado, en todas las zonas.
- **Sigue sin salir lo que te identifica**: ni el nombre que le pusiste al
  aparato, ni su número de serie, ni identificadores de publicidad, ni tu
  cuenta. Marca y modelo los comparten millones de aparatos y son justo lo que
  permite reproducir un fallo que solo pasa en el tuyo. Está explicado dentro
  del propio registro.

### 📤 Exportar

- **El archivo dice qué es**: `PrismHub-fallos-2026-08-29-2319.log`. Salían
  todos con el mismo nombre, así que dos exportados eran «reporte» y
  «reporte(1)». La fecha va del año al minuto, para que ordenados por nombre
  queden en orden de tiempo.
- Los del historial salen con «historial» adelante.

### 🎨 Detalles

- **Las filas anchas ya no crecen al seleccionarlas.** En el historial de PC se
  pegaban a los bordes y quedaban mordidas contra la lista.
- **El brillo rosado de selección se ve más**: más color y menos desenfoque,
  para que se lea como un contorno y no como una mancha.
- **El contador ahora cuenta las líneas que se ven.** Contaba el total, así que
  no se movía al cambiar de zona.
- **Los títulos se encogen antes que cortarse** — en teléfonos angostos salía
  «Ver registro…».
- **Márgenes seguros en apaisado**: el recorte de cámara y la barra de gestos
  se comían texto contra el borde.
- El bloqueador de anuncios ya no aparece en «Extensiones»: es de la app, no de
  una extensión.
