import { motion } from 'motion/react';
import { Link } from 'react-router-dom';
import { useEffect, useState } from 'react';
import { ArrowUpRight, Download, GitFork, Check, ZoomIn, X } from 'lucide-react';
import Layout from '../components/Layout';
import DeveloperNote from '../components/DeveloperNote';
import RequirementsTable from '../components/RequirementsTable';
import { WindowsIcon, LinuxIcon, AndroidIcon, AndroidTvIcon } from '../components/PlatformIcons';
import { useLang } from '../lib/i18n';
import {
  APP_VERSION,
  detectPlatform,
  formatSize,
  useExtensionCount,
  useLatestRelease,
  type DownloadPlatform,
} from '../lib/githubRelease';

// Se lee UNA sola vez, al cargar el módulo — no en el cuerpo de un
// componente. Date.now() ahí es una función impura (el linter de React lo
// marca, incluso dentro de useMemo/useEffect), pero acá arriba nunca se
// vuelve a llamar en cada render: es una constante fija para toda la
// sesión de la pestaña, que es lo único que hace falta para decidir si una
// versión sigue siendo "nueva".
const PAGE_LOAD_TIME = Date.now();
const DIAS_PARA_DEJAR_DE_SER_NUEVO = 3;

const fadeUp = {
  initial: { opacity: 0, y: 18 },
  whileInView: { opacity: 1, y: 0 },
  viewport: { once: true, margin: '-60px' },
  transition: { duration: 0.5, ease: 'easeOut' as const },
};

function Eyebrow({ children }: { children: React.ReactNode }) {
  return (
    <div
      className="mb-4 inline-flex items-center gap-2 rounded-full border px-3.5 py-1 text-[11px] font-semibold uppercase tracking-[0.14em]"
      style={{ borderColor: 'var(--border)', color: 'var(--accent)' }}
    >
      {children}
    </div>
  );
}

