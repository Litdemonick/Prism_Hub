## PrismHub v1.0.56 — El televisor se encuentra solo

> 📡 **Se acabó escribir direcciones.** En el teléfono, la tablet o el PC:
> Ajustes → Registros → **«Ver el registro de un televisor»**. Busca en tu red,
> muestra los que estén compartiendo y lo abre de un toque.

> ⚠️ **La app sigue en mantenimiento general.** Se la sigue reestructurando
> por dentro, así que es posible que te cruces con fallos o con cosas a medio
> terminar. Si encontrás algo roto, reportalo desde Ajustes → Reportar.

### 📡 Ver el registro de un televisor, sin escribir nada

- En el televisor se enciende igual que antes: **Ajustes → Ver registro → «Ver
  desde otro aparato»**. Y ahí ya no hace falta apuntar la dirección.
- En el otro aparato aparece en una lista y se abre de un toque. Se ve dentro
  de PrismHub, con los mismos colores del visor de siempre — no en una página
  pelada del navegador.
- **Si la conexión se corta, lo que ya llegó no se borra.** Si el televisor se
  cayó, eso es justamente lo que hace falta para saber por qué.
- Sigue funcionando por navegador si preferís: la dirección se muestra igual.

### 🔗 Y la dirección, mucho más corta

- Antes: `http://192.168.50.183:40365/r/ab3k9x`. Ahora: `192.168.50.183:8787/ab3k`
  — y **ya no cambia en toda la sesión**, así que apagar y volver a encender no
  te obliga a escribirla de nuevo.
- **Elige bien la dirección.** Un televisor con cable y wifi tiene dos, y se
  tomaba la primera sin mirar cuál. Ahora prefiere `192.168.x.x`, que es lo que
  reparten casi todos los routers de casa, y deja las dos anotadas en el
  registro por si la otra fuera la buena.

### 🔒 Sobre la privacidad, dicho claro

- El televisor solo se anuncia **mientras vos lo enciendas**, se apaga solo a
  los 45 minutos y es de solo lectura.
- Quien esté en tu red puede encontrarlo en ese rato sin ver la pantalla del
  televisor — antes hacía falta verla. Es el precio de la comodidad, y el
  registro sigue saliendo **sin credenciales, sin qué estuviste viendo y sin
  datos tuyos**.

### 🔧 Actualizaciones

- Cuando el instalador no aparece al actualizar, el registro ahora dice por
  qué: si falta el permiso de instalar apps o si el instalador se lanzó y el
  televisor no lo trajo al frente. Son dos problemas distintos que desde fuera
  se ven igual.
