import { useState, useEffect } from 'react';
import { ArrowUpRight } from 'lucide-react';
import { motion } from 'motion/react';

function formatCount(n: number): string {
  if (n >= 1000) return `${(n / 1000).toFixed(n % 1000 === 0 ? 0 : 1).replace('.0', '')}K`;
  return String(n);
}

export default function BottomLeftCard() {
  const [stars, setStars] = useState<number | null>(null);

  useEffect(() => {
    fetch('https://api.github.com/repos/Litdemonick/Prism_Hub')
      .then(r => r.json())
      .then(d => setStars(d.stargazers_count))
      .catch(() => setStars(null));
  }, []);

  return (
    <motion.div
      initial={{ x: -20, opacity: 0 }}
      animate={{ x: 0, opacity: 1 }}
      transition={{ duration: 0.8, delay: 0.2 }}
      className="absolute bottom-28 right-4 left-auto md:left-6 md:right-auto md:bottom-6 lg:bottom-10 lg:left-10 p-3 md:p-4 lg:p-5 rounded-[1.2rem] md:rounded-[1.5rem] lg:rounded-[2.2rem] glass-card flex flex-col gap-2 lg:gap-3 min-w-[180px] md:min-w-[200px] lg:min-w-[220px] w-fit"
    >
      <div className="flex items-center justify-between">
        <div className="flex flex-col">
          <span className="text-2xl md:text-3xl font-normal prism-text tracking-tight">
            {stars !== null ? formatCount(stars) : '—'}
          </span>
          <span className="text-[10px] md:text-[12px] font-normal text-violet-300/70 tracking-wider">GitHub Stars</span>
        </div>
        <svg width="40" height="40" viewBox="0 0 256 256" fill="none" xmlns="http://www.w3.org/2000/svg">
          <rect width="256" height="256" rx="60" fill="#1a1a2e"/>
          <path d="M128.001 30C72.7791 30 28 74.7708 28 130.001C28 174.184 56.6533 211.668 96.3867 224.891C101.384 225.817 103.219 222.722 103.219 220.081C103.219 217.696 103.126 209.819 103.083 201.463C75.2631 207.512 69.3927 189.664 69.3927 189.664C64.8437 178.105 58.2894 175.032 58.2894 175.032C49.2163 168.825 58.9733 168.953 58.9733 168.953C69.0151 169.658 74.3026 179.258 74.3026 179.258C83.2217 194.546 97.6965 190.126 103.403 187.571C104.301 181.107 106.892 176.696 109.752 174.199C87.5405 171.67 64.1913 163.095 64.1913 124.778C64.1913 113.86 68.0977 104.939 74.4947 97.9362C73.4564 95.4175 70.0335 85.2465 75.4635 71.4722C75.4635 71.4722 83.8609 68.7845 102.971 81.7226C110.948 79.5069 119.502 78.3958 128.001 78.3577C136.499 78.3958 145.061 79.5069 153.052 81.7226C172.139 68.7845 180.525 71.4722 180.525 71.4722C185.968 85.2465 182.544 95.4175 181.505 97.9362C187.917 104.939 191.797 113.86 191.797 124.778C191.797 163.187 168.403 171.644 146.135 174.119C149.722 177.223 152.918 183.308 152.918 192.638C152.918 206.018 152.802 216.787 152.802 220.081C152.802 222.742 154.602 225.86 159.671 224.878C199.383 211.64 228 174.169 228 130.001C228 74.7708 183.227 30 128.001 30Z" fill="white"/>
        </svg>
      </div>
      <motion.a
        href="https://github.com/Litdemonick/Prism_Hub"
        target="_blank"
        rel="noopener noreferrer"
        whileHover={{ scale: 1.02 }}
        whileTap={{ scale: 0.98 }}
        className="flex items-center bg-violet-600/20 hover:bg-violet-600/30 border border-violet-500/20 rounded-full pl-1.5 pr-4 py-1.5 gap-2 transition-colors self-start"
      >
        <div className="bg-violet-500/20 p-1 rounded-full">
          <ArrowUpRight className="w-3.5 h-3.5 text-violet-300" />
        </div>
        <span className="text-[13px] font-normal text-violet-200">Ver repositorio</span>
      </motion.a>
    </motion.div>
  );
}
