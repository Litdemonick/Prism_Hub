import { motion } from 'motion/react';
import { ArrowUpRight, Code2, Puzzle, GitPullRequest, Bug } from 'lucide-react';
import Layout from '../components/Layout';
import { useLang } from '../lib/i18n';

const template = `// ==PrismHubExtension==
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
    return [{ title: '...', url: '...', cover: '...' }];
  }

  async search(kw, page, filter) {
    const html = await this.request(\`/buscar/\${encodeURIComponent(kw)}?p=\${page}\`);
    return [{ title: '...', url: '...', cover: '...' }];
  }

  async createFilter() {
    return { genero: { title: 'Género', options: { '': 'Todos', accion: 'Acción' }, default: '', min: 1, max: 1 } };
  }

  async detail(url) {
    const html = await this.request(url);
    return {
      title: '...', cover: '...', desc: '...',
      episodes: [{ title: 'Episodios', urls: [{ name: 'EP 01', url: '...' }] }]
    };
  }

  async watch(url) {
    return { type: 'hls', url: '...', headers: { Referer: this.webSite } };
  }
}`;

const failover = `async watch(url) {
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
}`;

const extensionTypes = [
  { type: 'bangumi', watch: "{ type: 'hls'|'mp4', url, headers }" },
  { type: 'manga', watch: "{ urls: ['img1', 'img2'], headers }" },
  { type: 'fikushon', watch: "{ title, content: ['párrafo...'] }" },
];

const copy = {
  es: {
    title: 'Cómo funcionan',
    titleAccent: 'las extensiones',
    subtitle: 'Documentación técnica de prism+, el repositorio oficial que arma y mantiene el catálogo de PrismHub — no algo que el usuario instale por su cuenta.',
    repoNote: 'Todo el contenido que ves en PrismHub sale de acá:',
    repoLink: 'github.com/Litdemonick/prism-plus →',
    templateTitle: 'Plantilla base',
    typesTitle: 'Tipos de extensión (@type)',
    typeLabels: { bangumi: 'Anime / Series', manga: 'Manga / Cómic', fikushon: 'Novela' } as Record<string, string>,
    failoverTitle: 'Multi-servidor con failover automático',
    failoverDesc: 'Si el servidor principal falla, el reproductor lee X-Servers y cambia automáticamente.',
    contributeTitle: 'Cómo contribuir',
    contribute: [
      { icon: Bug, title: 'Reportar bugs', desc: 'Abrí un issue en GitHub con los pasos para reproducir el problema.', href: 'https://github.com/Litdemonick/Prism_Hub/issues' },
      { icon: Puzzle, title: 'Sumar un sitio nuevo', desc: 'Implementá latest(), search(), detail() y watch() y proponelo como código en el repositorio de prism+ — si se acepta, pasa a formar parte del catálogo oficial para todos.', href: 'https://github.com/Litdemonick/prism-plus' },
      { icon: GitPullRequest, title: 'Pull requests', desc: 'Mejoras de rendimiento, funciones nuevas o traducciones al código de la app son bienvenidas.', href: 'https://github.com/Litdemonick/Prism_Hub/pulls' },
      { icon: Code2, title: 'Ver el código real', desc: 'prism+ es el catálogo oficial que usa la app — mirá el código fuente de sus extensiones ahí.', href: 'https://github.com/Litdemonick/prism-plus' },
    ],
  },
  en: {
    title: 'How',
    titleAccent: 'extensions work',
    subtitle: "Technical documentation for prism+, the official repository that builds and maintains PrismHub's catalog — not something a user installs on their own.",
    repoNote: 'Every piece of content you see in PrismHub comes from here:',
    repoLink: 'github.com/Litdemonick/prism-plus →',
    templateTitle: 'Base template',
    typesTitle: 'Extension types (@type)',
    typeLabels: { bangumi: 'Anime / Series', manga: 'Manga / Comic', fikushon: 'Novel' } as Record<string, string>,
    failoverTitle: 'Multi-server with automatic failover',
    failoverDesc: 'If the main server fails, the player reads X-Servers and switches on its own.',
    contributeTitle: 'How to contribute',
    contribute: [
      { icon: Bug, title: 'Report bugs', desc: 'Open a GitHub issue with steps to reproduce the problem.', href: 'https://github.com/Litdemonick/Prism_Hub/issues' },
      { icon: Puzzle, title: 'Add a new site', desc: 'Implement latest(), search(), detail() and watch() and propose it as code in the prism+ repository — if accepted, it becomes part of the official catalog for everyone.', href: 'https://github.com/Litdemonick/prism-plus' },
      { icon: GitPullRequest, title: 'Pull requests', desc: 'Performance improvements, new features or translations to the app code are welcome.', href: 'https://github.com/Litdemonick/Prism_Hub/pulls' },
      { icon: Code2, title: 'See the real code', desc: "prism+ is the official catalog the app uses — check out its extensions' source there.", href: 'https://github.com/Litdemonick/prism-plus' },
    ],
  },
} as const;

