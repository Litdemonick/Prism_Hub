import { Link } from 'react-router-dom';
import { ArrowUpRight } from 'lucide-react';
import { useLang } from '../lib/i18n';

export default function Footer() {
  const { t } = useLang();

  const columns = [
    {
      title: t('footer.product'),
      links: [
        { label: t('nav.home'), to: '/' },
        { label: t('nav.docs'), to: '/docs' },
        { label: t('nav.faq'), to: '/faq' },
        { label: t('nav.developers'), to: '/developers' },
      ],
    },
    {
      title: t('footer.install'),
      links: [
        { label: t('platforms.windows'), to: '/windows' },
        { label: t('platforms.linux'), to: '/linux' },
        { label: t('platforms.android'), to: '/android' },
        { label: t('footer.allReleases'), to: 'https://github.com/Litdemonick/Prism_Hub/releases', external: true },
      ],
    },
    {
      title: t('footer.project'),
      links: [
        { label: t('footer.source'), to: 'https://github.com/Litdemonick/Prism_Hub', external: true },
        { label: t('footer.extensionsRepo'), to: 'https://github.com/Litdemonick/prism-plus', external: true },
        { label: t('nav.license'), to: '/license' },
        { label: t('footer.reportBug'), to: 'https://github.com/Litdemonick/Prism_Hub/issues', external: true },
      ],
    },
  ];

  return (
    <footer className="relative border-t px-5 pb-8 pt-14 md:px-10" style={{ borderColor: 'var(--border)' }}>
      <div className="mx-auto max-w-6xl">
        <div className="mb-12 grid grid-cols-2 gap-10 md:grid-cols-4">
          <div className="col-span-2 md:col-span-1">
            <div className="mb-3 flex items-center gap-2.5">
              <img src={`${import.meta.env.BASE_URL}brand/logo.png`} alt="PrismHub" className="h-8 w-8 rounded-lg" />
              <span className="font-[family-name:var(--font-display)] text-base font-semibold tracking-tight">PrismHub</span>
            </div>
            <p className="max-w-[220px] text-xs leading-relaxed" style={{ color: 'var(--text-faint)' }}>
              {t('footer.tagline')}
            </p>
          </div>
          {columns.map((col) => (
            <div key={col.title}>
              <div className="mb-4 text-xs font-semibold uppercase tracking-widest" style={{ color: 'var(--text-muted)' }}>
                {col.title}
              </div>
              <ul className="flex flex-col gap-2.5">
                {col.links.map((l) => (
                  <li key={l.label}>
                    {'external' in l && l.external ? (
                      <a
                        href={l.to}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="group flex items-center gap-1 text-[13px] transition-colors hover:text-[var(--text)]"
                        style={{ color: 'var(--text-faint)' }}
                      >
                        {l.label}
                        <ArrowUpRight className="h-3 w-3 opacity-0 transition-opacity group-hover:opacity-70" />
                      </a>
                    ) : (
                      <Link to={l.to} className="text-[13px] transition-colors hover:text-[var(--text)]" style={{ color: 'var(--text-faint)' }}>
                        {l.label}
                      </Link>
                    )}
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </div>

        <div className="spectrum-bar mb-8 opacity-30" />

        <div className="flex flex-col items-center justify-between gap-4 text-xs sm:flex-row" style={{ color: 'var(--text-faint)' }}>
          <span>&copy; 2026 Soul_Of_The_sun · AGPL-3.0</span>
          <a
            href="https://github.com/Litdemonick"
            target="_blank"
            rel="noopener noreferrer"
            className="underline decoration-dotted underline-offset-4 transition-colors hover:text-[var(--text)]"
          >
            github.com/Litdemonick
          </a>
        </div>
      </div>
    </footer>
  );
}
