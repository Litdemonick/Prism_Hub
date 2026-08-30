## PrismHub v1.0.54 — Que el registro no mienta

> 🎯 **Dos avisos que no eran ciertos, corregidos.** Uno acusaba al reproductor
> de un salto que había pedido la propia app; el otro daba dos números
> distintos para lo mismo en la misma pantalla.

> ⚠️ **La app sigue en mantenimiento general.** Se la sigue reestructurando
> por dentro, así que es posible que te cruces con fallos o con cosas a medio
> terminar. Si encontrás algo roto, reportalo desde Ajustes → Reportar.

### 🎯 «Salto fantasma» era un falso positivo

- El registro avisaba de que el vídeo se movía solo. No era cierto: el salto lo
  pedía la propia app al retomar donde lo habías dejado, por un camino que el
  detector no miraba.
- Un aviso falso en la zona de Fallos es peor que ninguno — manda a buscar un
  problema que no existe, justo en la pantalla que se abre cuando algo va mal.
- El detector sigue puesto, pero ahora cuando avise será por algo.

### 🔢 La página de red contaba mal

- Decía «582 líneas» arriba y «544» en el resumen, en la misma página. Contaba
  los renglones del documento —recuadros y títulos incluidos— en vez de las
  líneas del registro.

### ⏱️ La conexión de red dura 45 minutos

- Estaba en 15, pensada para «leer un registro y cerrar». En el uso real es
  otra cosa: se enciende para dejarla puesta mientras se prueba algo —un
  episodio entero, varias extensiones— mirando el navegador en paralelo. Se
  cortaba a mitad de la prueba, y volver a levantarla obliga a escribir otra
  dirección porque el código cambia cada vez.
- Sigue habiendo tope: es lo que garantiza que nadie se la deje abierta sin
  darse cuenta.

### 🔦 El aviso del wakelock, una sola vez

- En algunos televisores ese canal del sistema no responde, y no responde
  nunca: salían cuatro avisos idénticos por minuto. Ahora sale uno, y dice lo
  que importa: **en ese aparato la pantalla podría apagarse sola mientras
  reproducís**.
