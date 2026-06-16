import { motion } from 'motion/react';
import {
  Puzzle, Zap, BookOpen, Star, Tv2, Layers,
  Shield, Globe, Code2, ArrowUpRight, Download, Terminal,
} from 'lucide-react';
import type { ReactElement } from 'react';
import { useNavigate } from 'react-router-dom';
import Hero from '../components/Hero';

/* ── Platform icons ───────────────────────────────────────── */
const WinIcon = () => (
  <svg viewBox="0 0 22 22" className="w-8 h-8" fill="#0ea5e9">
    <rect x="0"  y="0"  width="9.5" height="9.5" rx="1.2"/>
    <rect x="12.5" y="0"  width="9.5" height="9.5" rx="1.2"/>
    <rect x="0"  y="12.5" width="9.5" height="9.5" rx="1.2"/>
    <rect x="12.5" y="12.5" width="9.5" height="9.5" rx="1.2"/>
  </svg>
);

const LinuxIcon = () => (
  <svg viewBox="0 0 448 512" className="w-7 h-7" fill="#f97316">
    <path d="M220.8 123.3c1 .5 1.8 1.7 3 1.7 1.1 0 2.8-.4 2.9-1.5.2-1.4-1.9-2.3-3.2-2.9-1.7-.7-3.9-1-5.5-.1-.4.2-.8.7-.6 1.1.3 1.3 2.3 1.1 3.4 1.7zm-21.9 1.7c1.2 0 2-1.2 3-1.7 1.1-.6 3.1-.4 3.5-1.6.2-.4-.2-.9-.6-1.1-1.6-.9-3.8-.6-5.5.1-1.3.6-3.4 1.5-3.2 2.9.1 1 1.8 1.5 2.8 1.4zM420 403.8c-3.6-4-5.3-11.6-7.2-19.7-1.8-8.1-3.9-16.8-10.5-22.4-1.3-1.1-2.6-2.1-4-2.9-1.3-.8-2.7-1.5-4.1-2 9.2-27.3 5.6-54.5-3.7-79.1-11.4-30.1-31.3-56.4-46.5-74.4-17.1-21.5-33.7-41.9-33.4-72C311.1 85.4 315.7.1 234.8 0 132.4-.2 158 103.4 156.9 135.2c-1.7 23.4-6.4 41.8-22.5 64.7-18.9 22.5-45.5 58.8-58.1 96.7-6 17.9-8.8 36.1-6.2 53.3-6.5 5.8-11.4 14.7-16.6 20.2-4.2 4.3-10.3 5.9-17 8.3s-14 6-18.5 14.5c-2.1 3.9-2.8 8.1-2.8 12.4 0 3.9.6 7.9 1.2 11.8 1.2 8.1 2.5 15.7.8 20.8-5.2 14.4-5.9 24.4-2.2 31.7 3.8 7.3 11.4 10.5 20.1 12.3 17.3 3.6 40.8 2.7 59.3 12.5 19.8 10.4 39.9 14.1 55.9 10.4 11.6-2.6 21.1-9.6 25.9-20.2 12.5-.1 26.3-5.4 48.3-6.6 14.9-1.2 33.6 5.3 55.1 4.1.6 2.3 1.4 4.6 2.5 6.7v.1c8.3 16.7 23.8 24.3 40.3 23 16.6-1.3 34.1-11 48.3-27.9 13.6-16.4 36-23.2 50.9-32.2 7.4-4.5 13.4-10.1 13.9-18.3.4-8.2-4.4-17.3-15.5-29.7z"/>
  </svg>
);

