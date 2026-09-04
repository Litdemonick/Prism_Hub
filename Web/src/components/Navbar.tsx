import { useState } from 'react';
import { Link, useLocation } from 'react-router-dom';
import { ArrowUpRight, Moon, Sun, Menu, X, Languages, Star } from 'lucide-react';
import { useTheme } from '../lib/theme';
import { useLang, type DictKey } from '../lib/i18n';
import { useGithubStars } from '../lib/githubRelease';

const items: { key: DictKey; to: string }[] = [
  { key: 'nav.home', to: '/' },
  { key: 'nav.docs', to: '/docs' },
  { key: 'nav.faq', to: '/faq' },
  { key: 'nav.developers', to: '/developers' },
  { key: 'nav.license', to: '/license' },
];

export default function Navbar() {
  const { theme, toggle } = useTheme();
  const { lang, setLang, t } = useLang();
  const stars = useGithubStars();
  const { pathname } = useLocation();
  const [open, setOpen] = useState(false);

  return (
    <nav className="relative z-20 flex items-center justify-between gap-4 px-5 py-5 md:px-10 md:py-6">
      <Link to="/" className="flex items-center gap-2.5 shrink-0" onClick={() => setOpen(false)}>
        <img src={`${import.meta.env.BASE_URL}brand/logo.png`} alt="PrismHub" className="h-8 w-8 rounded-lg" />
        <span className="font-[family-name:var(--font-display)] text-lg font-semibold tracking-tight">
          PrismHub
        </span>
      </Link>

      <ul className="hidden items-center gap-7 md:flex">
        {items.map((item) => {
          const active = pathname === item.to;
          return (
            <li key={item.to}>
              <Link
                to={item.to}
                className="relative py-1 text-sm font-medium transition-colors"
                style={{ color: active ? 'var(--text)' : 'var(--text-muted)' }}
              >
                {t(item.key)}
                {active && (
                  <span className="absolute -bottom-1 left-0 right-0 h-[2px] rounded-full spectrum-bar" />
                )}
              </Link>
            </li>
          );
        })}
      </ul>

      <div className="hidden items-center gap-2 md:flex">
        <button
          type="button"
          onClick={() => setLang(lang === 'es' ? 'en' : 'es')}
          aria-label={t('nav.lang')}
          title={t('nav.lang')}
          className="flex h-9 items-center gap-1.5 rounded-full border px-3 text-xs font-semibold uppercase tracking-wide transition-colors hover:opacity-80"
          style={{ borderColor: 'var(--border)', color: 'var(--text-muted)' }}
        >
          <Languages className="h-3.5 w-3.5" />
          {lang}
        </button>
        <button
          type="button"
          onClick={toggle}
          aria-label={t('nav.theme')}
          title={t('nav.theme')}
          className="flex h-9 w-9 items-center justify-center rounded-full border transition-colors hover:opacity-80"
          style={{ borderColor: 'var(--border)', color: 'var(--text-muted)' }}
        >
          {theme === 'dark' ? <Sun className="h-4 w-4" /> : <Moon className="h-4 w-4" />}
        </button>
        <a
          href="https://github.com/Litdemonick/Prism_Hub"
          target="_blank"
          rel="noopener noreferrer"
          className="flex items-center gap-2 rounded-full border py-1.5 pl-3 pr-2 text-xs font-semibold transition-transform hover:scale-[1.03] active:scale-[0.98]"
          style={{ borderColor: 'var(--border)', color: 'var(--text)' }}
        >
          {t('nav.github')}
          {stars != null && (
            <span className="flex items-center gap-1" style={{ color: 'var(--accent)' }}>
              <Star className="h-3 w-3 fill-current" />
              {stars}
            </span>
          )}
          <span className="flex h-5 w-5 items-center justify-center rounded-full" style={{ background: 'var(--surface-2)' }}>
            <ArrowUpRight className="h-3 w-3" />
          </span>
        </a>
      </div>

      <button
        type="button"
        className="flex h-9 w-9 items-center justify-center rounded-full border md:hidden"
        style={{ borderColor: 'var(--border)' }}
        onClick={() => setOpen((v) => !v)}
        aria-label="Menu"
        aria-expanded={open}
      >
        {open ? <X className="h-4 w-4" /> : <Menu className="h-4 w-4" />}
      </button>

      {open && (
        <div
          className="surface absolute left-4 right-4 top-[calc(100%-0.5rem)] z-30 flex flex-col gap-1 rounded-2xl p-3 shadow-xl md:hidden"
        >
          {items.map((item) => (
            <Link
              key={item.to}
              to={item.to}
              onClick={() => setOpen(false)}
              className="rounded-xl px-4 py-3 text-sm font-medium"
              style={{ color: pathname === item.to ? 'var(--text)' : 'var(--text-muted)', background: pathname === item.to ? 'var(--surface-2)' : 'transparent' }}
            >
              {t(item.key)}
            </Link>
          ))}
          <div className="mt-1 flex items-center gap-2 border-t px-1 pt-3" style={{ borderColor: 'var(--border)' }}>
            <button
              type="button"
              onClick={() => setLang(lang === 'es' ? 'en' : 'es')}
              className="flex h-9 flex-1 items-center justify-center gap-1.5 rounded-full border text-xs font-semibold uppercase"
              style={{ borderColor: 'var(--border)' }}
            >
              <Languages className="h-3.5 w-3.5" /> {lang}
            </button>
            <button
              type="button"
              onClick={toggle}
              className="flex h-9 flex-1 items-center justify-center gap-1.5 rounded-full border text-xs font-semibold"
              style={{ borderColor: 'var(--border)' }}
            >
              {theme === 'dark' ? <Sun className="h-4 w-4" /> : <Moon className="h-4 w-4" />}
            </button>
            <a
              href="https://github.com/Litdemonick/Prism_Hub"
              target="_blank"
              rel="noopener noreferrer"
              className="flex h-9 flex-1 items-center justify-center gap-1.5 rounded-full border text-xs font-semibold"
              style={{ borderColor: 'var(--border)' }}
            >
              GitHub <ArrowUpRight className="h-3 w-3" />
            </a>
          </div>
        </div>
      )}
    </nav>
  );
}
