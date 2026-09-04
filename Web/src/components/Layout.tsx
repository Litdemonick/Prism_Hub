import type { ReactNode } from 'react';
import Navbar from './Navbar';
import Footer from './Footer';

/** El armazón de cada página: fondo ambiental fijo, navbar, contenido y pie.
 * Reemplaza el patrón repetido de "contenedor redondeado + PrismBg" que
 * tenía cada página por separado — un solo lugar decide cómo se ve el
 * fondo de toda la app. */
export default function Layout({ children }: { children: ReactNode }) {
  return (
    <div className="relative min-h-screen w-full">
      <div className="ambient-glow" />
      <Navbar />
      <main>{children}</main>
      <Footer />
    </div>
  );
}
