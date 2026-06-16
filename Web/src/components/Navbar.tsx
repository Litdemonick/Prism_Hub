import { ArrowUpRight } from 'lucide-react';
import { motion } from 'motion/react';
import { Link } from 'react-router-dom';

function NavItem({ label, to }: { label: string; to: string }) {
  return (
    <li>
      <Link
        to={to}
        className="text-white/60 hover:text-white transition-colors text-sm font-normal"
      >
        {label}
      </Link>
    </li>
  );
}

export default function Navbar() {
  return (
    <nav className="flex items-center justify-between py-6 px-6 md:px-10 w-full relative z-10">
      <Link to="/" className="flex items-center gap-2 group">
        <span className="prism-text text-lg font-normal tracking-tight">PrismHub</span>
      </Link>

      <ul className="hidden md:flex items-center gap-8">
        <NavItem label="Inicio" to="/" />
        <NavItem label="Docs" to="/docs" />
        <NavItem label="FAQ" to="/faq" />
        <NavItem label="Extensiones" to="/developers" />
        <NavItem label="Licencia" to="/license" />
      </ul>

      <motion.a
        href="https://github.com/Litdemonick/Prism_Hub"
        target="_blank"
        rel="noopener noreferrer"
        whileHover={{ scale: 1.02 }}
        whileTap={{ scale: 0.98 }}
        className="flex items-center gap-2 bg-white/8 hover:bg-white/12 border border-white/10 text-white rounded-full pl-2 pr-4 py-1.5 transition-colors btn-glow"
      >
        <div className="bg-white/10 p-1 rounded-full">
          <ArrowUpRight className="w-4 h-4" />
        </div>
        <span className="text-xs font-normal">GitHub</span>
      </motion.a>
    </nav>
  );
}
