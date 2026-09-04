## PrismHub v1.0.88 — Las burbujas del lector confirman antes de saltar

> ⚠️ **La app sigue en mantenimiento general.** Se la sigue reestructurando por
> dentro, así que es posible que te cruces con fallos o con cosas a medio
> terminar. Si encontrás algo roto, reportalo desde Ajustes → Reportar.

### 🐛 Burbujas de "Continuar leyendo" (lanzadas en la 1.0.87)

- **Tocar una burbuja ya no salta directo a la otra obra.** Se agranda y
  espera: tocar la vista grande recién ahí confirma y abre el otro manga;
  tocar en cualquier otro lado la cierra sin hacer nada, como cancelar.
- El fondo oscuro de esa vista grande tapaba el contador de página
  ("2/34"), que vive en el mismo rincón de la pantalla. Bajado a un tinte
  apenas perceptible.
- El título debajo de cada burbuja se había sacado por un problema real de
  overflow (se veía como una raya amarilla en Android, el propio aviso de
  Flutter): la fila no reservaba alto para el renglón de texto. Vuelve, con
  un límite que achica el nombre para que entre en una línea en vez de
  desbordar.