const DroidIcon = () => (
  <svg viewBox="0 0 24 24" className="w-8 h-8" fill="#22c55e">
    <path d="M17.523 15.341A5.036 5.036 0 0 0 17 13v-2a5 5 0 0 0-10 0v2c0 .857-.122 1.476-.523 2.341C6 16 5 17 5 18c0 .553.448 1 1 1h12c.552 0 1-.447 1-1 0-1-1-2-1.477-2.659zM12 23c1.1 0 2-.9 2-2h-4c0 1.1.9 2 2 2zm-1-19.938C8.162 3.553 6 6.027 6 9v.268A3 3 0 0 1 7 9a3 3 0 0 1 3-3c0-.656-.216-1.268-.582-1.765L9 4l.418-.579A2.994 2.994 0 0 1 12 3c1.15 0 2.16.647 2.678 1.597L15.1 4.5l.322.5A3 3 0 0 1 18 9a3 3 0 0 1 1-.268V9c0-2.973-2.162-5.447-5-5.938z"/>
  </svg>
);

/* ── Data ─────────────────────────────────────────────────── */
const stats = [
  { value: '150+', label: 'Extensiones' },
  { value: '3',    label: 'Plataformas' },
  { value: 'v1.0', label: 'Versión estable' },
  { value: '100%', label: 'Open Source' },
];

const features = [
  {
    Icon: Puzzle, title: 'Extensiones JavaScript',
    desc: 'Cualquier fuente de contenido como archivo .js. Sin modificar la app, sin esperar actualizaciones.',
    bg: 'rgba(124,58,237,0.12)', border: 'rgba(124,58,237,0.28)',
  },
  {
    Icon: Zap, title: 'Failover automático',
    desc: 'Si el servidor falla, el player cambia al siguiente al instante. Cero cortes por errores de red.',
    bg: 'rgba(79,70,229,0.12)', border: 'rgba(79,70,229,0.28)',
  },
  {
    Icon: BookOpen, title: 'Historial y progreso',
    desc: 'Seguimiento local por episodio, favoritos y lista de pendientes. Sin cuentas ni servidores externos.',
    bg: 'rgba(6,182,212,0.10)', border: 'rgba(6,182,212,0.24)',
  },
  {
    Icon: Star, title: 'AniList integrado',
    desc: 'Vincula tu cuenta y PrismHub actualiza tu lista automáticamente mientras reproduces.',
    bg: 'rgba(124,58,237,0.12)', border: 'rgba(124,58,237,0.28)',
  },
  {
    Icon: Tv2, title: 'DLNA / Cast a TV',
    desc: 'Transmite directamente a tu televisor DLNA. Pantalla grande sin cables ni configuración extra.',
    bg: 'rgba(79,70,229,0.12)', border: 'rgba(79,70,229,0.28)',
  },
  {
    Icon: Layers, title: 'Multiplataforma nativo',
    desc: 'Compilado nativamente para Windows, Android y Linux. Mismas extensiones en todos tus dispositivos.',
    bg: 'rgba(6,182,212,0.10)', border: 'rgba(6,182,212,0.24)',
  },
];

type Platform = {
  name: string;
  Icon: () => ReactElement;
  color: string;
  shell: string;
  command: string;
  desc: string;
  route?: string;
  href?: string;
};

const platforms: Platform[] = [
  {
    name: 'Windows', Icon: WinIcon, color: '#0ea5e9',
    shell: 'PowerShell',
    command: 'irm https://raw.githubusercontent.com/Litdemonick/Prism_Hub/main/install/install.ps1 | iex',
    desc: 'Instalador .exe de un clic. Windows 10 / 11 (64 bits).',
    route: '/windows',
  },
  {
    name: 'Linux', Icon: LinuxIcon, color: '#f97316',
    shell: 'Bash',
    command: 'curl -fsSL https://raw.githubusercontent.com/Litdemonick/Prism_Hub/main/install/install.sh | bash',
    desc: 'Script universal. También disponible PKGBUILD para Arch.',
    route: '/linux',
  },
  {
    name: 'Android', Icon: DroidIcon, color: '#22c55e',
    shell: 'APK directo',
    command: 'Descarga el APK firmado desde GitHub Releases e instálalo.',
    desc: 'APK firmado. Android 5.0+. Activa "Fuentes desconocidas".',
    href: 'https://github.com/Litdemonick/Prism_Hub/releases/latest',
  },
];

