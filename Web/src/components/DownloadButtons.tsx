import { motion } from 'motion/react';
import { useNavigate } from 'react-router-dom';

const LinuxIcon = () => (
  <svg fill="currentColor" stroke="currentColor" strokeWidth="0" viewBox="0 0 448 512" className="w-4 h-4">
    <path d="M220.8 123.3c1 .5 1.8 1.7 3 1.7 1.1 0 2.8-.4 2.9-1.5.2-1.4-1.9-2.3-3.2-2.9-1.7-.7-3.9-1-5.5-.1-.4.2-.8.7-.6 1.1.3 1.3 2.3 1.1 3.4 1.7zm-21.9 1.7c1.2 0 2-1.2 3-1.7 1.1-.6 3.1-.4 3.5-1.6.2-.4-.2-.9-.6-1.1-1.6-.9-3.8-.6-5.5.1-1.3.6-3.4 1.5-3.2 2.9.1 1 1.8 1.5 2.8 1.4zM420 403.8c-3.6-4-5.3-11.6-7.2-19.7-1.8-8.1-3.9-16.8-10.5-22.4-1.3-1.1-2.6-2.1-4-2.9-1.3-.8-2.7-1.5-4.1-2 9.2-27.3 5.6-54.5-3.7-79.1-11.4-30.1-31.3-56.4-46.5-74.4-17.1-21.5-33.7-41.9-33.4-72C311.1 85.4 315.7.1 234.8 0 132.4-.2 158 103.4 156.9 135.2c-1.7 23.4-6.4 41.8-22.5 64.7-18.9 22.5-45.5 58.8-58.1 96.7-6 17.9-8.8 36.1-6.2 53.3-6.5 5.8-11.4 14.7-16.6 20.2-4.2 4.3-10.3 5.9-17 8.3s-14 6-18.5 14.5c-2.1 3.9-2.8 8.1-2.8 12.4 0 3.9.6 7.9 1.2 11.8 1.2 8.1 2.5 15.7.8 20.8-5.2 14.4-5.9 24.4-2.2 31.7 3.8 7.3 11.4 10.5 20.1 12.3 17.3 3.6 40.8 2.7 59.3 12.5 19.8 10.4 39.9 14.1 55.9 10.4 11.6-2.6 21.1-9.6 25.9-20.2 12.5-.1 26.3-5.4 48.3-6.6 14.9-1.2 33.6 5.3 55.1 4.1.6 2.3 1.4 4.6 2.5 6.7v.1c8.3 16.7 23.8 24.3 40.3 23 16.6-1.3 34.1-11 48.3-27.9 13.6-16.4 36-23.2 50.9-32.2 7.4-4.5 13.4-10.1 13.9-18.3.4-8.2-4.4-17.3-15.5-29.7z" />
  </svg>
);

const WindowsIcon = () => (
  <svg fill="currentColor" strokeWidth="0" viewBox="0 0 448 512" className="w-4 h-4">
    <path d="M0 93.7l183.6-25.3v177.4H0V93.7zm0 324.6l183.6 25.3V268.4H0v149.9zm203.8 28L448 480V268.4H203.8v177.9zm0-380.6v180.1H448V32L203.8 65.7z" />
  </svg>
);

const AndroidIcon = () => (
  <svg fill="currentColor" strokeWidth="0" viewBox="0 0 24 24" className="w-4 h-4">
    <path d="M17.523 15.341A5.036 5.036 0 0 0 17 13v-2a5 5 0 0 0-10 0v2c0 .857-.122 1.476-.523 2.341C6 16 5 17 5 18c0 .553.448 1 1 1h12c.552 0 1-.447 1-1 0-1-1-2-1.477-2.659zM12 23c1.1 0 2-.9 2-2h-4c0 1.1.9 2 2 2zm-1-19.938C8.162 3.553 6 6.027 6 9v.268A3 3 0 0 1 7 9a3 3 0 0 1 3-3c0-.656-.216-1.268-.582-1.765L9 4l.418-.579A2.994 2.994 0 0 1 12 3c1.15 0 2.16.647 2.678 1.597L15.1 4.5l.322.5A3 3 0 0 1 18 9a3 3 0 0 1 1-.268V9c0-2.973-2.162-5.447-5-5.938z"/>
  </svg>
);

const platforms = [
  { name: 'Linux',   icon: LinuxIcon,   route: '/linux'   as const },
  { name: 'Windows', icon: WindowsIcon, route: '/windows' as const },
  { name: 'Android', icon: AndroidIcon, route: null, href: 'https://github.com/Litdemonick/Prism_Hub/releases/latest' },
];

export default function DownloadButtons() {
  const navigate = useNavigate();

  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.6, delay: 0.6, ease: 'easeOut' }}
      className="flex items-center gap-3 mt-8 flex-wrap justify-center"
    >
      {platforms.map((p) => (
        <motion.button
          key={p.name}
          whileHover={{ scale: 1.04 }}
          whileTap={{ scale: 0.97 }}
          onClick={() => p.route ? navigate(p.route) : window.open(p.href, '_blank')}
          className="flex items-center gap-2 px-5 py-2.5 rounded-full border border-white/10 bg-white/5 hover:bg-white/10 hover:border-violet-500/30 text-white/80 hover:text-white transition-all backdrop-blur-md btn-glow"
        >
          <p.icon />
          <span className="text-[14px] font-normal">{p.name}</span>
        </motion.button>
      ))}
    </motion.div>
  );
}
