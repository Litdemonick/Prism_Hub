import { motion } from 'motion/react';
import { Download, Settings2, ShieldCheck, FolderDown, Tv, AlertTriangle, Usb, FileDown } from 'lucide-react';
import Layout from '../components/Layout';
import DeveloperNote from '../components/DeveloperNote';
import { AndroidIcon } from '../components/PlatformIcons';
import { useLang } from '../lib/i18n';
import {
  useLatestRelease,
  formatSize,
  getAndroidDownloadHref,
  getAndroidAsset,
  type AndroidVariant,
} from '../lib/githubRelease';

const allVariants: { label: string; key: AndroidVariant }[] = [
  { label: 'ARM64 (arm64-v8a)', key: 'arm64-v8a' },
  { label: 'ARM32 (armeabi-v7a)', key: 'armeabi-v7a' },
  { label: 'x86_64', key: 'x86_64' },
];

const copy = {
  es: {
    title: 'Instalar en Android',
    beforeTitle: 'Antes de instalar',
    installTitle: 'Instalar',
    mainLabel: 'Universal (todos los aparatos)',
    androidVersion: 'Android 7.0 o superior · sin Google Play',
    otherArch: 'Otras arquitecturas:',
    tvTitle: '¿Vas a instalarlo en un televisor?',
    tvDesc:
      'Es el mismo APK de arriba — la app detecta sola que corre en Android TV y cambia a su propia interfaz para control remoto. Un televisor no tiene el mismo navegador que un celular, así que el APK tiene que llegar por alguna de estas tres formas:',
    tvSteps: [
      { Icon: Usb, title: 'Por USB', desc: 'Descargalo en el celular o la PC, copialo a un pendrive y abrilo desde el gestor de archivos del televisor.' },
      { Icon: FileDown, title: 'Con la app "Downloader"', desc: 'Instalá "Downloader" (de AFTVnews) desde la tienda del televisor, y ahí pegá la URL del APK de la sección de arriba — la descarga e instala directo, sin cables.' },
      { Icon: Tv, title: 'Gestor de archivos con red', desc: 'Si el televisor tiene uno con soporte SMB/FTP, se puede compartir la carpeta de descargas del celular o la PC y abrir el APK desde ahí.' },
    ],
    steps: [
      {
        Icon: Settings2,
        title: 'Habilitá "Orígenes desconocidos"',
        desc: 'Ajustes → Seguridad (o Aplicaciones) → permitir instalar desde el navegador/archivos. Android lo pide solo la primera vez.',
      },
      {
        Icon: FolderDown,
        title: 'Descargá el APK correcto',
        desc: 'arm64-v8a cubre casi todos los celulares desde 2017. Si no arranca, probá armeabi-v7a.',
      },
      {
        Icon: AlertTriangle,
        title: '¿Play Protect dice "esta app puede dañar tu dispositivo"?',
        desc: 'Es el aviso genérico para cualquier app sin firmar de Google — no un análisis real. Tocá "Más detalles" (o los tres puntitos) → "Instalar de todas formas".',
      },
      {
        Icon: ShieldCheck,
        title: 'Instalá y listo',
        desc: 'Abrí el archivo descargado y confirmá — sin Play Store, sin cuentas, sin anuncios.',
      },
    ],
  },
  en: {
    title: 'Install on Android',
    beforeTitle: 'Before installing',
    installTitle: 'Install',
    mainLabel: 'Universal (any device)',
    androidVersion: 'Android 7.0 or later · no Google Play',
    otherArch: 'Other architectures:',
    tvTitle: 'Installing on a TV?',
    tvDesc:
      "It's the same APK from above — the app detects on its own that it's running on Android TV and switches to its own remote-friendly interface. A TV doesn't have the same browser a phone does, so the APK needs to get there one of these three ways:",
    tvSteps: [
      { Icon: Usb, title: 'Over USB', desc: 'Download it on your phone or PC, copy it to a flash drive, and open it from the TV\'s file manager.' },
      { Icon: FileDown, title: 'With the "Downloader" app', desc: 'Install "Downloader" (by AFTVnews) from the TV\'s app store, then paste the APK URL from the section above — it downloads and installs it directly, no cables needed.' },
      { Icon: Tv, title: 'A network file manager', desc: 'If the TV has one with SMB/FTP support, share the downloads folder from your phone or PC and open the APK from there.' },
    ],
    steps: [
      {
        Icon: Settings2,
        title: 'Enable "Unknown sources"',
        desc: 'Settings → Security (or Apps) → allow installing from your browser/files app. Android only asks once.',
      },
      {
        Icon: FolderDown,
        title: 'Download the right APK',
        desc: "arm64-v8a covers almost every phone from 2017 onward. If it won't launch, try armeabi-v7a.",
      },
      {
        Icon: AlertTriangle,
        title: 'Does Play Protect say "this app can harm your device"?',
        desc: "That's Google's generic warning for any unsigned app — not a real scan result. Tap \"More details\" (or the three-dot menu) → \"Install anyway\".",
      },
      {
        Icon: ShieldCheck,
        title: 'Install and done',
        desc: 'Open the downloaded file and confirm — no Play Store, no accounts, no ads.',
      },
    ],
  },
} as const;

