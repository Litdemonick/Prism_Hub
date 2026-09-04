## PrismHub v1.0.87 — Burbujas en el lector, importar lecturas e episodios nuevos que abrían mal

> ⚠️ **La app sigue en mantenimiento general.** Se la sigue reestructurando por
> dentro, así que es posible que te cruces con fallos o con cosas a medio
> terminar. Si encontrás algo roto, reportalo desde Ajustes → Reportar.

### ✨ Nuevo

- **Burbujas para saltar a otra obra sin salir del lector.** Mientras leés un
  manga, manhwa o novela, tocá la burbuja de otra obra que tenés en
  Continuar leyendo y pasá directo a ella — el lector actual se cierra y el
  otro se abre donde habías quedado. No mantiene nada abierto en paralelo:
  apenas la memoria de un salto normal, nunca la de varios lectores vivos a
  la vez. Con flechitas en PC, se desliza con el dedo en Android, y una
  flechita propia para ocultarla un rato sin apagar la función. **Apagada
  por defecto** — se activa desde Ajustes o desde los ajustes del propio
  lector.

### 🐛 Continuar viendo/leyendo

- **El aviso de capítulo nuevo abría el capítulo viejo.** Al detectar un
  episodio nuevo se actualizaba el nombre para mostrar en la tarjeta, pero
  nunca a qué capítulo apuntaba de verdad — avisaba "Episodio 15" y tocarla
  reabría el 14 de siempre. Ahora los dos se actualizan juntos. Afecta a
  PC, Android y Android TV por igual.

### 📥 Importar lecturas

- **ManhwaWeb y ShadeManga podían importar contenido +18 al Inicio normal
  en vez de a la Zona +18.** Esas dos extensiones separan su contenido
  adulto del normal con un filtro de búsqueda que la ficha de la obra no
  puede ver — ninguna lista de palabras alcanza para adivinarlo. Ahora,
  ante esa incertidumbre real, va directo a la Zona +18.
- **MangaDex no importaba nada.** Un link real del sitio
  (`mangadex.org/title/{id}/{nombre}`) no coincidía con lo que su ficha
  espera (el identificador solo). Se corrige la extracción.
- **Un link con "/" al final rompía la extracción del identificador** en
  varios sitios (confirmado en Ikigai Mangas y Olympus) — es la forma más
  común de copiar un link, así que se veía seguido.

### 📺 Televisor

- **Arreglo más profundo de la navegación con el mando.** El control
  anterior (v1.0.86) todavía dejaba pasar saltos incorrectos al final de
  una fila corrida. Ahora se compara el centro vertical de las tarjetas en
  vez de un porcentaje de superposición, que no depende de resolución ni
  de tamaño de tarjeta.
- Sin aviso al llegar al tope propio de una zona (antes decía "hasta acá
  llega esta zona por ahora"): ahora simplemente no dice nada.