function Hero() {
  const { t } = useLang();
  const extensionCount = useExtensionCount();
  const release = useLatestRelease();
  // Con qué sistema llega quien mira la página. El botón principal manda
  // DIRECTO a la página de instrucciones de ESE sistema — no descarga un
  // archivo de una: la idea es que la gente lea antes de instalar (el aviso
  // del desarrollador, el paso a paso) y no adivine cuál de las tarjetas de
  // "descargar" de más abajo es la suya.
  const platform = detectPlatform();
  const platformHref =
    platform === 'windows' ? '/windows' : platform === 'linux' ? '/linux' : platform === 'android' ? '/android' : null;
  const ctaLabel =
    platform === 'windows' ? t('hero.cta.windows')
    : platform === 'linux' ? t('hero.cta.linux')
    : platform === 'android' ? t('hero.cta.android')
    : t('hero.cta.download');

  return (
    <section className="relative overflow-hidden px-5 pb-20 pt-10 md:px-10 md:pb-28 md:pt-16">
      <div className="grain absolute inset-x-0 top-0 h-[560px]" />
      <div className="relative mx-auto flex max-w-4xl flex-col items-center text-center">
        <motion.div initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.5 }}>
          <Eyebrow>{t('hero.badge')}</Eyebrow>
        </motion.div>

        <motion.h1
          initial={{ opacity: 0, y: 16 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.6, delay: 0.05 }}
          className="font-[family-name:var(--font-display)] text-[2.4rem] font-bold leading-[1.08] tracking-tight sm:text-5xl md:text-6xl"
        >
          {t('hero.title.1')}
          <br />
          <span className="text-spectrum">{t('hero.title.2')}</span>
        </motion.h1>

        <motion.p
          initial={{ opacity: 0, y: 16 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.6, delay: 0.12 }}
          className="mt-6 max-w-xl text-balance text-base leading-relaxed sm:text-lg"
          style={{ color: 'var(--text-muted)' }}
        >
          {t('hero.subtitle')}
        </motion.p>

        <motion.div
          initial={{ opacity: 0, y: 16 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.6, delay: 0.18 }}
          className="mt-9 flex flex-wrap items-center justify-center gap-3"
        >
          {platformHref ? (
            <Link
              to={platformHref}
              className="flex items-center gap-2 rounded-full px-6 py-3.5 text-sm font-semibold shadow-lg transition-transform hover:scale-[1.03] active:scale-[0.98]"
              style={{ background: 'var(--accent)', color: 'var(--accent-ink)' }}
            >
              <Download className="h-4 w-4" />
              {ctaLabel}
            </Link>
          ) : (
            <button
              type="button"
              onClick={() => document.getElementById('descargar')?.scrollIntoView({ behavior: 'smooth' })}
              className="flex items-center gap-2 rounded-full px-6 py-3.5 text-sm font-semibold shadow-lg transition-transform hover:scale-[1.03] active:scale-[0.98]"
              style={{ background: 'var(--accent)', color: 'var(--accent-ink)' }}
            >
              <Download className="h-4 w-4" />
              {ctaLabel}
            </button>
          )}
          <a
            href="https://github.com/Litdemonick/Prism_Hub"
            target="_blank"
            rel="noopener noreferrer"
            className="flex items-center gap-2 rounded-full border px-6 py-3.5 text-sm font-semibold transition-transform hover:scale-[1.03] active:scale-[0.98]"
            style={{ borderColor: 'var(--border-strong)' }}
          >
            <GitFork className="h-4 w-4" />
            {t('hero.cta.source')}
          </a>
        </motion.div>

        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ duration: 0.6, delay: 0.3 }}
          className="mt-14 grid w-full max-w-lg grid-cols-3 gap-4 border-t pt-8"
          style={{ borderColor: 'var(--border)' }}
        >
          <div>
            <div className="font-[family-name:var(--font-display)] text-2xl font-bold">
              {extensionCount ?? '20+'}
            </div>
            <div className="mt-1 text-xs" style={{ color: 'var(--text-faint)' }}>{t('hero.stat.extensions')}</div>
          </div>
          <div>
            <div className="font-[family-name:var(--font-display)] text-2xl font-bold">3</div>
            <div className="mt-1 text-xs" style={{ color: 'var(--text-faint)' }}>{t('hero.stat.platforms')}</div>
          </div>
          <div>
            <div className="font-[family-name:var(--font-display)] text-2xl font-bold">{release?.tag ?? APP_VERSION}</div>
            <div className="mt-1 text-xs" style={{ color: 'var(--text-faint)' }}>AGPL-3.0</div>
          </div>
        </motion.div>
      </div>
    </section>
  );
}

type Shot = { src: string; label: string };

function ShotCard({ shot, index, onOpen }: { shot: Shot; index: number; onOpen: (s: Shot) => void }) {
  return (
    <motion.button
      type="button"
      {...fadeUp}
      transition={{ ...fadeUp.transition, delay: index * 0.08 }}
      onClick={() => onOpen(shot)}
      className="device-frame group block w-full cursor-zoom-in overflow-hidden rounded-2xl text-left"
    >
      {/* Sin caja de proporción forzada: cada imagen mide lo que le
          corresponde según su propio ancho/alto real (w-full h-auto). Entra
          ENTERA, sin recortar y sin relleno vacío alrededor. */}
      <img
        src={shot.src}
        alt={shot.label}
        loading="lazy"
        className="block h-auto w-full transition-transform duration-500 group-hover:scale-[1.03]"
      />
      <div className="flex items-center justify-between px-4 py-3 text-xs font-semibold" style={{ color: 'var(--text-muted)' }}>
        {shot.label}
        <ZoomIn className="h-3.5 w-3.5 opacity-0 transition-opacity group-hover:opacity-60" />
      </div>
    </motion.button>
  );
}

