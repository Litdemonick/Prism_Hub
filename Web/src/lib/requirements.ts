/**
 * Los umbrales de memoria y núcleos son los MISMOS que usa la app en
 * `PerfilDeAparato` para decidir el perfil del aparato (bajo/medio/alto):
 * por debajo del mínimo cae en el nivel "bajo" (calidad de vídeo tope 720p,
 * imágenes decodificadas al 75%, motores de extensión limitados a 6 vivos
 * a la vez); en o por encima del recomendado cae en "alto" (sin techo de
 * calidad, sin límite de motores). No es una cifra de marketing — es la
 * que ya corre en el código.
 */
export const requirements = {
  es: {
    min: { os: 'Windows 10 (64 bits) · Android 7.0 · cualquier distro Linux x64', ram: '2 GB', cpu: '2 núcleos', storage: '~250 MB libres' },
    rec: { os: 'Windows 11 · Android 10+ · distro Linux x64 reciente', ram: '4 GB o más', cpu: '4 núcleos o más', storage: '~500 MB libres' },
  },
  en: {
    min: { os: 'Windows 10 (64-bit) · Android 7.0 · any x64 Linux distro', ram: '2 GB', cpu: '2 cores', storage: '~250 MB free' },
    rec: { os: 'Windows 11 · Android 10+ · recent x64 Linux distro', ram: '4 GB or more', cpu: '4 cores or more', storage: '~500 MB free' },
  },
} as const;
