import { motion } from 'motion/react';
import { ArrowUpRight, Code2, Puzzle, GitPullRequest, Bug } from 'lucide-react';
import Navbar from '../components/Navbar';
import PrismBg from '../components/PrismBg';

const extensionTypes = [
  { type: 'bangumi', label: 'Anime / Series', watch: "{ type: 'hls'|'mp4', url, headers }" },
  { type: 'manga',   label: 'Manga / Cómic',  watch: "{ urls: ['img1', 'img2'], headers }" },
  { type: 'fikushon',label: 'Novela',          watch: "{ title, content: ['párrafo...'] }" },
];

const contribute = [
  { icon: Bug,           title: 'Reportar bugs',         desc: 'Abre un issue en GitHub con pasos para reproducir el problema.', href: 'https://github.com/Litdemonick/Prism_Hub/issues' },
  { icon: Puzzle,        title: 'Crear extensiones',     desc: 'Implementa latest(), search(), detail() y watch() para un nuevo sitio.', href: 'https://github.com/Litdemonick/prism-plus' },
  { icon: GitPullRequest,title: 'Pull Requests',         desc: 'Mejoras de rendimiento, nuevas features o traducciones son bienvenidas.', href: 'https://github.com/Litdemonick/Prism_Hub/pulls' },
  { icon: Code2,         title: 'Escribir extensiones',  desc: 'Publica tus extensiones en el repo prism+ oficial o en tu propio repo.', href: 'https://github.com/Litdemonick/prism-plus' },
];

export default function Developers() {
  return (
    <div className="w-full min-h-screen flex items-start justify-center p-3 md:p-5 bg-[#08080f]">
      <section className="relative w-full max-w-[1536px] min-h-[calc(100vh-1.5rem)] rounded-[1.5rem] md:rounded-[3rem] overflow-hidden flex flex-col items-center">
        <PrismBg />
        <div className="relative z-10 w-full h-full flex flex-col items-center">
          <Navbar />
          <div className="flex-1 w-full max-w-3xl px-6 pb-16 pt-4">
            <motion.div initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.5 }} className="mb-10 text-center">
              <h1 className="text-3xl md:text-5xl font-normal text-white tracking-tight mb-2">
                Crea <span className="prism-text">extensiones</span>
              </h1>
              <p className="text-white/30 text-sm">Guía para desarrolladores de extensiones PrismHub</p>
            </motion.div>

            {/* Template */}
            <motion.div initial={{ opacity: 0, y: 16 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.4, delay: 0.1 }} className="glass-card rounded-2xl px-6 py-5 mb-4">
              <h2 className="text-white text-base font-normal mb-4">Plantilla base</h2>
              <pre className="text-xs font-mono text-violet-300 leading-relaxed overflow-x-auto scrollbar-thin">{`// ==PrismHubExtension==
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
  async latest(page) {
    const html = await this.request(\`/directorio?p=\${page}\`);
    // parsear html y retornar lista
    return [{ title: '...', url: '...', cover: '...' }];
  }

  async search(kw, page) {
    const html = await this.request(\`/buscar/\${encodeURIComponent(kw)}?p=\${page}\`);
    return [{ title: '...', url: '...', cover: '...' }];
  }

  async detail(url) {
    const html = await this.request(url);
    return {
      title: '...', cover: '...', desc: '...',
      episodes: [{ title: 'Episodios', urls: [{ name: 'EP 01', url: '...' }] }]
    };
  }

  async watch(url) {
    // retornar URL de stream directa
    return { type: 'hls', url: '...', headers: { Referer: this.webSite } };
  }
}`}</pre>
            </motion.div>

            {/* Types */}
            <motion.div initial={{ opacity: 0, y: 16 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.4, delay: 0.2 }} className="glass-card rounded-2xl px-6 py-5 mb-4">
              <h2 className="text-white text-base font-normal mb-4">Tipos de extensión (@type)</h2>
              <div className="flex flex-col gap-3">
                {extensionTypes.map(et => (
                  <div key={et.type} className="flex flex-col sm:flex-row sm:items-center gap-2">
                    <code className="text-violet-400 text-xs font-mono bg-violet-500/10 px-2 py-1 rounded w-fit">{et.type}</code>
                    <span className="text-white/40 text-xs">{et.label}</span>
                    <code className="text-white/30 text-xs font-mono">{et.watch}</code>
                  </div>
                ))}
              </div>
            </motion.div>

            {/* Failover */}
            <motion.div initial={{ opacity: 0, y: 16 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.4, delay: 0.3 }} className="glass-card rounded-2xl px-6 py-5 mb-8">
              <h2 className="text-white text-base font-normal mb-4">Multi-servidor con failover automático</h2>
              <pre className="text-xs font-mono text-violet-300 leading-relaxed overflow-x-auto scrollbar-thin">{`async watch(url) {
  const servidores = { 'Servidor2': embedUrl2, 'Servidor3': embedUrl3 };
  return {
    type: 'hls',
    url: primaryUrl,
    headers: {
      'Referer': this.webSite,
      'X-Servers': JSON.stringify(servidores),
      'X-Primary-Server': 'Servidor1',
    }
  };
}`}</pre>
              <p className="text-white/30 text-xs mt-3">Si el servidor principal falla, el player lee <code className="text-violet-400">X-Servers</code> y cambia automáticamente.</p>
            </motion.div>

            {/* Contribute */}
            <motion.div initial={{ opacity: 0, y: 16 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.4, delay: 0.4 }}>
              <h2 className="text-white text-base font-normal mb-4 text-center">Cómo contribuir</h2>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                {contribute.map(({ icon: Icon, title, desc, href }) => (
                  <a key={title} href={href} target="_blank" rel="noopener noreferrer"
                    className="glass-card rounded-2xl px-5 py-4 hover:border-violet-500/20 transition-all group block">
                    <div className="flex items-center gap-3 mb-2">
                      <div className="bg-violet-500/10 p-2 rounded-lg">
                        <Icon className="w-4 h-4 text-violet-400" />
                      </div>
                      <span className="text-white text-sm font-normal">{title}</span>
                      <ArrowUpRight className="w-3.5 h-3.5 text-white/20 group-hover:text-violet-400 transition-colors ml-auto" />
                    </div>
                    <p className="text-white/40 text-xs leading-relaxed">{desc}</p>
                  </a>
                ))}
              </div>
            </motion.div>
          </div>
        </div>
      </section>
    </div>
  );
}
