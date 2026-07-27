import { motion } from 'motion/react';
import { Link } from 'react-router-dom';
import { ArrowUpRight } from 'lucide-react';

const columns = [
  {
    title: 'Producto',
    links: [
      { label: 'Inicio', to: '/' },
      { label: 'Documentación', to: '/docs' },
      { label: 'Preguntas frecuentes', to: '/faq' },
      { label: 'Extensiones', to: '/developers' },
    ],
  },
  {
    title: 'Instalar',
    links: [
      { label: 'Windows', to: '/windows' },
      { label: 'Linux', to: '/linux' },
      { label: 'Android', to: '/android' },
      { label: 'Releases en GitHub', to: 'https://github.com/Litdemonick/Prism_Hub/releases', external: true },
    ],
  },
  {
    title: 'Proyecto',
    links: [
      { label: 'Código fuente', to: 'https://github.com/Litdemonick/Prism_Hub', external: true },
      { label: 'Extensiones (prism+)', to: 'https://github.com/Litdemonick/prism-plus', external: true },
      { label: 'Licencia AGPL-3.0', to: '/license' },
      { label: 'Reportar un bug', to: 'https://github.com/Litdemonick/Prism_Hub/issues', external: true },
    ],
  },
];

export default function Footer() {
  return (
    <motion.footer
      initial={{ opacity: 0 }}
      whileInView={{ opacity: 1 }}
      viewport={{ once: true, margin: '-40px' }}
      transition={{ duration: 0.6 }}
      className="relative border-t border-white/[0.06] pt-16 pb-8 px-6"
    >
      <div className="absolute inset-0 bg-gradient-to-t from-violet-950/6 to-transparent pointer-events-none" />
      <div className="relative max-w-6xl mx-auto">
        <div className="grid grid-cols-2 md:grid-cols-4 gap-10 mb-14">
          <div className="col-span-2 md:col-span-1">
            <div className="flex items-center gap-2.5 mb-3">
              <img src={`${import.meta.env.BASE_URL}brand/logo.png`} alt="PrismHub" className="w-8 h-8 rounded-lg" />
              <span className="prism-text text-base font-normal tracking-tight">PrismHub</span>
            </div>
            <p className="text-white/30 text-xs leading-relaxed max-w-[220px]">
              Anime, manga, novelas, series y películas — sin límites. Open source, nativo, sin anuncios.
            </p>
          </div>
          {columns.map((col) => (
            <div key={col.title}>
              <div className="text-white/50 text-xs uppercase tracking-widest mb-4">{col.title}</div>
              <ul className="flex flex-col gap-2.5">
                {col.links.map((l) => (
                  <li key={l.label}>
                    {'external' in l && l.external ? (
                      <a
                        href={l.to}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="flex items-center gap-1 text-white/40 hover:text-white text-[13px] transition-colors group"
                      >
                        {l.label}
                        <ArrowUpRight className="w-3 h-3 opacity-0 group-hover:opacity-60 transition-opacity" />
                      </a>
                    ) : (
                      <Link
                        to={l.to}
                        className="text-white/40 hover:text-white text-[13px] transition-colors"
                      >
                        {l.label}
                      </Link>
                    )}
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </div>

        <div className="glow-line mb-8" />

        <div className="flex flex-col sm:flex-row items-center justify-between gap-4 text-white/25 text-xs">
          <span>© 2026 Soul_Of_The_sun · AGPL-3.0</span>
          <a
            href="https://github.com/Litdemonick"
            target="_blank"
            rel="noopener noreferrer"
            className="hover:text-white/50 transition-colors underline underline-offset-2"
          >
            github.com/Litdemonick
          </a>
        </div>
      </div>
    </motion.footer>
  );
}
