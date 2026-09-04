import { useState } from 'react';
import { Copy, Check } from 'lucide-react';

/** Un comando de consola con botón de copiar — usado en las páginas de
 * instalación (Windows/Linux) y en Docs. */
export default function ConsoleCommand({ command, hint }: { command: string; hint?: string }) {
  const [copied, setCopied] = useState(false);

  const handleCopy = async () => {
    try {
      await navigator.clipboard.writeText(command);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      // Sin permiso de portapapeles (algunos navegadores en http, o el
      // usuario lo negó): el comando sigue siendo seleccionable a mano.
    }
  };

  return (
    <div>
      <div className="code-block flex items-stretch overflow-hidden rounded-2xl">
        <pre className="scrollbar-thin flex-1 overflow-x-auto whitespace-nowrap px-5 py-4 text-sm leading-relaxed" style={{ color: 'var(--accent)' }}>
          <code>{command}</code>
        </pre>
        <button
          type="button"
          onClick={handleCopy}
          aria-label="Copiar comando"
          className="flex items-center justify-center border-l px-5 transition-colors hover:opacity-80"
          style={{ borderColor: 'var(--border)' }}
        >
          {copied ? <Check className="h-4 w-4 text-emerald-500" /> : <Copy className="h-4 w-4" style={{ color: 'var(--text-faint)' }} />}
        </button>
      </div>
      {hint && (
        <p className="mt-3 text-center text-xs" style={{ color: 'var(--text-faint)' }}>
          {hint}
        </p>
      )}
    </div>
  );
}
