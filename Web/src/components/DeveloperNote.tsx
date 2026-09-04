import { motion } from 'motion/react';
import { ShieldCheck, Mail, MessageCircle, GitFork } from 'lucide-react';
import { useLang } from '../lib/i18n';

const copy = {
  es: {
    badge: 'Antes de instalar — de parte del desarrollador',
    trustTitle: '¿Windows o Android dicen que esta app puede ser peligrosa?',
    trustBody:
      'Es un falso positivo, y tiene una explicación simple: el instalador todavía no tiene una firma digital (ese certificado cuesta dinero, y este proyecto no cobra nada). Sin firma, Windows (SmartScreen) y Android (Play Protect) desconfían de cualquier programa nuevo, lo hagan bien o mal.',
    trustList: [
      'PrismHub no instala nada oculto ni recolecta datos de quien lo usa: no hay cuentas, no hay servidores propios registrando qué mirás.',
      'Todo el contenido sale de extensiones que leen sitios web públicos y lo unifican en una sola app — PrismHub no aloja ni distribuye nada por su cuenta.',
      'El código es abierto de punta a punta (AGPL-3.0): se puede leer, auditar y compilar desde cero. Nada de criptomonedas, nada ilegal escondido en algún lado.',
    ],
    trustClosing:
      'Nada de esto es un "confiá porque sí": el código está publicado para que cualquiera lo revise. Y esto sigue siendo trabajo en curso — cada versión apunta a que la app sea cada vez más segura, no menos.',
    personalTitle: 'Un mensaje personal',
    personalBody:
      'Este proyecto lo hago solo — programo, diseño y pruebo todo yo, a veces hasta tarde, para que la calidad y la estabilidad estén a la altura. Todavía es una beta: es funcional, pero seguro faltan cosas por pulir. Tu feedback y tu paciencia probando ayudan más de lo que parece, hasta que salga la primera versión oficial.',
    contactTitle: 'Reportá cualquier error, sin vueltas',
    contactEmail: 'Correo',
    contactIssues: 'Issues en GitHub',
    contactDiscord: 'Discord — canal #soporte-prismhub',
  },
  en: {
    badge: 'Before installing — a note from the developer',
    trustTitle: 'Does Windows or Android say this app might be dangerous?',
    trustBody:
      "It's a false positive, and the reason is simple: the installer doesn't have a digital signature yet (that certificate costs money, and this project charges nothing). Without a signature, Windows (SmartScreen) and Android (Play Protect) distrust any new program, good or bad.",
    trustList: [
      "PrismHub doesn't install anything hidden or collect data from whoever uses it: no accounts, no servers of ours logging what you watch.",
      "All content comes from extensions that read public websites and bring it together in one app — PrismHub doesn't host or distribute anything on its own.",
      'The code is open end to end (AGPL-3.0): readable, auditable, buildable from scratch. No cryptocurrency, nothing illegal hidden anywhere.',
    ],
    trustClosing:
      "None of this is a \"just trust me\": the code is published so anyone can check it. And this is still ongoing work — every release aims to make the app more secure, never less.",
    personalTitle: 'A personal note',
    personalBody:
      "I build this alone — I code, design and test everything myself, sometimes staying up late so the quality and stability hold up. It's still a beta: functional, but there's surely rough edges left. Your feedback and patience testing it help more than you'd think, until the first official release ships.",
    contactTitle: 'Report any bug, no red tape',
    contactEmail: 'Email',
    contactIssues: 'GitHub Issues',
    contactDiscord: 'Discord — #soporte-prismhub channel',
  },
} as const;

export default function DeveloperNote() {
  const { lang } = useLang();
  const c = copy[lang];

  return (
    <motion.div
      initial={{ opacity: 0, y: 16 }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true, margin: '-40px' }}
      transition={{ duration: 0.4 }}
      className="surface rounded-2xl p-6"
    >
      <div
        className="mb-4 inline-flex items-center gap-2 rounded-xl border px-3 py-1.5 text-[11px] font-semibold uppercase leading-snug tracking-wide"
        style={{ borderColor: 'var(--border)', color: 'var(--accent)' }}
      >
        <ShieldCheck className="h-3.5 w-3.5 shrink-0" />
        {c.badge}
      </div>

      <h3 className="mb-2 font-[family-name:var(--font-display)] text-base font-semibold">{c.trustTitle}</h3>
      <p className="mb-3 text-sm leading-relaxed" style={{ color: 'var(--text-muted)' }}>{c.trustBody}</p>
      <ul className="mb-6 flex flex-col gap-2">
        {c.trustList.map((item) => (
          <li key={item} className="flex gap-2 text-xs leading-relaxed" style={{ color: 'var(--text-muted)' }}>
            <span className="mt-1.5 h-1 w-1 shrink-0 rounded-full" style={{ background: 'var(--accent)' }} />
            {item}
          </li>
        ))}
      </ul>
      <p className="mb-6 text-xs italic leading-relaxed" style={{ color: 'var(--text-faint)' }}>{c.trustClosing}</p>

      <div className="border-t pt-5" style={{ borderColor: 'var(--border)' }}>
        <h3 className="mb-2 font-[family-name:var(--font-display)] text-base font-semibold">{c.personalTitle}</h3>
        <p className="mb-5 text-sm leading-relaxed" style={{ color: 'var(--text-muted)' }}>{c.personalBody}</p>

        <p className="mb-3 text-xs font-semibold uppercase tracking-wide" style={{ color: 'var(--text-faint)' }}>
          {c.contactTitle}
        </p>
        <div className="flex flex-wrap gap-2">
          <a
            href="mailto:badleon2744@gmail.com"
            className="surface-2 flex items-center gap-2 rounded-full px-3.5 py-2 text-xs font-medium transition-opacity hover:opacity-80"
          >
            <Mail className="h-3.5 w-3.5" style={{ color: 'var(--accent)' }} />
            {c.contactEmail}
          </a>
          <a
            href="https://github.com/Litdemonick/Prism_Hub/issues"
            target="_blank"
            rel="noopener noreferrer"
            className="surface-2 flex items-center gap-2 rounded-full px-3.5 py-2 text-xs font-medium transition-opacity hover:opacity-80"
          >
            <GitFork className="h-3.5 w-3.5" style={{ color: 'var(--accent)' }} />
            {c.contactIssues}
          </a>
          <a
            href="https://discord.gg/a9vBhQwqHa"
            target="_blank"
            rel="noopener noreferrer"
            className="surface-2 flex items-center gap-2 rounded-full px-3.5 py-2 text-xs font-medium transition-opacity hover:opacity-80"
          >
            <MessageCircle className="h-3.5 w-3.5" style={{ color: 'var(--accent)' }} />
            {c.contactDiscord}
          </a>
        </div>
      </div>
    </motion.div>
  );
}