function Showcase() {
  const { t } = useLang();
  const base = import.meta.env.BASE_URL;
  // Panorámica (PC) y verticales (celular) NUNCA quedan parejas en una
  // misma fila con caja fija: una u otra siempre termina con relleno vacío
  // o recortada. Reportado en vivo con foto. Se separan en dos filas —una
  // por forma— así cada captura usa la proporción que le corresponde, y
  // las dos verticales, que SÍ comparten forma, quedan iguales entre sí.
  const desktopShot = { src: `${base}screenshots/desktop-home.png`, label: 'Windows / Linux' };
  const phoneShots = [
    { src: `${base}screenshots/mobile-home.jpeg`, label: 'Android' },
    { src: `${base}screenshots/mobile-search.jpeg`, label: 'Búsqueda' },
  ];
  const [open, setOpen] = useState<{ src: string; label: string } | null>(null);

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setOpen(null);
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open]);

  return (
    <section className="px-5 py-16 md:px-10 md:py-24">
      <div className="mx-auto max-w-6xl">
        <motion.div {...fadeUp} className="mb-12 max-w-xl">
          <Eyebrow>{t('showcase.eyebrow')}</Eyebrow>
          <h2 className="font-[family-name:var(--font-display)] text-2xl font-bold tracking-tight sm:text-3xl">
            {t('showcase.title')}
          </h2>
          <p className="mt-3 text-sm leading-relaxed sm:text-base" style={{ color: 'var(--text-muted)' }}>
            {t('showcase.desc')}
          </p>
        </motion.div>

        {/* Fila 1: la panorámica de escritorio, sola y a lo ancho — a su
            propia proporción no le compite nada al lado. */}
        <ShotCard shot={desktopShot} index={0} onOpen={setOpen} />

        {/* Fila 2: las dos verticales de celular, lado a lado — comparten
            forma, así que a la misma proporción quedan de la misma altura
            entre sí, sin necesidad de forzar una caja. */}
        <div className="mt-5 grid grid-cols-2 gap-5">
          {phoneShots.map((s, i) => (
            <ShotCard key={s.src} shot={s} index={i + 1} onOpen={setOpen} />
          ))}
        </div>
      </div>

      {open && (
        <div
          role="dialog"
          aria-modal="true"
          aria-label={open.label}
          onClick={() => setOpen(null)}
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/85 p-6 backdrop-blur-sm"
        >
          <button
            type="button"
            onClick={() => setOpen(null)}
            aria-label="Cerrar"
            className="absolute right-5 top-5 flex h-10 w-10 items-center justify-center rounded-full bg-white/10 text-white transition-colors hover:bg-white/20"
          >
            <X className="h-5 w-5" />
          </button>
          <img
            src={open.src}
            alt={open.label}
            className="max-h-[90vh] max-w-[92vw] rounded-xl object-contain"
            onClick={(e) => e.stopPropagation()}
          />
        </div>
      )}
    </section>
  );
}

function Features() {
  const { t } = useLang();
  // Seis tarjetas, todas del mismo tamaño: con dos "grandes" (col-span-2) la
  // última fila de un grid de 3 columnas quedaba con una sola tarjeta ancha
  // y un hueco vacío al lado — se veía asimétrico. Parejas, 6 entran justo
  // en dos filas de 3, sin sobrar nada.
  const items = [
    { title: t('features.f1.title'), desc: t('features.f1.desc') },
    { title: t('features.f2.title'), desc: t('features.f2.desc') },
    { title: t('features.f3.title'), desc: t('features.f3.desc') },
    { title: t('features.f4.title'), desc: t('features.f4.desc') },
    { title: t('features.f5.title'), desc: t('features.f5.desc') },
    { title: t('features.f6.title'), desc: t('features.f6.desc') },
  ];

  return (
    <section className="px-5 py-16 md:px-10 md:py-24" style={{ background: 'var(--bg-soft)' }}>
      <div className="mx-auto max-w-6xl">
        <motion.div {...fadeUp} className="mb-12 max-w-xl">
          <Eyebrow>{t('features.eyebrow')}</Eyebrow>
          <h2 className="font-[family-name:var(--font-display)] text-2xl font-bold tracking-tight sm:text-3xl">
            {t('features.title')}
          </h2>
        </motion.div>

        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {items.map((f, i) => (
            <motion.div
              key={f.title}
              {...fadeUp}
              transition={{ ...fadeUp.transition, delay: i * 0.06 }}
              className="surface rounded-2xl p-6"
            >
              <div className="spectrum-bar mb-4 w-8" />
              <h3 className="mb-2 font-[family-name:var(--font-display)] text-base font-semibold">{f.title}</h3>
              <p className="text-sm leading-relaxed" style={{ color: 'var(--text-muted)' }}>{f.desc}</p>
            </motion.div>
          ))}
        </div>
      </div>
    </section>
  );
}

