## PrismHub v1.0.85 — Correcciones de televisor y del lector

> ⚠️ **La app sigue en mantenimiento general.** Se la sigue reestructurando por
> dentro, así que es posible que te cruces con fallos o con cosas a medio
> terminar. Si encontrás algo roto, reportalo desde Ajustes → Reportar.

### 📺 Televisor

- **El nombre del botón elegido, en el panel izquierdo, no se veía.** El
  fondo del botón pasa a un rosa sólido cuando está elegido, pero el texto
  seguía pintado de ese mismo rosa — quedaba invisible contra su propio
  fondo. Al ícono de al lado ya se le había corregido esto mismo; al texto
  se le pasó por alto.
- **El panel desplegado (mostrando los nombres de cada categoría) tapaba el
  título de una fila**, y los dos textos quedaban mezclados, ilegibles.
  Contraído sigue transparente como hasta ahora; desplegado vuelve a tener
  un fondo sólido detrás, con esquina redondeada, para que no se filtre
  nada.
- **Los puntitos de paginación del carrusel de Inicio quedaban tapados por
  la fila de abajo.** En TV la tarjeta del carrusel ya ocupa el alto entero
  disponible, así que ese renglón no tenía dónde entrar. Como en TV esos
  puntitos tampoco sirven de nada —son para tocar, y con el mando no hay
  con qué tocarlos—, directamente se dejan de dibujar ahí.

### 📖 Lector

- **"Capítulo anterior/siguiente" quedaba cortado en celular**, en el pie
  de la cascada — no entraba en la mitad de pantalla que le toca a cada
  botón. Ahora dice solo "Anterior"/"Siguiente"; el ícono ya dice de qué
  capítulo se trata.
- **En PC, los botones de capítulo pasan al medio del grupo de opciones**
  (entre ajustes y detalle/episodios), con su propia cápsula visual en vez
  de dos íconos sueltos pegados al título.
- **Los títulos largos que no entraban se pueden tocar para leerlos
  enteros.** Antes quedaban cortados con "..." sin ninguna forma de verlos
  completos sin salir a la ficha.
