import { useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { ChevronDown } from 'lucide-react';
import Navbar from '../components/Navbar';
import PrismBg from '../components/PrismBg';

const faqs = [
  {
    q: '¿Qué es PrismHub?',
    a: 'PrismHub es una aplicación multiplataforma (Windows, Android, Linux) para ver anime, leer manga y acceder a series y películas. Funciona mediante extensiones JavaScript que puedes instalar y crear tú mismo.',
  },
  {
    q: '¿PrismHub es compatible con Windows, Linux y Android?',
    a: 'Sí. PrismHub tiene soporte para Windows, Linux y Android. Windows y Linux cuentan con instaladores automáticos desde terminal. Android tiene APK descargable desde Releases.',
  },
  {
    q: '¿Cómo instalo extensiones?',
    a: 'Ve a Ajustes → Extensiones → URL del repositorio y pega una de estas URLs:\n\nRepositorio oficial (prism+):\nhttps://raw.githubusercontent.com/Litdemonick/prism-plus/main/index.json\n\nRepositorio comunidad (150+ extensiones):\nhttps://raw.githubusercontent.com/Litdemonick/Prism_Hub/main/index.json\n\nLuego pulsa Recargar para ver las extensiones disponibles.',
  },
  {
    q: '¿Qué contenido puedo ver?',
    a: 'Puedes ver anime, películas, series y leer manga desde múltiples fuentes, todo desde una sola aplicación usando extensiones. Las extensiones de prism+ están enfocadas en contenido en español.',
  },
  {
    q: '¿Puedo crear mis propias extensiones?',
    a: 'Sí. Las extensiones son archivos JavaScript con un header ==PrismHubExtension== y una clase que implementa latest(), search(), detail() y watch(). Consulta la sección de Extensiones para más detalles.',
  },
  {
    q: '¿PrismHub es código abierto?',
    a: 'Sí. PrismHub es open source bajo licencia AGPL-3.0. Puedes usar, modificar y distribuir la aplicación siempre que mantengas el código fuente accesible.',
  },
  {
    q: '¿Por qué el reproductor cambia de servidor automáticamente?',
    a: 'Las extensiones de prism+ retornan un header X-Servers con servidores alternativos. Si el servidor principal falla, el reproductor lee ese header y prueba el siguiente sin que tengas que hacer nada.',
  },
];

function FaqItem({ question, answer }: { question: string; answer: string }) {
  const [open, setOpen] = useState(false);
  return (
    <motion.div layout className="rounded-2xl glass-card overflow-hidden">
      <button
        onClick={() => setOpen(!open)}
        className="w-full flex items-center justify-between px-6 py-4 text-left text-white text-sm md:text-base font-normal"
      >
        <span>{question}</span>
        <ChevronDown className={`w-4 h-4 text-violet-400 transition-transform duration-300 flex-shrink-0 ml-4 ${open ? 'rotate-180' : ''}`} />
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
            <div className="px-6 pb-5 text-white/50 text-xs md:text-sm font-normal leading-relaxed whitespace-pre-line border-t border-white/5 pt-3">
              {answer}
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </motion.div>
  );
}

export default function Faq() {
  return (
    <div className="w-full min-h-screen flex items-center justify-center p-3 md:p-5 bg-[#08080f]">
      <section className="relative w-full max-w-[1536px] min-h-[calc(100vh-1.5rem)] rounded-[1.5rem] md:rounded-[3rem] overflow-hidden flex flex-col items-center">
        <PrismBg />
        <div className="relative z-10 w-full h-full flex flex-col items-center">
          <Navbar />
          <div className="flex-1 w-full max-w-2xl px-6 pb-12">
            <motion.h1
              initial={{ opacity: 0, y: 10 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.5 }}
              className="text-3xl md:text-4xl font-normal text-white text-center mb-8 tracking-tight"
            >
              FAQ — <span className="prism-text">PrismHub</span>
            </motion.h1>
            <div className="flex flex-col gap-3">
              {faqs.map((faq, i) => (
                <motion.div
                  key={i}
                  initial={{ opacity: 0, y: 16 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={{ duration: 0.4, delay: i * 0.07 }}
                >
                  <FaqItem question={faq.q} answer={faq.a} />
                </motion.div>
              ))}
            </div>
          </div>
        </div>
      </section>
    </div>
  );
}