/* ── Syntax-highlighted code (hardcoded, safe for dangerouslySetInnerHTML) ─ */
const codeHtml = `<span style="color:#6366f1">// ==PrismHubExtension==</span>
<span style="color:#94a3b8">// @name</span>    <span style="color:#a78bfa">MiExtension</span>
<span style="color:#94a3b8">// @version</span> <span style="color:#67e8f9">1.0.0</span>
<span style="color:#94a3b8">// @author</span>  <span style="color:#67e8f9">TuNombre</span>
<span style="color:#94a3b8">// @lang</span>    <span style="color:#f472b6">es</span>
<span style="color:#94a3b8">// @type</span>    <span style="color:#f472b6">bangumi</span>
<span style="color:#94a3b8">// @webSite</span> <span style="color:#67e8f9">https://sitio.com</span>
<span style="color:#6366f1">// ==/PrismHubExtension==</span>

<span style="color:#818cf8">export default class</span> <span style="color:#a78bfa">extends</span> Extension {
  <span style="color:#818cf8">async</span> <span style="color:#67e8f9">latest</span>(page) {
    <span style="color:#4b5563">/* → [{title, url, cover}] */</span>
  }
  <span style="color:#818cf8">async</span> <span style="color:#67e8f9">search</span>(kw, page) {
    <span style="color:#4b5563">/* → [{title, url, cover}] */</span>
  }
  <span style="color:#818cf8">async</span> <span style="color:#67e8f9">detail</span>(url) {
    <span style="color:#4b5563">/* → {title, episodes:[...]} */</span>
  }
  <span style="color:#818cf8">async</span> <span style="color:#67e8f9">watch</span>(url) {
    <span style="color:#4b5563">/* → {type:'hls'|'mp4', url} */</span>
  }
}`;

/* ── Animation preset ────────────────────────────────────── */
const fadeUp = (delay = 0) => ({
  initial: { opacity: 0, y: 40 },
  whileInView: { opacity: 1, y: 0 },
  viewport: { once: true, margin: '-80px' } as const,
  transition: { duration: 0.7, delay },
});