export default function Developers() {
  const { lang } = useLang();
  const c = copy[lang];

  return (
    <Layout>
      <section className="px-5 py-16 md:px-10 md:py-24">
        <div className="mx-auto max-w-3xl">
          <motion.div initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.5 }} className="mb-10 text-center">
            <h1 className="mb-2 font-[family-name:var(--font-display)] text-3xl font-bold tracking-tight md:text-5xl">
              {c.title} <span className="text-spectrum">{c.titleAccent}</span>
            </h1>
            <p className="text-sm" style={{ color: 'var(--text-faint)' }}>{c.subtitle}</p>
            <p className="mt-4 text-sm">
              <span style={{ color: 'var(--text-muted)' }}>{c.repoNote}</span>{' '}
              <a
                href="https://github.com/Litdemonick/prism-plus"
                target="_blank"
                rel="noopener noreferrer"
                className="font-semibold underline"
                style={{ color: 'var(--accent)' }}
              >
                {c.repoLink}
              </a>
            </p>
          </motion.div>

          <motion.div initial={{ opacity: 0, y: 16 }} whileInView={{ opacity: 1, y: 0 }} viewport={{ once: true }} transition={{ duration: 0.4 }} className="surface mb-4 rounded-2xl px-6 py-5">
            <h2 className="mb-4 font-[family-name:var(--font-display)] text-base font-semibold">{c.templateTitle}</h2>
            <pre className="scrollbar-thin overflow-x-auto text-xs leading-relaxed" style={{ color: 'var(--accent)' }}>{template}</pre>
          </motion.div>

          <motion.div initial={{ opacity: 0, y: 16 }} whileInView={{ opacity: 1, y: 0 }} viewport={{ once: true }} transition={{ duration: 0.4, delay: 0.05 }} className="surface mb-4 rounded-2xl px-6 py-5">
            <h2 className="mb-4 font-[family-name:var(--font-display)] text-base font-semibold">{c.typesTitle}</h2>
            <div className="flex flex-col gap-3">
              {extensionTypes.map((et) => (
                <div key={et.type} className="flex flex-col gap-2 sm:flex-row sm:items-center">
                  <code className="w-fit rounded px-2 py-1 font-mono text-xs" style={{ background: 'color-mix(in srgb, var(--accent) 14%, transparent)', color: 'var(--accent)' }}>
                    {et.type}
                  </code>
                  <span className="text-xs" style={{ color: 'var(--text-faint)' }}>{c.typeLabels[et.type]}</span>
                  <code className="font-mono text-xs" style={{ color: 'var(--text-faint)' }}>{et.watch}</code>
                </div>
              ))}
            </div>
          </motion.div>

          <motion.div initial={{ opacity: 0, y: 16 }} whileInView={{ opacity: 1, y: 0 }} viewport={{ once: true }} transition={{ duration: 0.4, delay: 0.1 }} className="surface mb-8 rounded-2xl px-6 py-5">
            <h2 className="mb-4 font-[family-name:var(--font-display)] text-base font-semibold">{c.failoverTitle}</h2>
            <pre className="scrollbar-thin overflow-x-auto text-xs leading-relaxed" style={{ color: 'var(--accent)' }}>{failover}</pre>
            <p className="mt-3 text-xs" style={{ color: 'var(--text-faint)' }}>{c.failoverDesc}</p>
          </motion.div>

          <motion.div initial={{ opacity: 0, y: 16 }} whileInView={{ opacity: 1, y: 0 }} viewport={{ once: true }} transition={{ duration: 0.4, delay: 0.15 }}>
            <h2 className="mb-4 text-center font-[family-name:var(--font-display)] text-base font-semibold">{c.contributeTitle}</h2>
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
              {c.contribute.map(({ icon: Icon, title, desc, href }) => (
                <a
                  key={title}
                  href={href}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="surface group block rounded-2xl px-5 py-4 transition-transform hover:scale-[1.015]"
                >
                  <div className="mb-2 flex items-center gap-3">
                    <div className="rounded-lg p-2" style={{ background: 'var(--surface-2)', color: 'var(--accent)' }}>
                      <Icon className="h-4 w-4" />
                    </div>
                    <span className="text-sm font-semibold">{title}</span>
                    <ArrowUpRight className="ml-auto h-3.5 w-3.5 opacity-0 transition-opacity group-hover:opacity-70" />
                  </div>
                  <p className="text-xs leading-relaxed" style={{ color: 'var(--text-faint)' }}>{desc}</p>
                </a>
              ))}
            </div>
          </motion.div>
        </div>
      </section>
    </Layout>
  );
}
