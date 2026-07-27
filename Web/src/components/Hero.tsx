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
          <div className="w-full flex flex-col items-center pt-8 px-6 text-center max-w-4xl">
            <HeroBadge />
            <motion.h1
              initial={{ opacity: 0, scale: 0.97 }}
              animate={{ opacity: 1, scale: 1 }}
              transition={{ duration: 0.8, delay: 0.2 }}
              className="text-5xl sm:text-6xl md:text-7xl lg:text-[88px] font-normal text-white mb-3 tracking-tight leading-[1.05]"
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
            className="absolute bottom-6 left-1/2 -translate-x-1/2 z-20 flex flex-col items-center gap-1 pointer-events-none"
          >
            <span className="text-white/25 text-[10px] tracking-widest uppercase">Desliza</span>
            <motion.div
              animate={{ y: [0, 6, 0] }}
              transition={{ duration: 1.6, repeat: Infinity, ease: 'easeInOut' }}
            >
              <ChevronDown className="w-4 h-4 text-white/25" />
            </motion.div>
          </motion.div>
        </div>
      </section>
    </div>
  );
}
