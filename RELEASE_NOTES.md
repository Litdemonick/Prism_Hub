## PrismHub v1.0.49 — Que el registro sirva para arreglar

> 🔎 **Ahora se ve lo que hace la app, no solo lo que falla.** Cada pedido de
> red, cada paso que das y todo lo que antes solo salía por consola queda
> escrito. Si algo no te anda, el registro que exportes ya trae con qué
> encontrarlo.

> ⚠️ **La app sigue en mantenimiento general.** Se la sigue reestructurando
> por dentro, así que es posible que te cruces con fallos o con cosas a medio
> terminar. Si encontrás algo roto, reportalo desde Ajustes → Reportar.

### 🔎 Mucho más registro (todas las plataformas)

- **Cada pedido de red de la app queda anotado**: método, servidor, código de
  respuesta y cuánto tardó. Antes solo se anotaba lo de las extensiones, así
  que cuando algo «no cargaba» y la extensión ni intervenía, no había nada que
  mirar. Ni cabeceras ni contenido, a propósito: ahí es donde viajan las
  cookies.
- **Lo que antes solo salía por consola ahora se guarda.** Había medio
  centenar de mensajes que se perdían — justo en televisor y teléfono, donde
  nadie tiene una consola abierta.
- **Se ve lo que estabas haciendo**, paso a paso, y no solo después de un
  cierre: a qué zona fuiste, qué instalaste, cuándo buscaste. De la búsqueda
  **no** se guarda qué escribiste.
- **Las zonas ahora dividen bien.** Se revisó el código y faltaban la mitad de
  las marcas reales: el reproductor y las extensiones dejaban líneas fuera de
  su zona. Y un fallo aparece en «Fallos» además de en la suya, para no tener
  que elegir primero de qué parte de la app era.
- **Lo normal se lee en blanco.** Iba en gris apagado, que es el color de
  «esto no importa» — y era la mayor parte del registro.

### 🖼️ El nombre de PrismHub, entero

- Se veía cortado en todas las plataformas. Las letras mezclaban dos tipos de
  caracteres, y cuando al aparato le falta alguno lo saca de otra fuente con
  otro ancho: ahí la letra se desarma. Ahora está dibujado con uno solo.
- El recuadro se mide solo en vez de estar escrito a mano, así que no puede
  quedar abierto.
- Y cada sesión guarda su hora de apertura, así el historial ya no muestra
  aperturas «sin fecha».

### 📺 Televisor

- **El historial usa el mismo diseño que el registro**: columna de acciones al
  costado en las tres pantallas, así que salir, cambiar de zona o encender la
  conexión se hace desde cualquier punto sin subir hasta arriba.
- **Al abrir una sesión guardada podés filtrar por zona** igual que en el
  registro en vivo — Todo, Fallos, Extensiones, Reproductor.
- **La luz de selección ya no se sale de la tarjeta.** El resplandor se dibuja
  detrás y las tarjetas eran translúcidas, así que se veía entero a través.

### 💻 PC y Android

- Cada plataforma con lo suyo: en teléfono y escritorio la barra de arriba se
  queda —con el dedo o el ratón se llega sin recorrer nada— y ahí va exportar.
  «Ver desde otro aparato» sigue siendo solo de televisor, que es donde no hay
  a dónde exportar.
