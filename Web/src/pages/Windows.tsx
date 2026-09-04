import { motion } from 'motion/react';
import { ShieldAlert, AlertTriangle } from 'lucide-react';
import Layout from '../components/Layout';
import ConsoleCommand from '../components/ConsoleCommand';
import DeveloperNote from '../components/DeveloperNote';
import { WindowsIcon } from '../components/PlatformIcons';
import { useLang } from '../lib/i18n';

const installCommand =
  'irm https://raw.githubusercontent.com/Litdemonick/Prism_Hub/main/install/install.ps1 | iex';

const copy = {
  es: {
    title: 'Instalar en Windows',
    hint: 'Pegá esto en PowerShell (no hace falta administrador)',
    releasesLink: 'O descargá el instalador .exe desde Releases →',
    menuTitle: 'Un solo comando, tres cosas',
    menuDesc:
      'El script abre un menú: la misma línea sirve para instalar la primera vez, actualizar a la última versión o desinstalar — no hay tres comandos distintos que recordar.',
    menu: ['Instalar', 'Actualizar', 'Desinstalar', 'Salir'],
    troubleTitle: '¿Windows bloquea el instalador?',
    troubleIntro:
      'El .exe todavía no tiene firma digital (certificado de code-signing), así que Windows puede marcarlo como desconocido. Depende de qué te aparece:',
    trouble1title: '"Windows protegió su PC" (SmartScreen)',
    trouble1:
      'Tocá Más información → Ejecutar de todas formas. No hace falta cambiar nada más.',
    trouble2title: '"Una directiva de Control de aplicaciones bloqueó este archivo" (error 4551 / Smart App Control)',
    trouble2:
      'Este bloqueo no tiene botón de "ejecutar igual" — hay que apagar la función entera: Configuración → Privacidad y seguridad → Seguridad de Windows → Control de aplicaciones y del navegador → Control inteligente de aplicaciones → Desactivado. Si ahí ya dice "Activado" (no "Evaluación"), Windows no deja volver atrás sin reinstalar el sistema.',
    vcTitle: '¿"No se encontró MSVCP140.dll" o "VCRUNTIME140.dll" al abrir la app?',
    vcBody:
      'Pasa sobre todo en un Windows recién formateado o instalado desde cero: le falta el Visual C++ Redistributable, una pieza de Microsoft que PrismHub (y cualquier app hecha con Flutter) necesita para arrancar — no es un archivo dañado ni un problema de PrismHub.',
    vcAuto: 'Instalando por consola (arriba) esto se resuelve solo: el script lo detecta y lo instala antes de terminar, sin pedir reiniciar.',
    vcManual: 'Si instalaste con el .exe de Releases y te aparece el error, descargalo directo de Microsoft e instalalo:',
    vcLink: 'Visual C++ Redistributable (oficial, aka.ms/Microsoft) →',
  },
  en: {
    title: 'Install on Windows',
    hint: 'Paste this into PowerShell (administrator not required)',
    releasesLink: 'Or download the .exe installer from Releases →',
    menuTitle: 'One command, three things',
    menuDesc:
      'The script opens a menu: the same line installs it the first time, updates to the latest version, or uninstalls — no three separate commands to remember.',
    menu: ['Install', 'Update', 'Uninstall', 'Exit'],
    troubleTitle: 'Does Windows block the installer?',
    troubleIntro:
      "The .exe doesn't have a digital signature (code-signing certificate) yet, so Windows may flag it as unknown. It depends on what you see:",
    trouble1title: '"Windows protected your PC" (SmartScreen)',
    trouble1: 'Tap More info → Run anyway. Nothing else to change.',
    trouble2title: '"An app control policy blocked this file" (error 4551 / Smart App Control)',
    trouble2:
      'This block has no "run anyway" button — the whole feature has to be turned off: Settings → Privacy & security → Windows Security → App & browser control → Smart App Control → Off. If it already says "On" (not "Evaluation"), Windows won\'t let you go back without reinstalling the OS.',
    vcTitle: '"MSVCP140.dll" or "VCRUNTIME140.dll not found" when opening the app?',
    vcBody:
      "This mostly happens on a freshly formatted or clean-installed Windows: it's missing the Visual C++ Redistributable, a Microsoft component PrismHub (and any Flutter-built app) needs to start — it's not a corrupted file or a PrismHub problem.",
    vcAuto: "Installing via the console command (above) fixes this on its own: the script detects it and installs it before finishing, no restart needed.",
    vcManual: "If you installed with the .exe from Releases and hit this error, download it straight from Microsoft and install it:",
    vcLink: 'Visual C++ Redistributable (official, aka.ms/Microsoft) →',
  },
} as const;

