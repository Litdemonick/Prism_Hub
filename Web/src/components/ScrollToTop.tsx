import { useEffect } from 'react';
import { useLocation } from 'react-router-dom';

/** React Router no resetea el scroll al cambiar de ruta — es SPA, así que
 * técnicamente "no se navegó a otra página". El resultado: tocar un enlace
 * estando scrolleado a la mitad de Inicio hacía aparecer la página nueva ya
 * a la mitad, como si hubiera llegado "abajo" en vez de al principio.
 * Reportado en vivo. Se sube al tope en cada cambio de ruta, en un solo
 * lugar para que valga en todo el sitio. */
export default function ScrollToTop() {
  const { pathname } = useLocation();
  useEffect(() => {
    window.scrollTo(0, 0);
  }, [pathname]);
  return null;
}
