import { motion } from 'motion/react';
import { ChevronDown } from 'lucide-react';
import Navbar from './Navbar';
import HeroBadge from './HeroBadge';
import BottomLeftCard from './BottomLeftCard';
import BottomRightCorner from './BottomRightCorner';
import DownloadButtons from './DownloadButtons';
import PrismBg from './PrismBg';

export default function Hero() {
  return (
    <div className="w-full h-screen flex items-center justify-center p-3 md:p-5 bg-[#08080f]">
      <section className="relative w-full max-w-[1536px] h-full rounded-[1.5rem] md:rounded-[3rem] overflow-hidden flex flex-col items-center">
        <PrismBg />
        <div className="relative z-10 w-full h-full flex flex-col items-center">
          <Navbar />
          <div className="relative z-10 w-full flex flex-col items-center pt-8 landscape:pt-2 px-6 text-center max-w-4xl">
            <HeroBadge />
            <motion.h1
              initial={{ opacity: 0, scale: 0.97 }}
              animate={{ opacity: 1, scale: 1 }}
              transition={{ duration: 0.8, delay: 0.2 }}
              className="text-5xl sm:text-6xl md:text-7xl lg:text-[88px] landscape:text-3xl font-normal text-white mb-3 landscape:mb-1 tracking-tight leading-[1.05]"
            >
              Prism<span className="prism-text">Hub</span>
            </motion.h1>
            <motion.p
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              transition={{ duration: 0.8, delay: 0.4 }}
              className="text-sm sm:text-base md:text-lg text-white/50 leading-relaxed max-w-xl font-normal"
            >
              Anime, manga, novelas, series y películas — sin límites. Sistema de extensiones
              JavaScript para cualquier fuente de contenido.
            </motion.p>
            <DownloadButtons />
            <motion.a
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              transition={{ duration: 0.6, delay: 1 }}
              href="https://github.com/Litdemonick/prism-plus"
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center gap-1.5 text-[11px] text-emerald-400/50 hover:text-emerald-400/80 transition-colors mt-4 landscape:mt-2"
            >
              <svg viewBox="0 0 512 512" className="w-3 h-3" fill="currentColor">
                <path d="M256 48C141.1 48 48 141.1 48 256s93.1 208 208 208 208-93.1 208-208S370.9 48 256 48zm128 256h-80v80h-96v-80h-80v-96h80v-80h96v80h80v96z"/>
              </svg>
              <span>Repositorio de extensiones prism+</span>
            </motion.a>
          </div>
          <BottomLeftCard />
          <BottomRightCorner />

          {/* Indicador de scroll — el hero ocupa el 100vh completo, sin esto
              parecía que la página terminaba ahí y no había nada más abajo
              (confirmado en vivo). */}
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={{ duration: 1, delay: 1.4 }}
            // Oculto en pantallas muy bajas (celular en horizontal, etc.) —
            // ahí el contenido del hero ya ocupa casi todo el alto y esto
            // se superponía con los botones de descarga.
            className="hidden sm:flex absolute bottom-8 left-1/2 -translate-x-1/2 z-20 flex-col items-center gap-1.5 pointer-events-none"
          >
            <span className="text-white/45 text-xs font-normal tracking-[0.2em] uppercase">Desliza</span>
            <motion.div
              animate={{ y: [0, 10, 0] }}
              transition={{ duration: 1.6, repeat: Infinity, ease: 'easeInOut' }}
              className="flex flex-col -space-y-3"
            >
              <ChevronDown className="w-7 h-7 text-violet-300/70" />
              <ChevronDown className="w-7 h-7 text-violet-300/35" />
            </motion.div>
          </motion.div>
        </div>
      </section>
    </div>
  );
}