export default function Windows() {
  const { lang } = useLang();
  const c = copy[lang];

  return (
    <Layout>
      <section className="px-5 py-16 md:px-10 md:py-24">
        <div className="mx-auto max-w-xl">
          <motion.div initial={{ opacity: 0, y: 16 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.5 }}>
            <div className="mb-6 flex items-center justify-center gap-2.5">
              <span style={{ color: 'var(--accent)' }}>
                <WindowsIcon className="h-6 w-6" />
              </span>
              <h1 className="font-[family-name:var(--font-display)] text-2xl font-bold tracking-tight">{c.title}</h1>
            </div>

            <ConsoleCommand command={installCommand} hint={c.hint} />

            <p className="mt-4 text-center text-sm">
              <a
                href="https://github.com/Litdemonick/Prism_Hub/releases/latest"
                target="_blank"
                rel="noopener noreferrer"
                className="underline decoration-dotted underline-offset-4"
                style={{ color: 'var(--accent)' }}
              >
                {c.releasesLink}
              </a>
            </p>

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
              <div className="mb-3 flex items-center gap-2">
                <ShieldAlert className="h-4 w-4" style={{ color: 'var(--accent)' }} />
                <h2 className="font-[family-name:var(--font-display)] text-sm font-semibold">{c.troubleTitle}</h2>
              </div>
              <p className="text-xs leading-relaxed" style={{ color: 'var(--text-muted)' }}>{c.troubleIntro}</p>
              <div className="mt-3 border-t pt-3 text-xs leading-relaxed" style={{ borderColor: 'var(--border)' }}>
                <span className="font-semibold" style={{ color: 'var(--text)' }}>{c.trouble1title}</span>{' '}
                <span style={{ color: 'var(--text-muted)' }}>{c.trouble1}</span>
              </div>
              <div className="mt-3 border-t pt-3 text-xs leading-relaxed" style={{ borderColor: 'var(--border)' }}>
                <span className="font-semibold" style={{ color: 'var(--text)' }}>{c.trouble2title}</span>{' '}
                <span style={{ color: 'var(--text-muted)' }}>{c.trouble2}</span>
              </div>
            </div>

            <div className="surface mt-4 rounded-2xl px-6 py-5">
              <div className="mb-3 flex items-center gap-2">
                <AlertTriangle className="h-4 w-4" style={{ color: 'var(--accent)' }} />
                <h2 className="font-[family-name:var(--font-display)] text-sm font-semibold">{c.vcTitle}</h2>
              </div>
              <p className="mb-3 text-xs leading-relaxed" style={{ color: 'var(--text-muted)' }}>{c.vcBody}</p>
              <p className="mb-3 text-xs leading-relaxed" style={{ color: 'var(--text-muted)' }}>{c.vcAuto}</p>
              <p className="text-xs leading-relaxed" style={{ color: 'var(--text-muted)' }}>{c.vcManual}</p>
              <a
                href="https://aka.ms/vs/17/release/vc_redist.x64.exe"
                className="mt-2 inline-block text-xs font-semibold underline"
                style={{ color: 'var(--accent)' }}
              >
                {c.vcLink}
              </a>
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
