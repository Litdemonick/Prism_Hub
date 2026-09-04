import { motion } from 'motion/react';
import { useLang } from '../lib/i18n';
import { requirements } from '../lib/requirements';

const fadeUp = {
  initial: { opacity: 0, y: 18 },
  whileInView: { opacity: 1, y: 0 },
  viewport: { once: true, margin: '-60px' },
  transition: { duration: 0.5, ease: 'easeOut' as const },
};

/** La tabla de requisitos mínimos/recomendados — compartida entre Inicio y
 * las páginas de cada plataforma, para que alguien que llega directo a
 * /windows (sin pasar por Inicio) la vea igual. */
export default function RequirementsTable({ compact = false }: { compact?: boolean }) {
  const { t, lang } = useLang();
  const r = requirements[lang];
  const rows: { label: string; key: keyof typeof r.min }[] = [
    { label: t('requirements.os'), key: 'os' },
    { label: t('requirements.ram'), key: 'ram' },
    { label: t('requirements.cpu'), key: 'cpu' },
    { label: t('requirements.storage'), key: 'storage' },
  ];

  return (
    <div className={compact ? '' : 'mx-auto max-w-4xl'}>
      {!compact && (
        <motion.div {...fadeUp} className="mb-6 text-center">
          <h2 className="font-[family-name:var(--font-display)] text-xl font-bold tracking-tight sm:text-2xl">
            {t('requirements.title')}
          </h2>
          <p className="mx-auto mt-2 max-w-xl text-sm leading-relaxed" style={{ color: 'var(--text-muted)' }}>
            {t('requirements.desc')}
          </p>
        </motion.div>
      )}

      <motion.div {...fadeUp} className="surface overflow-hidden rounded-2xl">
        <div className="grid grid-cols-3 text-sm">
          <div className="p-4" />
          <div className="border-b border-l p-4 text-center font-semibold" style={{ borderColor: 'var(--border)' }}>
            {t('requirements.min')}
          </div>
          <div
            className="border-b border-l p-4 text-center font-semibold"
            style={{ borderColor: 'var(--border)', color: 'var(--accent)' }}
          >
            {t('requirements.rec')}
          </div>
          {rows.map((row) => (
            <div key={row.key} className="contents">
              <div className="border-t p-4 font-medium" style={{ borderColor: 'var(--border)', color: 'var(--text-muted)' }}>
                {row.label}
              </div>
              <div className="border-t border-l p-4 text-center" style={{ borderColor: 'var(--border)' }}>
                {r.min[row.key]}
              </div>
              <div className="border-t border-l p-4 text-center font-medium" style={{ borderColor: 'var(--border)' }}>
                {r.rec[row.key]}
              </div>
            </div>
          ))}
        </div>
      </motion.div>
      <p className="mx-auto mt-4 max-w-2xl text-center text-xs leading-relaxed" style={{ color: 'var(--text-faint)' }}>
        {t('requirements.note')}
      </p>
    </div>
  );
}
