import { motion } from 'motion/react';
import Navbar from '../components/Navbar';
import PrismBg from '../components/PrismBg';

const sections = [
  {
    title: '1. ¿Qué es PrismHub?',
    content: (
      <div className="space-y-3">
        <p>PrismHub es una aplicación multiplataforma de streaming para anime, manga y series. Su arquitectura se basa en <span className="text-violet-400">extensiones JavaScript</span> que permiten añadir cualquier fuente de contenido sin modificar la app.</p>
        <p>Es open source bajo <span className="text-violet-400">AGPL-3.0</span>, mantenido activamente con mejoras continuas.</p>
        <a href="https://github.com/Litdemonick/Prism_Hub" target="_blank" rel="noopener noreferrer" className="text-violet-400 underline hover:text-violet-300 transition-colors inline-block">Repositorio en GitHub →</a>
      </div>
    ),
  },
  {
    title: '2. Instalación',
    content: (
      <div className="space-y-4">
        {[
          { label: 'Linux', cmd: 'curl -fsSL https://raw.githubusercontent.com/Litdemonick/Prism_Hub/main/install/install.sh | bash' },
          { label: 'Windows (PowerShell)', cmd: 'irm https://raw.githubusercontent.com/Litdemonick/Prism_Hub/main/install/install.ps1 | iex' },
        ].map(({ label, cmd }) => (
          <div key={label}>
            <p className="text-xs text-white/40 mb-2 font-mono">{label}</p>
            <pre className="glass-card rounded-xl px-4 py-3 text-xs font-mono text-violet-300 overflow-x-auto scrollbar-thin whitespace-nowrap">{cmd}</pre>
          </div>
        ))}
        <p className="text-white/40 text-xs">Android: descarga el APK desde <a href="https://github.com/Litdemonick/Prism_Hub/releases/latest" target="_blank" rel="noopener noreferrer" className="text-violet-400 underline">Releases →</a></p>
      </div>
    ),
  },
  {
    title: '3. Formato de extensión',
    content: (
      <pre className="glass-card rounded-xl px-4 py-3 text-xs font-mono text-violet-300 leading-relaxed overflow-x-auto scrollbar-thin">{`// ==PrismHubExtension==
// @name         MiExtension
// @version      1.0.0
// @author       TuNombre
// @lang         es
// @license      MIT
// @package      com.tudominio.miextension
// @type         bangumi
// @webSite      https://sitio.com
// ==/PrismHubExtension==

export default class extends Extension {
  async latest(page) { /* [{title, url, cover}] */ }
  async search(kw, page) { /* [{title, url, cover}] */ }
  async detail(url) { /* {title, cover, desc, episodes} */ }
  async watch(url) { /* {type:'hls'|'mp4', url, headers} */ }
}`}</pre>
    ),
  },
  {
    title: '4. API disponible en extensiones',
    content: (
      <div className="overflow-x-auto scrollbar-thin">
        <table className="w-full text-left text-xs md:text-sm min-w-[480px]">
          <thead>
            <tr className="border-b border-white/10">
              <th className="py-2 pr-4 text-white/40 font-normal">Método</th>
              <th className="py-2 text-white/40 font-normal">Descripción</th>
            </tr>
          </thead>
          <tbody className="text-white/60">
            {[
              ["this.request('/ruta')", 'HTTP al webSite base — incluye UA y cookies'],
              ['fetch(url, options)', 'HTTP a cualquier URL externa'],
              ['this.querySelector(html, sel)', 'Selector CSS sobre HTML'],
              ['this.queryXPath(html, xpath)', 'XPath sobre HTML'],
              ['CryptoJS', 'Librería CryptoJS pre-cargada'],
              ['md5(str)', 'Hash MD5'],
            ].map(([fn, desc]) => (
              <tr key={fn} className="border-b border-white/5">
                <td className="py-2 pr-4 font-mono text-violet-400 text-xs whitespace-nowrap">{fn}</td>
                <td className="py-2 text-xs">{desc}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    ),
  },
  {
    title: '5. Repositorios de extensiones',
    content: (
      <div className="space-y-4">
        <div>
          <p className="text-violet-400 text-xs mb-1 font-mono">prism+ — oficial (configurado por defecto)</p>
          <pre className="glass-card rounded-xl px-4 py-2 text-xs font-mono text-white/50 overflow-x-auto scrollbar-thin">https://raw.githubusercontent.com/Litdemonick/prism-plus/main/index.json</pre>
        </div>
        <div>
          <p className="text-white/40 text-xs mb-1 font-mono">comunidad — 150+ extensiones</p>
          <pre className="glass-card rounded-xl px-4 py-2 text-xs font-mono text-white/50 overflow-x-auto scrollbar-thin">https://raw.githubusercontent.com/Litdemonick/Prism_Hub/main/index.json</pre>
        </div>
        <p className="text-white/30 text-xs">Ajustes → Extensiones → URL del repositorio → pegar URL → Recargar</p>
      </div>
    ),
  },
  {
    title: '6. Estructura del repositorio',
    content: (
      <pre className="glass-card rounded-xl px-4 py-3 text-xs font-mono text-violet-300 leading-relaxed">{`Prism_Hub/
├── lib/
│   ├── controllers/    ← Lógica de negocio (GetX)
│   ├── data/services/  ← Runtime JS + Isar DB
│   ├── models/         ← Modelos de datos
│   └── views/          ← UI (páginas y widgets)
├── extensions/         ← 150+ extensiones comunidad
├── assets/i18n/        ← Traducciones (ES, EN, ZH…)
├── install/            ← Scripts Windows / Linux / Arch
├── index.json          ← Catálogo extensiones comunidad
└── pubspec.yaml        ← Dependencias Flutter`}</pre>
    ),
  },
  {
    title: '7. Compilar desde código fuente',
    content: (
      <pre className="glass-card rounded-xl px-4 py-3 text-xs font-mono text-violet-300 leading-relaxed">{`# Requiere Flutter 3.22+
flutter pub get
flutter build windows --release
flutter build apk --release
flutter build linux --release`}</pre>
    ),
  },
];

export default function Docs() {
  return (
    <div className="w-full min-h-screen flex items-start justify-center p-3 md:p-5 bg-[#08080f]">
      <section className="relative w-full max-w-[1536px] min-h-[calc(100vh-1.5rem)] rounded-[1.5rem] md:rounded-[3rem] overflow-hidden flex flex-col items-center">
        <PrismBg />
        <div className="relative z-10 w-full h-full flex flex-col items-center">
          <Navbar />
          <div className="flex-1 w-full max-w-3xl px-6 pb-16 pt-4">
            <motion.div initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.5 }} className="mb-10 text-center">
              <h1 className="text-3xl md:text-5xl font-normal text-white tracking-tight mb-2">Documentación</h1>
              <p className="text-white/30 text-sm">
                PrismHub · Open Source · AGPL-3.0 ·{' '}
                <a href="https://github.com/Litdemonick/Prism_Hub" target="_blank" rel="noopener noreferrer" className="text-violet-400 hover:text-violet-300 transition-colors">GitHub</a>
              </p>
            </motion.div>
            <div className="flex flex-col gap-4">
              {sections.map((section, i) => (
                <motion.div key={i} initial={{ opacity: 0, y: 16 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.4, delay: i * 0.05 }} className="rounded-2xl glass-card px-6 py-5">
                  <h2 className="text-white text-base md:text-lg font-normal mb-4">{section.title}</h2>
                  <div className="text-white/60 text-xs md:text-sm font-normal leading-relaxed">{section.content}</div>
                </motion.div>
              ))}
            </div>
          </div>
        </div>
      </section>
    </div>
  );
}
