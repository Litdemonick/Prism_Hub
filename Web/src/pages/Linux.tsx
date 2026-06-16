import { useState } from 'react';
import { motion } from 'motion/react';
import { Copy, Check } from 'lucide-react';
import Navbar from '../components/Navbar';
import PrismBg from '../components/PrismBg';

const installCommand = 'curl -fsSL https://raw.githubusercontent.com/Litdemonick/Prism_Hub/main/install/install.sh | bash';

export default function Linux() {
  const [copied, setCopied] = useState(false);

  const handleCopy = async () => {
    await navigator.clipboard.writeText(installCommand);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <div className="w-full h-screen flex items-center justify-center p-3 md:p-5 bg-[#08080f]">
      <section className="relative w-full max-w-[1536px] h-full rounded-[1.5rem] md:rounded-[3rem] overflow-hidden flex flex-col items-center">
        <PrismBg />
        <div className="relative z-10 w-full h-full flex flex-col items-center">
          <Navbar />
          <div className="flex-1 flex items-center justify-center px-6 w-full">
            <motion.div
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.6 }}
              className="w-full max-w-xl"
            >
              <div className="flex items-center gap-2 mb-5 justify-center">
                <svg fill="currentColor" stroke="currentColor" strokeWidth="0" viewBox="0 0 448 512" className="w-5 h-5 text-violet-400">
                  <path d="M220.8 123.3c1 .5 1.8 1.7 3 1.7 1.1 0 2.8-.4 2.9-1.5.2-1.4-1.9-2.3-3.2-2.9-1.7-.7-3.9-1-5.5-.1-.4.2-.8.7-.6 1.1.3 1.3 2.3 1.1 3.4 1.7zm-21.9 1.7c1.2 0 2-1.2 3-1.7 1.1-.6 3.1-.4 3.5-1.6.2-.4-.2-.9-.6-1.1-1.6-.9-3.8-.6-5.5.1-1.3.6-3.4 1.5-3.2 2.9.1 1 1.8 1.5 2.8 1.4zM420 403.8c-3.6-4-5.3-11.6-7.2-19.7-1.8-8.1-3.9-16.8-10.5-22.4-1.3-1.1-2.6-2.1-4-2.9-1.3-.8-2.7-1.5-4.1-2 9.2-27.3 5.6-54.5-3.7-79.1-11.4-30.1-31.3-56.4-46.5-74.4-17.1-21.5-33.7-41.9-33.4-72C311.1 85.4 315.7.1 234.8 0 132.4-.2 158 103.4 156.9 135.2c-1.7 23.4-6.4 41.8-22.5 64.7-18.9 22.5-45.5 58.8-58.1 96.7-6 17.9-8.8 36.1-6.2 53.3-6.5 5.8-11.4 14.7-16.6 20.2-4.2 4.3-10.3 5.9-17 8.3s-14 6-18.5 14.5c-2.1 3.9-2.8 8.1-2.8 12.4 0 3.9.6 7.9 1.2 11.8 1.2 8.1 2.5 15.7.8 20.8-5.2 14.4-5.9 24.4-2.2 31.7 3.8 7.3 11.4 10.5 20.1 12.3 17.3 3.6 40.8 2.7 59.3 12.5 19.8 10.4 39.9 14.1 55.9 10.4 11.6-2.6 21.1-9.6 25.9-20.2 12.5-.1 26.3-5.4 48.3-6.6 14.9-1.2 33.6 5.3 55.1 4.1.6 2.3 1.4 4.6 2.5 6.7v.1c8.3 16.7 23.8 24.3 40.3 23 16.6-1.3 34.1-11 48.3-27.9 13.6-16.4 36-23.2 50.9-32.2 7.4-4.5 13.4-10.1 13.9-18.3.4-8.2-4.4-17.3-15.5-29.7z" />
                </svg>
                <span className="text-white text-lg font-normal">Instalar en Linux</span>
              </div>
              <div className="flex items-stretch gap-0 glass-card rounded-2xl overflow-hidden">
                <pre className="flex-1 overflow-x-auto text-sm font-mono text-violet-300 leading-relaxed px-5 py-4 whitespace-nowrap scrollbar-thin bg-transparent">
                  <code>{installCommand}</code>
                </pre>
                <button
                  onClick={handleCopy}
                  className="flex items-center justify-center px-5 py-4 bg-violet-500/10 hover:bg-violet-500/20 transition-colors border-l border-white/5"
                >
                  {copied
                    ? <Check className="w-4 h-4 text-green-400" />
                    : <Copy className="w-4 h-4 text-white/50 hover:text-white" />
                  }
                </button>
              </div>
              <p className="mt-3 text-[12px] text-white/30 font-normal text-center">
                Pega esto en tu terminal
              </p>
              <div className="mt-6 glass-card rounded-2xl px-5 py-4">
                <p className="text-white/40 text-xs mb-3 font-mono">Arch Linux (PKGBUILD)</p>
                <pre className="text-violet-300 text-sm font-mono">{'cd install && makepkg -si'}</pre>
              </div>
            </motion.div>
          </div>
        </div>
      </section>
    </div>
  );
}
