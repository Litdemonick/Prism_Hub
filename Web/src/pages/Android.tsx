import { motion } from 'motion/react';
import { Download, Settings2, ShieldCheck, FolderDown } from 'lucide-react';
import Navbar from '../components/Navbar';
import PrismBg from '../components/PrismBg';
import { REPO, useLatestRelease, formatSize } from '../lib/githubRelease';

const DroidIcon = () => (
  <svg fill="currentColor" strokeWidth="0" viewBox="0 0 24 24" className="w-5 h-5 text-violet-400">
    <path d="M17.523 15.341A5.036 5.036 0 0 0 17 13v-2a5 5 0 0 0-10 0v2c0 .857-.122 1.476-.523 2.341C6 16 5 17 5 18c0 .553.448 1 1 1h12c.552 0 1-.447 1-1 0-1-1-2-1.477-2.659zM12 23c1.1 0 2-.9 2-2h-4c0 1.1.9 2 2 2zm-1-19.938C8.162 3.553 6 6.027 6 9v.268A3 3 0 0 1 7 9a3 3 0 0 1 3-3c0-.656-.216-1.268-.582-1.765L9 4l.418-.579A2.994 2.994 0 0 1 12 3c1.15 0 2.16.647 2.678 1.597L15.1 4.5l.322.5A3 3 0 0 1 18 9a3 3 0 0 1 1-.268V9c0-2.973-2.162-5.447-5-5.938z" />
  </svg>
);

const steps = [
  {
    Icon: Settings2,
    title: 'Habilitá "Orígenes desconocidos"',
    desc: 'Ajustes → Seguridad (o Aplicaciones) → permitir instalar desde el navegador/archivos. Android te lo va a pedir solo la primera vez.',
  },
  {
    Icon: FolderDown,
    title: 'Descargá el APK correcto',
    desc: 'arm64-v8a cubre casi todos los celulares desde 2017. Si no arranca, probá armeabi-v7a.',
  },
  {
    Icon: ShieldCheck,
    title: 'Instalá y listo',
    desc: 'Abrí el archivo descargado y confirmá — sin Play Store, sin cuentas, sin anuncios.',
  },
];

export default function Android() {
  const release = useLatestRelease();
  const asset = release?.android;
  const downloadHref = asset?.browser_download_url
    ?? `https://github.com/${REPO}/releases/latest`;

  return (
    <div className="w-full h-screen flex items-center justify-center p-3 md:p-5 bg-[#08080f]">
      <section className="relative w-full max-w-[1536px] h-full rounded-[1.5rem] md:rounded-[3rem] overflow-hidden flex flex-col items-center">
        <PrismBg />
        <div className="relative z-10 w-full h-full flex flex-col items-center">
          <Navbar />
          <div className="flex-1 flex items-center justify-center px-6 w-full overflow-y-auto py-10">
            <motion.div
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.6 }}
              className="w-full max-w-lg"
            >
              <div className="flex items-center gap-2 mb-6 justify-center">
                <DroidIcon />
                <span className="text-white text-lg font-normal">Instalar en Android</span>
              </div>

              <motion.a
                href={downloadHref}
                target="_blank"
                rel="noopener noreferrer"
                whileHover={{ scale: 1.02 }}
                whileTap={{ scale: 0.97 }}
                className="flex items-center justify-center gap-2 w-full py-4 rounded-2xl text-white text-sm bg-[#22c55e]/12 border border-[#22c55e]/35 hover:bg-[#22c55e]/18 transition-all btn-glow"
              >
                <Download className="w-4 h-4 text-[#22c55e]" />
                {asset
                  ? `Descargar APK (arm64-v8a)${asset.size ? ` · ${formatSize(asset.size)}` : ''}`
                  : 'Descargar APK'}
              </motion.a>
              <p className="mt-3 text-[12px] text-white/30 font-normal text-center">
                Android 5.0 o superior · sin Google Play
              </p>

              <div className="mt-8 flex flex-col gap-4">
                {steps.map((s, i) => (
                  <motion.div
                    key={s.title}
                    initial={{ opacity: 0, x: -12 }}
                    animate={{ opacity: 1, x: 0 }}
                    transition={{ duration: 0.4, delay: 0.15 + i * 0.1 }}
                    className="glass-card rounded-2xl p-4 flex items-start gap-3"
                  >
                    <div className="w-8 h-8 rounded-lg bg-violet-500/12 border border-violet-500/25 flex items-center justify-center shrink-0">
                      <s.Icon className="w-4 h-4 text-violet-300" />
                    </div>
                    <div>
                      <div className="text-white/80 text-[13px] mb-0.5">{s.title}</div>
                      <div className="text-white/35 text-[12px] leading-relaxed">{s.desc}</div>
                    </div>
                  </motion.div>
                ))}
              </div>

              <p className="mt-6 text-center">
                <a
                  href={`https://github.com/${REPO}/releases/latest`}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-violet-400 hover:text-violet-300 text-sm transition-colors underline underline-offset-4"
                >
                  Ver todas las arquitecturas en Releases →
                </a>
              </p>
            </motion.div>
          </div>
        </div>
      </section>
    </div>
  );
}