/* ── Home ────────────────────────────────────────────────── */
export default function Home() {
  const navigate = useNavigate();

  return (
    <div className="bg-[#08080f] overflow-x-hidden">

      {/* ───── HERO ───── */}
      <Hero />

      {/* ───── STATS BAR ───── */}
      <motion.section {...fadeUp()} className="border-y border-white/[0.05] py-12">
        <div className="max-w-5xl mx-auto px-6 grid grid-cols-2 md:grid-cols-4 gap-6 text-center">
          {stats.map((s) => (
            <div key={s.label}>
              <div className="text-3xl md:text-4xl font-light prism-text mb-1">{s.value}</div>
              <div className="text-[11px] text-white/30 tracking-widest uppercase">{s.label}</div>
            </div>
          ))}
        </div>
      </motion.section>

      {/* ───── FEATURES ───── */}
      <section className="relative py-32 px-6">
        <div className="absolute inset-0 bg-gradient-to-b from-transparent via-violet-950/8 to-transparent pointer-events-none" />
        <div className="max-w-6xl mx-auto">
          <motion.div {...fadeUp()} className="text-center mb-20">
            <span className="section-badge">✦  Características</span>
            <h2 className="text-4xl md:text-5xl lg:text-[58px] font-light text-white leading-tight mt-5 mb-5">
              Todo lo que necesitas<br/>
              <span className="prism-text">sin compromisos</span>
            </h2>
            <p className="text-white/40 max-w-md mx-auto text-base leading-relaxed">
              Motor de extensiones JS, reproducción robusta y tracking integrado. Todo nativo, todo local.
            </p>
          </motion.div>

          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
            {features.map((f, i) => (
              <motion.div
                key={f.title}
                initial={{ opacity: 0, y: 30 }}
                whileInView={{ opacity: 1, y: 0 }}
                viewport={{ once: true, margin: '-60px' }}
                transition={{ duration: 0.5, delay: i * 0.08 }}
                whileHover={{ y: -5, transition: { duration: 0.2 } }}
                className="card-glow rounded-2xl p-7 group cursor-default"
              >
                <div
                  className="w-12 h-12 rounded-xl flex items-center justify-center mb-5 transition-transform duration-300 group-hover:scale-110"
                  style={{ background: f.bg, border: `1px solid ${f.border}` }}
                >
                  <f.Icon className="w-5 h-5 text-violet-200" />
                </div>
                <h3 className="text-white text-[15px] font-normal mb-2">{f.title}</h3>
                <p className="text-white/40 text-[13px] leading-relaxed">{f.desc}</p>
              </motion.div>
            ))}
          </div>
        </div>
      </section>

      {/* ───── DIVIDER ───── */}
      <div className="glow-line max-w-4xl mx-6 md:mx-auto" />

      {/* ───── PLATFORMS ───── */}
      <section className="relative py-32 px-6">
        <div className="max-w-6xl mx-auto">
          <motion.div {...fadeUp()} className="text-center mb-20">
            <span className="section-badge">↓  Instalación</span>
            <h2 className="text-4xl md:text-5xl lg:text-[58px] font-light text-white leading-tight mt-5 mb-5">
              Un solo comando<br/>
              <span className="prism-text">en todas las plataformas</span>
            </h2>
            <p className="text-white/40 max-w-md mx-auto text-base leading-relaxed">
              Scripts de instalación automáticos para Windows y Linux. APK directo para Android.
            </p>
          </motion.div>

          <div className="grid grid-cols-1 md:grid-cols-3 gap-5">
            {platforms.map((p, i) => (
              <motion.div
                key={p.name}
                initial={{ opacity: 0, y: 40 }}
                whileInView={{ opacity: 1, y: 0 }}
                viewport={{ once: true, margin: '-60px' }}
                transition={{ duration: 0.6, delay: i * 0.12 }}
                whileHover={{ y: -8, transition: { duration: 0.25 } }}
                className="card-glow rounded-3xl p-7 flex flex-col gap-5"
              >
                {/* Header */}
                <div className="flex items-center gap-4">
                  <div
                    className="w-14 h-14 rounded-2xl flex items-center justify-center shrink-0"
                    style={{ background: `${p.color}18`, border: `1px solid ${p.color}35` }}
                  >
                    <p.Icon />
                  </div>
                  <div>
                    <div className="text-white text-lg font-light">{p.name}</div>
                    <div className="text-white/30 text-xs mt-0.5 leading-snug">{p.desc}</div>
                  </div>
                </div>

                {/* Command */}
                <div className="code-block p-4 flex-1">
                  <div className="text-white/20 text-[10px] font-mono mb-2 tracking-wider uppercase">{p.shell}</div>
                  <p
                    className="text-[11.5px] font-mono leading-relaxed break-all"
                    style={{ color: `${p.color}cc` }}
                  >
                    {p.command}
                  </p>
                </div>

                {/* Button */}
                <motion.button
                  whileHover={{ scale: 1.02 }}
                  whileTap={{ scale: 0.97 }}
                  onClick={() => p.route ? navigate(p.route) : window.open(p.href!, '_blank')}
                  className="flex items-center justify-center gap-2 w-full py-3 rounded-xl text-sm font-light transition-all duration-300 btn-glow"
                  style={{ background: `${p.color}12`, border: `1px solid ${p.color}32`, color: p.color }}
                >
                  <Download className="w-4 h-4" />
                  Instalar en {p.name}
                </motion.button>
              </motion.div>
            ))}
          </div>
        </div>
      </section>

      {/* ───── DIVIDER ───── */}
      <div className="glow-line max-w-4xl mx-6 md:mx-auto" />

      {/* ───── EXTENSIONS ───── */}
      <section className="relative py-32 px-6">
        <div className="absolute inset-0 bg-gradient-to-b from-transparent via-indigo-950/8 to-transparent pointer-events-none" />
        <div className="max-w-6xl mx-auto">
          <motion.div {...fadeUp()} className="text-center mb-20">
            <span className="section-badge">⬡  Extensiones</span>
            <h2 className="text-4xl md:text-5xl lg:text-[58px] font-light text-white leading-tight mt-5 mb-5">
              Ecosistema abierto<br/>
              <span className="prism-text">de extensiones JS</span>
            </h2>
            <p className="text-white/40 max-w-md mx-auto text-base leading-relaxed">
              Dos repositorios listos para usar o crea las tuyas en minutos con la API estándar.
            </p>
          </motion.div>

          <div className="grid grid-cols-1 lg:grid-cols-2 gap-8 items-start">

            {/* Code preview */}
            <motion.div
              initial={{ opacity: 0, x: -30 }}
              whileInView={{ opacity: 1, x: 0 }}
              viewport={{ once: true }}
              transition={{ duration: 0.7 }}
              className="card-glow rounded-2xl overflow-hidden"
            >
              <div className="flex items-center gap-2 px-5 py-3 border-b border-white/[0.05] bg-white/[0.015]">
                <div className="w-3 h-3 rounded-full bg-red-500/40" />
                <div className="w-3 h-3 rounded-full bg-yellow-500/40" />
                <div className="w-3 h-3 rounded-full bg-green-500/40" />
                <span className="text-white/20 text-xs ml-3 font-mono">miExtension.js</span>
              </div>
              <pre
                className="p-6 text-[12.5px] leading-[1.85] font-mono overflow-x-auto scrollbar-thin m-0 bg-transparent"
                dangerouslySetInnerHTML={{ __html: codeHtml }}
              />
            </motion.div>

            {/* Repos + dev CTA */}
            <motion.div
              initial={{ opacity: 0, x: 30 }}
              whileInView={{ opacity: 1, x: 0 }}
              viewport={{ once: true }}
              transition={{ duration: 0.7, delay: 0.1 }}
              className="flex flex-col gap-4"
            >
              {/* prism+ */}
              <div className="card-glow rounded-2xl p-6">
                <div className="flex items-center gap-3 mb-3">
                  <div className="w-10 h-10 rounded-xl bg-violet-500/12 border border-violet-500/20 flex items-center justify-center">
                    <Shield className="w-4 h-4 text-violet-400" />
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="text-white text-sm">prism+ · Oficial</div>
                    <div className="text-white/30 text-xs">TioAnime, AnimeFLV, MonosChinos, MangaDex…</div>
                  </div>
                  <span className="shrink-0 text-[10px] px-2.5 py-1 rounded-full bg-violet-500/10 border border-violet-500/20 text-violet-300">
                    Preinstalado
                  </span>
                </div>
                <p className="text-white/35 text-xs leading-relaxed mb-3">
                  Extensiones creadas por el equipo PrismHub. Enfocadas en español. Vienen activas por defecto en la app.
                </p>
                <div className="code-block px-3 py-2 text-[10px] font-mono text-violet-300/55 break-all">
                  raw.githubusercontent.com/Litdemonick/prism-plus/main/index.json
                </div>
              </div>

              {/* Comunidad */}
              <div className="card-glow rounded-2xl p-6">
                <div className="flex items-center gap-3 mb-3">
                  <div className="w-10 h-10 rounded-xl bg-cyan-500/10 border border-cyan-500/20 flex items-center justify-center">
                    <Globe className="w-4 h-4 text-cyan-400" />
                  </div>
                  <div>
                    <div className="text-white text-sm">Comunidad</div>
                    <div className="text-white/30 text-xs">150+ extensiones · multi-idioma</div>
                  </div>
                </div>
                <p className="text-white/35 text-xs leading-relaxed mb-3">
                  Anime, manga, novelas y películas de la comunidad. Múltiples idiomas. En constante crecimiento.
                </p>
                <div className="code-block px-3 py-2 text-[10px] font-mono text-cyan-300/55 break-all">
                  raw.githubusercontent.com/Litdemonick/Prism_Hub/main/index.json
                </div>
              </div>

              {/* Dev CTA */}
              <motion.button
                whileHover={{ y: -3, transition: { duration: 0.2 } }}
                onClick={() => navigate('/developers')}
                className="card-glow rounded-2xl p-5 flex items-center justify-between w-full group btn-glow"
              >
                <div className="flex items-center gap-3">
                  <div className="w-10 h-10 rounded-xl bg-white/5 border border-white/10 flex items-center justify-center">
                    <Code2 className="w-4 h-4 text-violet-300" />
                  </div>
                  <div className="text-left">
                    <div className="text-white text-sm">Crea tu extensión</div>
                    <div className="text-white/30 text-xs">Guía completa · API disponible</div>
                  </div>
                </div>
                <ArrowUpRight className="w-4 h-4 text-white/20 group-hover:text-violet-400 transition-colors" />
              </motion.button>
            </motion.div>
          </div>
        </div>
      </section>

      {/* ───── CTA ───── */}
      <section className="py-32 px-6">
        <div className="max-w-3xl mx-auto">
          <motion.div {...fadeUp()}>
            <div className="card-glow rounded-3xl p-10 md:p-16 relative overflow-hidden text-center">
              <div className="absolute -top-32 -left-32 w-80 h-80 rounded-full bg-violet-600/10 blur-3xl pointer-events-none" />
              <div className="absolute -bottom-32 -right-32 w-80 h-80 rounded-full bg-cyan-600/8 blur-3xl pointer-events-none" />
              <div className="relative z-10">
                <span className="section-badge mb-6 inline-flex">★  Descarga gratuita</span>
                <h2 className="text-4xl md:text-5xl font-light text-white mb-4 leading-tight">
                  Empieza ahora.<br/>
                  <span className="prism-text">Es gratis para siempre.</span>
                </h2>
                <p className="text-white/40 mb-10 text-base max-w-sm mx-auto leading-relaxed">
                  Open source bajo AGPL-3.0. Sin suscripciones, sin anuncios, sin servidores propios.
                </p>
                <div className="flex items-center justify-center gap-4 flex-wrap">
                  <motion.a
                    href="https://github.com/Litdemonick/Prism_Hub"
                    target="_blank"
                    rel="noopener noreferrer"
                    whileHover={{ scale: 1.04 }}
                    whileTap={{ scale: 0.97 }}
                    className="flex items-center gap-2 px-8 py-3.5 rounded-full bg-white text-[#08080f] text-sm hover:bg-violet-100 transition-colors btn-glow"
                  >
                    <ArrowUpRight className="w-4 h-4" />
                    Ver en GitHub
                  </motion.a>
                  <motion.button
                    onClick={() => navigate('/docs')}
                    whileHover={{ scale: 1.04 }}
                    whileTap={{ scale: 0.97 }}
                    className="flex items-center gap-2 px-8 py-3.5 rounded-full border border-white/10 text-white/60 hover:text-white hover:border-violet-500/30 text-sm transition-all"
                  >
                    <Terminal className="w-4 h-4" />
                    Documentación
                  </motion.button>
                </div>
              </div>
            </div>
          </motion.div>

          <motion.p
            initial={{ opacity: 0 }}
            whileInView={{ opacity: 1 }}
            viewport={{ once: true }}
            transition={{ duration: 0.6, delay: 0.4 }}
            className="text-center text-white/18 text-xs mt-10"
          >
            © 2026 Soul_Of_The_sun · AGPL-3.0 ·{' '}
            <a
              href="https://github.com/Litdemonick"
              className="hover:text-white/45 transition-colors underline underline-offset-2"
            >
              github.com/Litdemonick
            </a>
          </motion.p>
        </div>
      </section>

    </div>
  );
}
