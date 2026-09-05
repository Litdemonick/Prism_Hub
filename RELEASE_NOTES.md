## PrismHub v1.0.99 — El mando ya no navega la pantalla de atrás

<!-- solo-plataforma: androidtv -->

> 📺 **Esta versión es solo para televisor.** Windows, Linux, teléfono y
> tablet siguen en la 1.0.97: nada de lo que cambia acá los toca, así que no
> tiene sentido hacerlos actualizar.

> ⚠️ **La app sigue en mantenimiento general.** Se la sigue reestructurando por
> dentro, así que es posible que te cruces con fallos o con cosas a medio
> terminar. Si encontrás algo roto, reportalo desde Ajustes → Reportar.

### 📺 Android TV

- **Al abrir una pantalla nueva, el mando ya no sigue manejando la de
  atrás.** Pasaba en el repositorio de extensiones y en el historial: se
  veía la pantalla nueva arriba, pero las flechas seguían moviendo la
  selección de la que quedó debajo, todavía viva. La causa era el mismo
  mecanismo que rescata el foco cuando se pierde de verdad —pensado para
  una tarjeta que se recicla o un panel que se cierra—, que no distinguía
  ese caso de "pantalla nueva sin nada enfocado todavía" y devolvía el
  mando al último lugar bueno, que era el de la pantalla anterior. Corregido
  en la raíz: ahora solo se vuelve ahí si ese último lugar sigue siendo
  parte de la pantalla que se está viendo. Esto destrababa, entre otras
  cosas, instalar extensiones nuevas desde el televisor.

- **La Zona +18 ya tiene su botón de Favoritos, separado de Historial.**
  Antes solo estaba conectado el de Historial; ahora cada uno abre su
  propia pantalla, con el filtro que corresponde.

- **La pantalla de "escribí algo" del buscador, mejor centrada y con menos
  texto.** Quedaba pegada arriba en vez de en el medio de la pantalla, y
  sobraba una segunda línea explicando un mecanismo que no hace falta
  saber desde el sillón. El ícono también usa el color de la pantalla que
  lo llama —rosa en el buscador general, rojo en el de la Zona +18—, antes
  quedaba siempre rosa aunque todo lo demás alrededor fuera rojo.
