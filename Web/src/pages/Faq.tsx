import { useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { ChevronDown } from 'lucide-react';
import Layout from '../components/Layout';
import { useLang } from '../lib/i18n';

const copy = {
  es: {
    title: 'Preguntas frecuentes',
    faqs: [
      {
        q: '¿Qué es PrismHub?',
        a: 'Una aplicación multiplataforma (Windows, Linux, Android) para ver anime, leer manga y acceder a series y películas. Funciona mediante extensiones JavaScript que podés instalar y crear vos mismo.',
      },
      {
        q: '¿Es compatible con Windows, Linux y Android?',
        a: 'Sí. Windows y Linux tienen instaladores automáticos desde consola. Android tiene un APK descargable desde Releases — el mismo archivo sirve para teléfono, tablet y Android TV.',
      },
      {
        q: '¿Cómo instalo extensiones?',
        a: 'El repositorio oficial (prism+) ya viene configurado por defecto. Para agregar otro: Ajustes → Extensiones → URL del repositorio, pegá la URL de un index.json compatible y tocá Recargar.\n\nhttps://raw.githubusercontent.com/Litdemonick/prism-plus/main/index.json',
      },
      {
        q: '¿Qué contenido puedo ver?',
        a: 'Anime, películas, series y manga desde múltiples fuentes, todo desde una sola app. Las extensiones de prism+ están enfocadas en contenido en español.',
      },
      {
        q: '¿Puedo crear mis propias extensiones?',
        a: 'Sí. Son archivos JavaScript con un encabezado ==PrismHubExtension== y una clase que implementa latest(), search(), detail() y watch(). Ver la sección Extensiones para el detalle.',
      },
      {
        q: '¿Es código abierto?',
        a: 'Sí, bajo licencia AGPL-3.0. Se puede usar, modificar y distribuir manteniendo el código fuente accesible.',
      },
      {
        q: '¿Por qué el reproductor cambia de servidor solo?',
        a: 'Las extensiones de prism+ devuelven un encabezado X-Servers con servidores alternativos. Si el principal falla, el reproductor prueba el siguiente sin que hagas nada.',
      },
      {
        q: 'Windows bloqueó o borró el instalador, ¿está infectado?',
        a: 'No. El .exe todavía no tiene firma digital, así que un antivirus puede marcarlo como "desconocido" al primer intento — es un falso positivo común en software nuevo sin firmar, no un virus. Revisá Seguridad de Windows → Protección contra virus y amenazas → Historial de protección, y restauralo desde ahí.',
      },
      {
        q: '¿PrismHub cobra algo o guarda mis datos?',
        a: 'No. No hay cuentas, ni pagos, ni servidores propios registrando qué mirás — el historial y los favoritos viven en el aparato donde los usás.',
      },
    ],
  },
  en: {
    title: 'Frequently asked questions',
    faqs: [
      {
        q: 'What is PrismHub?',
        a: 'A cross-platform app (Windows, Linux, Android) for watching anime, reading manga, and accessing series and movies. It works through JavaScript extensions you can install and write yourself.',
      },
      {
        q: 'Does it support Windows, Linux and Android?',
        a: 'Yes. Windows and Linux have automatic console installers. Android has a downloadable APK from Releases — the same file works on phone, tablet and Android TV.',
      },
      {
        q: 'How do I install extensions?',
        a: "The official repository (prism+) is already configured by default. To add another: Settings → Extensions → repository URL, paste a compatible index.json URL and tap Reload.\n\nhttps://raw.githubusercontent.com/Litdemonick/prism-plus/main/index.json",
      },
      {
        q: 'What content can I watch?',
        a: 'Anime, movies, series and manga from multiple sources, all from a single app. The prism+ extensions are focused on Spanish-language content.',
      },
      {
        q: 'Can I write my own extensions?',
        a: 'Yes. They are JavaScript files with an ==PrismHubExtension== header and a class implementing latest(), search(), detail() and watch(). See the Extensions section for details.',
      },
      {
        q: 'Is it open source?',
        a: 'Yes, under the AGPL-3.0 license. You can use, modify and distribute it as long as the source stays accessible.',
      },
      {
        q: 'Why does the player switch servers on its own?',
        a: 'prism+ extensions return an X-Servers header with alternate servers. If the main one fails, the player tries the next one with nothing for you to do.',
      },
      {
        q: 'Windows blocked or deleted the installer — is it infected?',
        a: "No. The .exe doesn't have a digital signature yet, so an antivirus may flag it as \"unknown\" on first try — a common false positive for new unsigned software, not a virus. Check Windows Security → Virus & threat protection → Protection history, and restore it from there.",
      },
      {
        q: 'Does PrismHub charge anything or store my data?',
        a: "No. There are no accounts, no payments, and no servers of ours logging what you watch — history and favorites live on the device you use them on.",
      },
    ],
  },
} as const;

function FaqItem({ question, answer }: { question: string; answer: string }) {
  const [open, setOpen] = useState(false);
  return (
    <motion.div layout className="surface overflow-hidden rounded-2xl">
      <button
        onClick={() => setOpen(!open)}
        className="flex w-full items-center justify-between px-6 py-4 text-left text-sm font-medium md:text-base"
      >
        <span>{question}</span>
        <ChevronDown
          className={`ml-4 h-4 w-4 flex-shrink-0 transition-transform duration-300 ${open ? 'rotate-180' : ''}`}
          style={{ color: 'var(--accent)' }}
        />
      </button>
      <AnimatePresence initial={false}>
        {open && (
          <motion.div
            key="answer"
            initial={{ height: 0, opacity: 0 }}
            animate={{ height: 'auto', opacity: 1 }}
            exit={{ height: 0, opacity: 0 }}
            transition={{ duration: 0.3, ease: 'easeInOut' }}
            className="overflow-hidden"
          >
            <div
              className="whitespace-pre-line border-t px-6 pb-5 pt-3 text-xs leading-relaxed md:text-sm"
              style={{ borderColor: 'var(--border)', color: 'var(--text-muted)' }}
            >
              {answer}
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </motion.div>
  );
}

export default function Faq() {
  const { lang } = useLang();
  const c = copy[lang];

  return (
    <Layout>
      <section className="px-5 py-16 md:px-10 md:py-24">
        <div className="mx-auto max-w-2xl">
          <motion.h1
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.5 }}
            className="mb-10 text-center font-[family-name:var(--font-display)] text-3xl font-bold tracking-tight md:text-4xl"
          >
            {c.title}
          </motion.h1>
          <div className="flex flex-col gap-3">
            {c.faqs.map((faq, i) => (
              <motion.div
                key={faq.q}
                initial={{ opacity: 0, y: 14 }}
                whileInView={{ opacity: 1, y: 0 }}
                viewport={{ once: true, margin: '-40px' }}
                transition={{ duration: 0.4, delay: Math.min(i * 0.05, 0.3) }}
              >
                <FaqItem question={faq.q} answer={faq.a} />
              </motion.div>
            ))}
          </div>
        </div>
      </section>
    </Layout>
  );
}
