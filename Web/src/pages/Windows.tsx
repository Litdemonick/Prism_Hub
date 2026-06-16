import { useState } from 'react';
import { motion } from 'motion/react';
import { Copy, Check } from 'lucide-react';
import Navbar from '../components/Navbar';
import PrismBg from '../components/PrismBg';

const installCommand = 'irm https://raw.githubusercontent.com/Litdemonick/Prism_Hub/main/install/install.ps1 | iex';

export default function Windows() {
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
              className="w-full max-w-lg"
            >
              <div className="flex items-center gap-2 mb-5 justify-center">
                <svg fill="currentColor" strokeWidth="0" viewBox="0 0 448 512" className="w-5 h-5 text-violet-400">
                  <path d="M0 93.7l183.6-25.3v177.4H0V93.7zm0 324.6l183.6 25.3V268.4H0v149.9zm203.8 28L448 480V268.4H203.8v177.9zm0-380.6v180.1H448V32L203.8 65.7z" />
                </svg>
                <span className="text-white text-lg font-normal">Instalar en Windows</span>
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
                Pega esto en PowerShell como administrador
              </p>
              <p className="mt-5 text-center">
                <a
                  href="https://github.com/Litdemonick/Prism_Hub/releases/latest"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-violet-400 hover:text-violet-300 text-sm transition-colors underline underline-offset-4"
                >
                  O descarga el instalador .exe desde Releases →
                </a>
              </p>
            </motion.div>
          </div>
        </div>
      </section>
    </div>
  );
}
