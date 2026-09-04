import { motion } from 'motion/react';
import Layout from '../components/Layout';
import ConsoleCommand from '../components/ConsoleCommand';
import DeveloperNote from '../components/DeveloperNote';
import { LinuxIcon } from '../components/PlatformIcons';
import { useLang } from '../lib/i18n';

const installCommand =
  'curl -fsSL https://raw.githubusercontent.com/Litdemonick/Prism_Hub/main/install/install.sh | bash';
const archCommand = 'cd install && makepkg -si';

const copy = {
  es: {
    title: 'Instalar en Linux',
    hint: 'Pegá esto en tu terminal',
    menuTitle: 'Un solo comando, tres cosas',
    menuDesc:
      'El script abre un menú: la misma línea sirve para instalar la primera vez, actualizar a la última versión o desinstalar — no hay tres comandos distintos que recordar.',
    menu: ['Instalar', 'Actualizar', 'Desinstalar', 'Salir'],
    archTitle: 'Arch Linux (PKGBUILD)',
    archDesc: 'Si preferís pacman en vez del script genérico, el repositorio trae un PKGBUILD listo:',
  },
  en: {
    title: 'Install on Linux',
    hint: 'Paste this into your terminal',
    menuTitle: 'One command, three things',
    menuDesc:
      'The script opens a menu: the same line installs it the first time, updates to the latest version, or uninstalls — no three separate commands to remember.',
    menu: ['Install', 'Update', 'Uninstall', 'Exit'],
    archTitle: 'Arch Linux (PKGBUILD)',
    archDesc: 'If you prefer pacman over the generic script, the repository ships a ready PKGBUILD:',
  },
} as const;

export default function Linux() {
  const { lang } = useLang();
  const c = copy[lang];

  return (
    <Layout>
      <section className="px-5 py-16 md:px-10 md:py-24">
        <div className="mx-auto max-w-xl">
          <motion.div initial={{ opacity: 0, y: 16 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.5 }}>
            <div className="mb-6 flex items-center justify-center gap-2.5">
              <span style={{ color: 'var(--accent)' }}>
                <LinuxIcon className="h-6 w-6" />
              </span>
              <h1 className="font-[family-name:var(--font-display)] text-2xl font-bold tracking-tight">{c.title}</h1>
            </div>

            <ConsoleCommand command={installCommand} hint={c.hint} />

            <div className="surface mt-8 rounded-2xl px-6 py-5">
              <h2 className="mb-2 font-[family-name:var(--font-display)] text-sm font-semibold">{c.menuTitle}</h2>
              <p className="mb-4 text-xs leading-relaxed" style={{ color: 'var(--text-muted)' }}>{c.menuDesc}</p>
              <ol className="flex flex-col gap-2 text-xs">
                {c.menu.map((label, i) => (
                  <li key={label} className="flex items-center gap-3">
                    <span
                      className="flex h-5 w-5 shrink-0 items-center justify-center rounded-full font-mono text-[10px] font-bold"
                      style={{ background: 'var(--surface-2)', color: 'var(--accent)' }}
                    >
                      {i + 1}
                    </span>
                    <span style={{ color: 'var(--text-muted)' }}>{label}</span>
                  </li>
                ))}
              </ol>
            </div>

            <div className="surface mt-4 rounded-2xl px-6 py-5">
              <h2 className="mb-2 font-[family-name:var(--font-display)] text-sm font-semibold">{c.archTitle}</h2>
              <p className="mb-3 text-xs leading-relaxed" style={{ color: 'var(--text-muted)' }}>{c.archDesc}</p>
              <ConsoleCommand command={archCommand} />
            </div>

            <div className="mt-4">
              <DeveloperNote />
            </div>
          </motion.div>
        </div>
      </section>
    </Layout>
  );
}