function Requirements() {
  const { t } = useLang();
  return (
    <section className="px-5 py-16 md:px-10 md:py-24">
      <motion.div {...fadeUp} className="mx-auto mb-10 max-w-4xl text-center">
        <Eyebrow>{t('requirements.eyebrow')}</Eyebrow>
      </motion.div>
      <RequirementsTable />
    </section>
  );
}

function DownloadSection() {
  const { t } = useLang();
  const release = useLatestRelease();

  const platforms: { key: DownloadPlatform; label: string; Icon: typeof WindowsIcon; href?: string }[] = [
    { key: 'windows', label: t('platforms.windows'), Icon: WindowsIcon, href: '/windows' },
    { key: 'linux', label: t('platforms.linux'), Icon: LinuxIcon, href: '/linux' },
    { key: 'android', label: t('platforms.android'), Icon: AndroidIcon, href: '/android' },
    { key: 'androidTv', label: t('platforms.androidTv'), Icon: AndroidTvIcon, href: '/android' },
  ];

  return (
    <section id="descargar" className="px-5 py-16 md:px-10 md:py-24" style={{ background: 'var(--bg-soft)' }}>
      <div className="mx-auto max-w-5xl">
        <motion.div {...fadeUp} className="mb-12 text-center">
          <Eyebrow>{t('download.eyebrow')}</Eyebrow>
          <h2 className="font-[family-name:var(--font-display)] text-2xl font-bold tracking-tight sm:text-3xl">
            {t('download.title')}
          </h2>
        </motion.div>

        <motion.div {...fadeUp} className="mb-6 flex items-center gap-3">
          <span
            className="rounded-full px-3 py-1 text-[11px] font-bold uppercase tracking-wide"
            style={{ background: 'color-mix(in srgb, var(--accent) 16%, transparent)', color: 'var(--accent)' }}
          >
            {t('download.betaZone')}
          </span>
          <span className="text-xs" style={{ color: 'var(--text-faint)' }}>{t('download.betaZoneDesc')}</span>
        </motion.div>

        <div className="grid gap-4 sm:grid-cols-2">
          {platforms.map(({ key, label, Icon, href }, i) => {
            const asset = release?.[key];
            const isNew =
              !!release?.publishedAt &&
              PAGE_LOAD_TIME - new Date(release.publishedAt).getTime() <
                DIAS_PARA_DEJAR_DE_SER_NUEVO * 24 * 60 * 60 * 1000;
            return (
              <motion.div
                key={key}
                {...fadeUp}
                transition={{ ...fadeUp.transition, delay: i * 0.06 }}
                className="surface flex flex-col justify-between rounded-2xl p-6"
              >
                <div>
                  <div className="mb-4 flex items-center justify-between">
                    <div
                      className="flex h-11 w-11 items-center justify-center rounded-xl"
                      style={{ background: 'var(--surface-2)', color: 'var(--accent)' }}
                    >
                      <Icon className="h-5 w-5" />
                    </div>
                    {isNew && (
                      <span
                        className="rounded-full px-2.5 py-1 text-[10px] font-bold uppercase tracking-wide"
                        style={{ background: 'color-mix(in srgb, var(--accent) 18%, transparent)', color: 'var(--accent)' }}
                      >
                        {t('platforms.new')}
                      </span>
                    )}
                  </div>
                  <h3 className="font-[family-name:var(--font-display)] text-lg font-semibold">{label}</h3>
                  <div className="mt-1 flex items-center gap-3 font-mono text-xs" style={{ color: 'var(--text-faint)' }}>
                    <span>{release?.tag ?? APP_VERSION}</span>
                    {asset?.size ? <span>· {formatSize(asset.size)}</span> : null}
                  </div>
                </div>
                <div className="mt-6 flex items-center gap-2">
                  {/* A la página de instrucciones, NO directo al archivo:
                      pedido explícito, para que se lea el aviso de
                      seguridad antes de bajar algo. Esa página ya tiene el
                      método real de instalación (comando de consola, o el
                      botón del APK en Android). */}
                  <Link
                    to={href ?? '#descargar'}
                    className="flex flex-1 items-center justify-center gap-2 rounded-xl py-2.5 text-sm font-semibold transition-transform hover:scale-[1.02] active:scale-[0.98]"
                    style={{ background: 'var(--accent)', color: 'var(--accent-ink)' }}
                  >
                    <Download className="h-4 w-4" />
                    {t('platforms.install')}
                  </Link>
                  {href && (
                    // Link, no <a href>: el sitio enruta con HashRouter — un
                    // <a href="/windows"> normal navega el NAVEGADOR a esa
                    // ruta absoluta, que en GitHub Pages no existe (falta el
                    // "#" que HashRouter necesita) y da una pantalla en
                    // blanco. Mismo bug que ya se corrigió en el CTA del
                    // Hero, acá se había colado de nuevo.
                    <Link
                      to={href}
                      className="flex h-10 w-10 items-center justify-center rounded-xl border transition-colors hover:opacity-80"
                      style={{ borderColor: 'var(--border)' }}
                      aria-label={label}
                    >
                      <ArrowUpRight className="h-4 w-4" />
                    </Link>
                  )}
                </div>
              </motion.div>
            );
          })}
        </div>

        <motion.div {...fadeUp} className="mt-12 border-t pt-10" style={{ borderColor: 'var(--border)' }}>
          <div className="mb-4 flex items-center gap-3">
            <span
              className="rounded-full border px-3 py-1 text-[11px] font-bold uppercase tracking-wide"
              style={{ borderColor: 'var(--border-strong)', color: 'var(--text-muted)' }}
            >
              {t('download.stableZone')}
            </span>
            <span className="text-xs" style={{ color: 'var(--text-faint)' }}>{t('download.stableZoneDesc')}</span>
          </div>
          <div
            className="surface-2 flex flex-col items-center gap-1 rounded-2xl border-2 border-dashed px-6 py-10 text-center"
            style={{ borderColor: 'var(--border-strong)' }}
          >
            <p className="text-sm font-medium" style={{ color: 'var(--text-muted)' }}>{t('download.stableEmpty')}</p>
          </div>
        </motion.div>

        <motion.div {...fadeUp} className="mt-8 flex flex-wrap items-center justify-center gap-x-6 gap-y-2 text-center text-sm">
          {release?.htmlUrl && (
            <a
              href={release.htmlUrl}
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center gap-1 font-semibold transition-colors"
              style={{ color: 'var(--accent)' }}
            >
              <Check className="h-4 w-4" />
              {t('download.notes')}
            </a>
          )}
          <a
            href="https://github.com/Litdemonick/Prism_Hub/releases"
            target="_blank"
            rel="noopener noreferrer"
            style={{ color: 'var(--text-faint)' }}
            className="transition-colors hover:opacity-80"
          >
            {t('download.releases')}
          </a>
        </motion.div>

        <div className="mt-10">
          <DeveloperNote />
        </div>
      </div>
    </section>
  );
}

export default function Home() {
  return (
    <Layout>
      <Hero />
      <Showcase />
      <Features />
      <Requirements />
      <DownloadSection />
    </Layout>
  );
}
