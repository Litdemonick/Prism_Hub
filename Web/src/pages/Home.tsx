import { motion } from 'motion/react';
import { ArrowUpRight, Download, GitFork, Check } from 'lucide-react';
import Layout from '../components/Layout';
import DeveloperNote from '../components/DeveloperNote';
import { WindowsIcon, LinuxIcon, AndroidIcon, AndroidTvIcon } from '../components/PlatformIcons';
import { useLang } from '../lib/i18n';
import { requirements } from '../lib/requirements';
import {
  APP_VERSION,
  formatSize,
  getDirectDownloadHref,
  useExtensionCount,
  useLatestRelease,
  type DownloadPlatform,
} from '../lib/githubRelease';

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
          <a
            href="#descargar"
            className="flex items-center gap-2 rounded-full px-6 py-3.5 text-sm font-semibold shadow-lg transition-transform hover:scale-[1.03] active:scale-[0.98]"
            style={{ background: 'var(--accent)', color: 'var(--accent-ink)' }}
          >
            <Download className="h-4 w-4" />
            {t('hero.cta.download')}
          </a>
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

function Showcase() {
  const { t } = useLang();
  const base = import.meta.env.BASE_URL;
  const shots = [
    { src: `${base}screenshots/desktop-home.png`, label: 'Windows / Linux' },
    { src: `${base}screenshots/mobile-home.jpeg`, label: 'Android' },
    { src: `${base}screenshots/desktop-search.png`, label: 'Búsqueda' },
  ];

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

        <div className="grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
          {shots.map((s, i) => (
            <motion.div
              key={s.src}
              {...fadeUp}
              transition={{ ...fadeUp.transition, delay: i * 0.08 }}
              className="device-frame group overflow-hidden rounded-2xl"
            >
              <img
                src={s.src}
                alt={s.label}
                loading="lazy"
                className="aspect-[16/10] w-full object-cover object-top transition-transform duration-500 group-hover:scale-[1.04]"
              />
              <div className="px-4 py-3 text-xs font-semibold" style={{ color: 'var(--text-muted)' }}>{s.label}</div>
            </motion.div>
          ))}
        </div>
      </div>
    </section>
  );
}

function Features() {
  const { t } = useLang();
  const items = [
    { title: t('features.f1.title'), desc: t('features.f1.desc'), big: true },
    { title: t('features.f2.title'), desc: t('features.f2.desc') },
    { title: t('features.f3.title'), desc: t('features.f3.desc') },
    { title: t('features.f4.title'), desc: t('features.f4.desc') },
    { title: t('features.f5.title'), desc: t('features.f5.desc') },
    { title: t('features.f6.title'), desc: t('features.f6.desc'), big: true },
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
              className={`surface rounded-2xl p-6 ${f.big ? 'lg:col-span-2' : ''}`}
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
  const { t, lang } = useLang();
  const r = requirements[lang];
  const rows: { label: string; key: keyof typeof r.min }[] = [
    { label: t('requirements.os'), key: 'os' },
    { label: t('requirements.ram'), key: 'ram' },
    { label: t('requirements.cpu'), key: 'cpu' },
    { label: t('requirements.storage'), key: 'storage' },
  ];

  return (
    <section className="px-5 py-16 md:px-10 md:py-24">
      <div className="mx-auto max-w-4xl">
        <motion.div {...fadeUp} className="mb-10 text-center">
          <Eyebrow>{t('requirements.eyebrow')}</Eyebrow>
          <h2 className="font-[family-name:var(--font-display)] text-2xl font-bold tracking-tight sm:text-3xl">
            {t('requirements.title')}
          </h2>
          <p className="mx-auto mt-3 max-w-xl text-sm leading-relaxed" style={{ color: 'var(--text-muted)' }}>
            {t('requirements.desc')}
          </p>
        </motion.div>

        <motion.div {...fadeUp} className="surface overflow-hidden rounded-2xl">
          <div className="grid grid-cols-3 text-sm">
            <div className="p-4" />
            <div className="border-b border-l p-4 text-center font-semibold" style={{ borderColor: 'var(--border)' }}>
              {t('requirements.min')}
            </div>
            <div
              className="border-b border-l p-4 text-center font-semibold"
              style={{ borderColor: 'var(--border)', color: 'var(--accent)' }}
            >
              {t('requirements.rec')}
            </div>
            {rows.map((row) => (
              <>
                <div key={`${row.key}-label`} className="border-t p-4 font-medium" style={{ borderColor: 'var(--border)', color: 'var(--text-muted)' }}>
                  {row.label}
                </div>
                <div key={`${row.key}-min`} className="border-t border-l p-4 text-center" style={{ borderColor: 'var(--border)' }}>
                  {r.min[row.key]}
                </div>
                <div key={`${row.key}-rec`} className="border-t border-l p-4 text-center font-medium" style={{ borderColor: 'var(--border)' }}>
                  {r.rec[row.key]}
                </div>
              </>
            ))}
          </div>
        </motion.div>
        <p className="mx-auto mt-5 max-w-2xl text-center text-xs leading-relaxed" style={{ color: 'var(--text-faint)' }}>
          {t('requirements.note')}
        </p>
      </div>
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
    { key: 'androidTv', label: t('platforms.androidTv'), Icon: AndroidTvIcon },
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
            const downloadHref = getDirectDownloadHref(release, key);
            return (
              <motion.div
                key={key}
                {...fadeUp}
                transition={{ ...fadeUp.transition, delay: i * 0.06 }}
                className="surface flex flex-col justify-between rounded-2xl p-6"
              >
                <div>
                  <div
                    className="mb-4 flex h-11 w-11 items-center justify-center rounded-xl"
                    style={{ background: 'var(--surface-2)', color: 'var(--accent)' }}
                  >
                    <Icon className="h-5 w-5" />
                  </div>
                  <h3 className="font-[family-name:var(--font-display)] text-lg font-semibold">{label}</h3>
                  <div className="mt-1 flex items-center gap-3 font-mono text-xs" style={{ color: 'var(--text-faint)' }}>
                    <span>{release?.tag ?? APP_VERSION}</span>
                    {asset?.size ? <span>· {formatSize(asset.size)}</span> : null}
                  </div>
                </div>
                <div className="mt-6 flex items-center gap-2">
                  <a
                    href={downloadHref}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="flex flex-1 items-center justify-center gap-2 rounded-xl py-2.5 text-sm font-semibold transition-transform hover:scale-[1.02] active:scale-[0.98]"
                    style={{ background: 'var(--accent)', color: 'var(--accent-ink)' }}
                  >
                    <Download className="h-4 w-4" />
                    {t('platforms.install')}
                  </a>
                  {href && (
                    <a
                      href={href}
                      className="flex h-10 w-10 items-center justify-center rounded-xl border transition-colors hover:opacity-80"
                      style={{ borderColor: 'var(--border)' }}
                      aria-label={label}
                    >
                      <ArrowUpRight className="h-4 w-4" />
                    </a>
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