export default function Android() {
  const { lang } = useLang();
  const c = copy[lang];
  const release = useLatestRelease();
  // El botón principal siempre ofrece el Universal: un solo archivo que
  // anda en cualquier arquitectura y que la propia app reconoce sola si el
  // aparato es un celular, una tablet o un televisor — no hay nada que la
  // página tenga que adivinar. Las arquitecturas sueltas (más livianas)
  // quedan aparte, para quien ya sabe cuál le corresponde.
  const mainHref = getAndroidDownloadHref(release);
  const mainAsset = getAndroidAsset(release);
  const mainLabel = c.mainLabel;
  const otherVariants = allVariants;

  return (
    <Layout>
      <section className="px-5 py-16 md:px-10 md:py-24">
        <div className="mx-auto max-w-lg lg:max-w-3xl">
          <motion.div
            initial={{ opacity: 0, y: 16 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.5 }}
            className="mx-auto max-w-lg"
          >
            <div className="mb-6 flex items-center justify-center gap-2.5">
              <span style={{ color: 'var(--accent)' }}>
                <AndroidIcon className="h-6 w-6" />
              </span>
              <h1 className="font-[family-name:var(--font-display)] text-2xl font-bold tracking-tight">{c.title}</h1>
            </div>

            {/* Primero el aviso, después cómo instalar — mismo orden que
                Windows y Linux. Se había quedado a medio mover acá. */}
            <p
              className="mb-3 text-center text-xs font-bold uppercase tracking-wide"
              style={{ color: 'var(--accent)' }}
            >
              {c.beforeTitle}
            </p>
            <DeveloperNote />

            <p
              className="mb-3 mt-10 text-center text-xs font-bold uppercase tracking-wide"
              style={{ color: 'var(--accent)' }}
            >
              {c.installTitle}
            </p>

            <a
              href={mainHref}
              target="_blank"
              rel="noopener noreferrer"
              className="flex w-full items-center justify-center gap-2 rounded-2xl py-4 text-sm font-semibold shadow-lg transition-transform hover:scale-[1.02] active:scale-[0.98]"
              style={{ background: 'var(--accent)', color: 'var(--accent-ink)' }}
            >
              <Download className="h-4 w-4 shrink-0" />
              <span>{mainAsset?.size ? `${mainLabel} · ${formatSize(mainAsset.size)}` : mainLabel}</span>
            </a>
            <p className="mt-3 text-center text-xs" style={{ color: 'var(--text-faint)' }}>{c.androidVersion}</p>

            {otherVariants.length > 0 && (
              <div className="mt-5 flex flex-col gap-2">
                <p className="text-center text-[11px]" style={{ color: 'var(--text-faint)' }}>{c.otherArch}</p>
                <div className="flex flex-wrap justify-center gap-2">
                  {otherVariants.map((v) => {
                    const href = getAndroidDownloadHref(release, v.key);
                    const asset = getAndroidAsset(release, v.key);
                    return (
                      <a
                        key={v.key}
                        href={href}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="surface flex items-center gap-1.5 rounded-xl px-4 py-2.5 text-xs transition-opacity hover:opacity-80"
                      >
                        <Download className="h-3 w-3 shrink-0" />
                        {asset?.size ? `${v.label} · ${formatSize(asset.size)}` : v.label}
                      </a>
                    );
                  })}
                </div>
              </div>
            )}
          </motion.div>

          {/* En PC hay lugar de sobra: los pasos van de a dos por fila en
              vez de una sola tira angosta en el medio de la pantalla. */}
          <div className="mt-8 grid gap-3 sm:grid-cols-2">
            {c.steps.map((s, i) => (
              <motion.div
                key={s.title}
                initial={{ opacity: 0, x: -12 }}
                animate={{ opacity: 1, x: 0 }}
                transition={{ duration: 0.4, delay: 0.1 + i * 0.08 }}
                className="surface flex items-start gap-3 rounded-2xl p-4"
              >
                <div
                  className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg"
                  style={{ background: 'var(--surface-2)', color: 'var(--accent)' }}
                >
                  <s.Icon className="h-4 w-4" />
                </div>
                <div>
                  <div className="mb-0.5 text-[13px] font-semibold">{s.title}</div>
                  <div className="text-[12px] leading-relaxed" style={{ color: 'var(--text-faint)' }}>{s.desc}</div>
                </div>
              </motion.div>
            ))}
          </div>

          <div className="surface mt-4 rounded-2xl p-5">
            <div className="mb-4 flex items-start gap-3">
              <div
                className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg"
                style={{ background: 'var(--surface-2)', color: 'var(--accent)' }}
              >
                <Tv className="h-4 w-4" />
              </div>
              <div>
                <div className="mb-1 text-[13px] font-semibold">{c.tvTitle}</div>
                <div className="text-[12px] leading-relaxed" style={{ color: 'var(--text-faint)' }}>{c.tvDesc}</div>
              </div>
            </div>
            <div className="grid gap-3 border-t pt-4 sm:grid-cols-3" style={{ borderColor: 'var(--border)' }}>
              {c.tvSteps.map((s) => (
                <div key={s.title} className="flex items-start gap-3 sm:flex-col sm:gap-2 sm:pl-0 pl-11">
                  <s.Icon className="mt-0.5 h-4 w-4 shrink-0" style={{ color: 'var(--accent)' }} />
                  <div>
                    <div className="mb-0.5 text-[12px] font-semibold">{s.title}</div>
                    <div className="text-[11px] leading-relaxed" style={{ color: 'var(--text-faint)' }}>{s.desc}</div>
                  </div>
                </div>
              ))}
            </div>
          </div>

          <div className="mx-auto mt-4 max-w-lg">
            <DeveloperNote />
          </div>
        </div>
      </section>
    </Layout>
  );
}
