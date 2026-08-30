## PrismHub v1.0.51 — El registro contesta las tres preguntas

> 🧩 **Ahora dice qué extensiones tenés puestas y en qué versión**, cómo está
> configurada la app y qué hardware mueve el vídeo. Son las preguntas que
> había que hacer por mensaje antes de poder mirar nada.

> ⚠️ **La app sigue en mantenimiento general.** Se la sigue reestructurando
> por dentro, así que es posible que te cruces con fallos o con cosas a medio
> terminar. Si encontrás algo roto, reportalo desde Ajustes → Reportar.

### 🧩 Extensiones instaladas

- El registro abre listando **qué extensiones hay puestas, con su versión**, y
  marcando las apagadas. La mayoría de los reportes son «esta extensión no
  carga», y sin esto no se puede distinguir un fallo de la app de una
  extensión vieja — que es lo primero que hay que descartar.

### ⚙️ Cómo está configurada la app

- Se anota lo que **cambia el comportamiento**: proxy, motor de vídeo,
  reproductor, idioma y cuántas extensiones hay apagadas. Con un proxy puesto
  toda la red pasa por otro lado, y un «no carga» ahí no significa lo mismo.
- No va la lista entera de ajustes: eso sería ruido.

### 📺 Hardware que importa para el vídeo

- **Arquitectura y chip**: los decodificadores traen binarios distintos por
  arquitectura, y un aparato que corre la app en 32 bits teniendo 64 —pasa en
  cajas de televisión mal armadas— se comporta distinto.
- **Hercios de la pantalla**: buena parte de los tirones del reproductor son
  cuadros que no encajan con el refresco, y sin ese número no se puede ni
  empezar a mirarlo.

### 🐞 Corregido

- **La explicación desaparecía al filtrar.** Al elegir una zona se veía el
  nombre en grande y debajo, directamente, líneas técnicas: los apartados que
  cuentan qué es el registro y qué **no** lleva se escondían justo para quien
  estaba mirando una zona concreta.
