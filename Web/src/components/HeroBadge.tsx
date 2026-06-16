import { Sparkles } from 'lucide-react';
import { motion } from 'motion/react';

export default function HeroBadge() {
  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.6, ease: 'easeOut' }}
      className="flex items-center gap-2 px-4 py-2 rounded-full bg-violet-500/10 border border-violet-500/20 mx-auto mb-4 w-fit backdrop-blur-md"
    >
      <Sparkles className="w-3.5 h-3.5 text-violet-400" />
      <span className="text-[13px] font-normal text-violet-300">Open Source · AGPL-3.0</span>
    </motion.div>
  );
}
