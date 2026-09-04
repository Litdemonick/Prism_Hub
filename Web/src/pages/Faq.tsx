import { useMemo, useState, type ComponentType } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { ChevronDown, Search, MessageSquarePlus, RefreshCw, Trash2 } from 'lucide-react';
import Layout from '../components/Layout';
import { WindowsIcon, LinuxIcon, AndroidIcon } from '../components/PlatformIcons';
import { useLang } from '../lib/i18n';

// Los comandos y el orden del menú (1 Instalar, 2 Actualizar, 3 Desinstalar,
// 4 Salir) son los mismos que arman install.ps1 e install.sh — si esos
// cambian, estos pasos se desactualizan y hay que revisarlos junto con ellos.
const winCommand = 'irm https://raw.githubusercontent.com/Litdemonick/Prism_Hub/main/install/install.ps1 | iex';
const linuxCommand = 'curl -fsSL https://raw.githubusercontent.com/Litdemonick/Prism_Hub/main/install/install.sh | bash';

/** Limpia lo que se escribe en el buscador antes de usarlo para filtrar o
 * para armar el enlace a GitHub Issues.
 *
 * ── Qué hace de verdad, y qué no ─────────────────────────────────────────
 *
 * Esto es un buscador que compara texto EN EL NAVEGADOR contra una lista
 * fija de preguntas — no hay ningún servidor, ninguna base de datos, ninguna
 * consulta que se arme con lo que se escribe acá. No hay "inyección SQL"
 * posible porque no hay SQL en ningún lado del sitio: sería agregar un
 * candado a una puerta que no existe.
 *
 * Lo que sí hace falta, y esto SÍ es real:
 *   · Sacar caracteres de control y espacios invisibles (ancho cero, marcas
 *     direccionales) — no aportan nada a una búsqueda y pueden verse como
 *     basura si terminan en la URL del issue de GitHub.
 *   · Colapsar espacios repetidos.
 *   · Poner un tope de largo, para que un pegado accidental de texto enorme
 *     no arme un enlace roto.
 *   · Y al construir el enlace de GitHub, `encodeURIComponent` — eso es lo
 *     que de verdad evita un link malformado o que alguien "escape" de la
 *     URL con caracteres especiales.
 */
function sanitizeQuery(raw: string): string {
  return raw
    .normalize('NFC')
    // \p{Cc} = caracteres de control, \p{Cf} = formato invisible (espacios
    // de ancho cero, marcas direccionales, marca de orden de bytes). Ninguno
    // de los dos aporta a una busqueda ni deberia llegar a la URL del issue.
    .replace(/[\p{Cc}\p{Cf}]/gu, '')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 200);
}

const copy = {
  es: {
    title: 'Preguntas frecuentes',
    searchPlaceholder: 'Buscar en las preguntas...',
    noResultsTitle: 'No encontramos nada con eso',
    noResultsDesc: 'Puede que la respuesta todavía no esté acá. Contanos tu pregunta, sugerencia, error o mejora en GitHub Issues y la revisamos.',
    noResultsButton: 'Escribir en GitHub Issues',
    faqs: [
      {
        q: '¿Qué es PrismHub?',
        a: 'Una aplicación multiplataforma (Windows, Linux, Android) para ver anime, series y películas, y leer manga. Todo el contenido sale de prism+, el repositorio oficial de extensiones — no es algo que cada usuario arme por su cuenta.',
      },
      {
        q: '¿Es compatible con Windows, Linux y Android?',
        a: 'Sí, con instalador propio para cada uno: por consola o instalador .exe en Windows, por consola o paquete .tar.gz en Linux, APK en Android. El mismo APK Universal sirve para teléfono, tablet y Android TV — la app reconoce sola en qué aparato está.',
      },
      {
        q: '¿En qué idioma está el contenido?',
        a: 'El catálogo de prism+ está enfocado en contenido en español, con soporte también en inglés por ahora. La idea es sumar más idiomas con el tiempo, a medida que el catálogo crece.',
      },
      {
        q: '¿De dónde salen las extensiones? ¿Puedo agregar mi propio repositorio?',
        a: 'De un solo lugar: prism+, el repositorio oficial, que ya viene configurado — no hay que agregar ni configurar nada. Las extensiones las arma y firma ese mismo equipo; no es algo que el usuario instale por su cuenta desde otro repositorio.',
      },
      {
        q: '¿Puedo escribir mi propia extensión?',
        a: 'No para uso personal — instalarla por tu cuenta no es una opción soportada. Si programás y te falta un sitio, se puede proponer como código en el repositorio de prism+ (ver la sección Extensiones) para que, si se acepta, pase a formar parte del catálogo oficial para todos.',
      },
      {
        q: '¿Es código abierto?',
        a: 'Sí, bajo licencia AGPL-3.0. Se puede usar, modificar, auditar y distribuir manteniendo el código fuente accesible — el repositorio de la app y el de las extensiones son los dos públicos.',
      },
      {
        q: '¿Qué pasa si un servidor no funciona?',
        a: 'Las extensiones de prism+ devuelven una lista de servidores alternativos para el mismo episodio. Si el que estás usando falla, el reproductor reintenta ese mismo un par de veces por las dudas, pero cambiar a otro es una elección tuya — un toque en el botón "Servidor" y listo, sin tener que salir del episodio ni buscar de nuevo.',
      },
      {
        q: '¿Necesito internet todo el tiempo?',
        a: 'Sí para ver o buscar contenido nuevo, porque se transmite en vivo desde cada sitio — no hay descargas para ver sin conexión. Sin internet, la app te avisa en vez de quedarse esperando: podés seguir viendo tu historial y favoritos guardados una vez que vuelva la conexión.',
      },
      {
        q: '¿Cómo actualizo la app?',
        a: 'Si ya la tenés instalada, la propia app te avisa cuando hay una versión nueva y te ofrece actualizar con un botón, sin salir de ahí. Si preferís hacerlo por consola (Windows/Linux) o bajando el instalador de nuevo, también funciona — es la misma versión, dos caminos.',
      },
      {
        q: '¿Cómo la desinstalo?',
        a: 'En Windows y Linux, el mismo comando de instalación abre un menú con la opción Desinstalar. En Android, como cualquier otra app: mantené presionado el ícono y elegí desinstalar, o desde Ajustes → Aplicaciones.',
      },
      {
        q: 'Windows bloqueó o borró el instalador, ¿está infectado?',
        a: 'No. El .exe todavía no tiene firma digital (ese certificado cuesta dinero, y el proyecto no cobra nada), así que un antivirus puede marcarlo como "desconocido" al primer intento — es un falso positivo común en software nuevo sin firmar, no un virus. Revisá Seguridad de Windows → Protección contra virus y amenazas → Historial de protección, y restauralo desde ahí. Más detalle en la página de instalación de Windows.',
      },
      {
        q: '¿PrismHub cobra algo o guarda mis datos?',
        a: 'No. No hay cuentas, ni pagos, ni servidores propios registrando qué mirás — el historial y los favoritos viven en el aparato donde los usás. El código es público, así que esto se puede verificar leyéndolo, no hay que confiar a ciegas.',
      },
      {
        q: '¿Por qué confiar en PrismHub si no tiene firma digital todavía?',
        a: 'Porque el código es completamente auditable: cualquiera puede leerlo, compilarlo desde cero y comparar el resultado. La firma digital es un trámite pago que todavía no se hizo, no una garantía de seguridad en sí misma — la garantía real es que no hay nada escondido, y está publicado para probarlo.',
      },
    ],
    tutorialsTitle: 'Tutoriales paso a paso',
    tutorials: [
      {
        Icon: WindowsIcon,
        title: 'Instalar en Windows por consola',
        steps: [
          'Abrí PowerShell (buscalo en el menú Inicio, no hace falta abrirlo como administrador).',
          `Pegá este comando y presioná Enter: ${winCommand}`,
          'Esperá a que se descargue el instalador — va a mostrar un menú.',
          'Elegí la opción [1] Instalar.',
          'Si falta el Visual C++ Redistributable, el instalador lo detecta y lo instala solo, sin pedir nada más.',
        ],
      },
      {
        Icon: LinuxIcon,
        title: 'Instalar en Linux por consola',
        steps: [
          'Abrí una terminal.',
          `Pegá este comando y presioná Enter: ${linuxCommand}`,
          'Elegí la opción [1] Instalar en el menú que aparece.',
        ],
      },
      {
        Icon: AndroidIcon,
        title: 'Instalar en Android',
        steps: [
          'Descargá el APK Universal desde la página de Android.',
          'Habilitá "Orígenes desconocidos" cuando el sistema lo pida (solo la primera vez).',
          'Abrí el archivo descargado. Si Play Protect avisa "esta app puede dañar tu dispositivo", tocá "Más detalles" → "Instalar de todas formas" — es el aviso genérico para cualquier app sin firmar de Google, no un análisis real.',
          'Confirmá la instalación.',
        ],
      },
      {
        Icon: RefreshCw,
        title: 'Actualizar a la última versión',
        steps: [
          'Si ya la tenés instalada y abierta: la propia app avisa cuando hay una versión nueva y ofrece actualizar con un botón, ahí mismo.',
          'Por consola en Windows o Linux: corré el mismo comando de instalación de arriba y elegí la opción [2] Actualizar en el menú.',
          'En Android: descargá el APK de nuevo desde la página y abrilo — se instala encima de la versión anterior, sin borrar historial ni favoritos.',
        ],
      },
      {
        Icon: Trash2,
        title: 'Desinstalar',
        steps: [
          'En Windows o Linux: corré el mismo comando de instalación y elegí la opción [3] Desinstalar en el menú.',
          'En Android: mantené presionado el ícono de la app y elegí desinstalar, o andá a Ajustes → Aplicaciones → PrismHub → Desinstalar.',
        ],
      },
    ],
  },
  en: {
    title: 'Frequently asked questions',
    searchPlaceholder: 'Search the questions...',
    noResultsTitle: "We couldn't find anything for that",
    noResultsDesc: "The answer might not be here yet. Tell us your question, suggestion, bug or improvement idea on GitHub Issues and we'll take a look.",
    noResultsButton: 'Open a GitHub Issue',
    faqs: [
      {
        q: 'What is PrismHub?',
        a: 'A cross-platform app (Windows, Linux, Android) for watching anime, series and movies, and reading manga. All the content comes from prism+, the official extensions repository — it\'s not something each user assembles on their own.',
      },
      {
        q: 'Does it support Windows, Linux and Android?',
        a: 'Yes, with its own installer for each: via console or a .exe installer on Windows, via console or a .tar.gz package on Linux, an APK on Android. The same Universal APK works on phone, tablet and Android TV — the app recognizes the device on its own.',
      },
      {
        q: 'What language is the content in?',
        a: "The prism+ catalog is focused on Spanish-language content, with English also supported for now. The plan is to add more languages over time as the catalog grows.",
      },
      {
        q: 'Where do extensions come from? Can I add my own repository?',
        a: "From a single place: prism+, the official repository, already configured out of the box — nothing to add or set up. Extensions are built and signed by that same team; it's not something a user installs on their own from a different repository.",
      },
      {
        q: 'Can I write my own extension?',
        a: "Not for personal use — installing it yourself isn't a supported option. If you code and a site is missing, it can be proposed as code in the prism+ repository (see the Extensions section) so that, if accepted, it becomes part of the official catalog for everyone.",
      },
      {
        q: 'Is it open source?',
        a: 'Yes, under the AGPL-3.0 license. It can be used, modified, audited and distributed as long as the source stays accessible — both the app repository and the extensions one are public.',
      },
      {
        q: "What happens if a server doesn't work?",
        a: 'prism+ extensions return a list of alternate servers for the same episode. If the one you\'re using fails, the player retries it a couple of times just in case, but switching to another one is your call — one tap on the "Server" button and that\'s it, no need to leave the episode or search again.',
      },
      {
        q: 'Do I need internet all the time?',
        a: "Yes to watch or search for new content, since it streams live from each site — there are no offline downloads. Without internet, the app tells you instead of hanging: you can still browse your saved history and favorites once the connection is back.",
      },
      {
        q: 'How do I update the app?',
        a: "If it's already installed, the app itself notifies you when a new version is out and offers to update with a button, without leaving it. If you'd rather do it via console (Windows/Linux) or by downloading the installer again, that works too — same version, two paths.",
      },
      {
        q: 'How do I uninstall it?',
        a: 'On Windows and Linux, the same install command opens a menu with an Uninstall option. On Android, like any other app: long-press the icon and choose uninstall, or go to Settings → Apps.',
      },
      {
        q: 'Windows blocked or deleted the installer — is it infected?',
        a: "No. The .exe doesn't have a digital signature yet (that certificate costs money, and the project charges nothing), so an antivirus may flag it as \"unknown\" on first try — a common false positive for new unsigned software, not a virus. Check Windows Security → Virus & threat protection → Protection history, and restore it from there. More detail on the Windows install page.",
      },
      {
        q: 'Does PrismHub charge anything or store my data?',
        a: "No. There are no accounts, no payments, and no servers of ours logging what you watch — history and favorites live on the device you use them on. The code is public, so this can be checked by reading it, not taken on faith.",
      },
      {
        q: "Why trust PrismHub if it doesn't have a digital signature yet?",
        a: "Because the code is fully auditable: anyone can read it, build it from scratch and compare the result. A digital signature is a paid step that hasn't happened yet, not a security guarantee in itself — the real guarantee is that nothing is hidden, and it's published so that can be checked.",
      },
    ],
    tutorialsTitle: 'Step-by-step tutorials',
    tutorials: [
      {
        Icon: WindowsIcon,
        title: 'Install on Windows via console',
        steps: [
          'Open PowerShell (search for it in the Start menu — no need to run it as administrator).',
          `Paste this command and press Enter: ${winCommand}`,
          "Wait for the installer to download — it'll show a menu.",
          'Choose option [1] Install.',
          "If the Visual C++ Redistributable is missing, the installer detects it and installs it on its own, no extra prompts.",
        ],
      },
      {
        Icon: LinuxIcon,
        title: 'Install on Linux via console',
        steps: [
          'Open a terminal.',
          `Paste this command and press Enter: ${linuxCommand}`,
          'Choose option [1] Install in the menu that shows up.',
        ],
      },
      {
        Icon: AndroidIcon,
        title: 'Install on Android',
        steps: [
          'Download the Universal APK from the Android page.',
          'Enable "Unknown sources" when the system asks (only the first time).',
          'Open the downloaded file. If Play Protect warns "this app can harm your device", tap "More details" → "Install anyway" — that\'s Google\'s generic warning for any unsigned app, not a real scan result.',
          'Confirm the install.',
        ],
      },
      {
        Icon: RefreshCw,
        title: 'Update to the latest version',
        steps: [
          "If it's already installed and open: the app itself notifies you when a new version is out and offers to update with a button, right there.",
          'Via console on Windows or Linux: run the same install command above and choose option [2] Update in the menu.',
          "On Android: download the APK again from the page and open it — it installs over the previous version, without deleting history or favorites.",
        ],
      },
      {
        Icon: Trash2,
        title: 'Uninstall',
        steps: [
          'On Windows or Linux: run the same install command and choose option [3] Uninstall in the menu.',
          'On Android: long-press the app icon and choose uninstall, or go to Settings → Apps → PrismHub → Uninstall.',
        ],
      },
    ],
  },
} as const;

function FaqItem({ question, answer }: { question: string; answer: string }) {
  const [open, setOpen] = useState(false);
  return (
    <motion.div layout className="surface overflow-hidden rounded-2xl">
      <button
        onClick={() => setOpen(!open)}
        className="flex w-full items-center justify-between px-6 py-4 text-left text-sm font-medium md:text-base"
      >
        <span>{question}</span>
        <ChevronDown
          className={`ml-4 h-4 w-4 flex-shrink-0 transition-transform duration-300 ${open ? 'rotate-180' : ''}`}
          style={{ color: 'var(--accent)' }}
        />
      </button>
      <AnimatePresence initial={false}>
        {open && (
          <motion.div
            key="answer"
            initial={{ height: 0, opacity: 0 }}
            animate={{ height: 'auto', opacity: 1 }}
            exit={{ height: 0, opacity: 0 }}
            transition={{ duration: 0.3, ease: 'easeInOut' }}
            className="overflow-hidden"
          >
            <div
              className="whitespace-pre-line border-t px-6 pb-5 pt-3 text-xs leading-relaxed md:text-sm"
              style={{ borderColor: 'var(--border)', color: 'var(--text-muted)' }}
            >
              {answer}
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </motion.div>
  );
}

function TutorialItem({
  Icon,
  title,
  steps,
}: {
  Icon: ComponentType<{ className?: string }>;
  title: string;
  steps: readonly string[];
}) {
  const [open, setOpen] = useState(false);
  return (
    <motion.div layout className="surface overflow-hidden rounded-2xl">
      <button
        onClick={() => setOpen(!open)}
        className="flex w-full items-center gap-3 px-6 py-4 text-left text-sm font-medium md:text-base"
      >
        <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg" style={{ background: 'var(--surface-2)', color: 'var(--accent)' }}>
          <Icon className="h-4 w-4" />
        </span>
        <span className="flex-1">{title}</span>
        <ChevronDown
          className={`h-4 w-4 flex-shrink-0 transition-transform duration-300 ${open ? 'rotate-180' : ''}`}
          style={{ color: 'var(--accent)' }}
        />
      </button>
      <AnimatePresence initial={false}>
        {open && (
          <motion.div
            key="steps"
            initial={{ height: 0, opacity: 0 }}
            animate={{ height: 'auto', opacity: 1 }}
            exit={{ height: 0, opacity: 0 }}
            transition={{ duration: 0.3, ease: 'easeInOut' }}
            className="overflow-hidden"
          >
            <ol
              className="flex flex-col gap-3 border-t px-6 pb-5 pt-4 text-xs leading-relaxed md:text-sm"
              style={{ borderColor: 'var(--border)', color: 'var(--text-muted)' }}
            >
              {steps.map((step, i) => (
                <li key={i} className="flex gap-3">
                  <span
                    className="flex h-5 w-5 shrink-0 items-center justify-center rounded-full text-[11px] font-bold"
                    style={{ background: 'color-mix(in srgb, var(--accent) 16%, transparent)', color: 'var(--accent)' }}
                  >
                    {i + 1}
                  </span>
                  <span className="pt-0.5">{step}</span>
                </li>
              ))}
            </ol>
          </motion.div>
        )}
      </AnimatePresence>
    </motion.div>
  );
}

export default function Faq() {
  const { lang } = useLang();
  const c = copy[lang];
  const [query, setQuery] = useState('');

  const cleanQuery = sanitizeQuery(query);

  const filtered = useMemo(() => {
    if (!cleanQuery) return c.faqs;
    const needle = cleanQuery.toLowerCase();
    return c.faqs.filter(
      (faq) => faq.q.toLowerCase().includes(needle) || faq.a.toLowerCase().includes(needle),
    );
  }, [c.faqs, cleanQuery]);

  const issueUrl = `https://github.com/Litdemonick/Prism_Hub/issues/new?${new URLSearchParams({
    title: cleanQuery,
    body: lang === 'es'
      ? `Pregunta, sugerencia, error o mejora relacionada:\n\n> ${cleanQuery}\n\n(No encontré esto en el FAQ del sitio.)`
      : `Question, suggestion, bug or improvement related to:\n\n> ${cleanQuery}\n\n(I couldn't find this in the site FAQ.)`,
  }).toString()}`;

  return (
    <Layout>
      <section className="px-5 py-16 md:px-10 md:py-24">
        <div className="mx-auto max-w-2xl lg:max-w-3xl">
          <motion.h1
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.5 }}
            className="mb-6 text-center font-[family-name:var(--font-display)] text-3xl font-bold tracking-tight md:text-4xl"
          >
            {c.title}
          </motion.h1>

          <motion.div
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.5, delay: 0.05 }}
            className="surface mb-8 flex items-center gap-3 rounded-2xl px-4 py-3"
          >
            <Search className="h-4 w-4 shrink-0" style={{ color: 'var(--text-faint)' }} />
            <input
              type="text"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder={c.searchPlaceholder}
              maxLength={200}
              className="w-full bg-transparent text-sm placeholder:opacity-60"
            />
          </motion.div>

          <div className="flex flex-col gap-3">
            {filtered.map((faq, i) => (
              <motion.div
                key={faq.q}
                initial={{ opacity: 0, y: 14 }}
                whileInView={{ opacity: 1, y: 0 }}
                viewport={{ once: true, margin: '-40px' }}
                transition={{ duration: 0.4, delay: Math.min(i * 0.05, 0.3) }}
              >
                <FaqItem question={faq.q} answer={faq.a} />
              </motion.div>
            ))}
          </div>

          {cleanQuery.length > 0 && filtered.length === 0 && (
            <motion.div
              initial={{ opacity: 0, y: 10 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.4 }}
              className="surface flex flex-col items-center gap-3 rounded-2xl px-6 py-8 text-center"
            >
              <MessageSquarePlus className="h-6 w-6" style={{ color: 'var(--accent)' }} />
              <div>
                <div className="mb-1 text-sm font-semibold">{c.noResultsTitle}</div>
                <div className="text-xs leading-relaxed" style={{ color: 'var(--text-faint)' }}>{c.noResultsDesc}</div>
              </div>
              <a
                href={issueUrl}
                target="_blank"
                rel="noopener noreferrer"
                className="mt-1 flex items-center gap-2 rounded-xl px-5 py-2.5 text-xs font-semibold transition-transform hover:scale-[1.02] active:scale-[0.98]"
                style={{ background: 'var(--accent)', color: 'var(--accent-ink)' }}
              >
                {c.noResultsButton}
              </a>
            </motion.div>
          )}

          <motion.h2
            initial={{ opacity: 0, y: 10 }}
            whileInView={{ opacity: 1, y: 0 }}
            viewport={{ once: true, margin: '-40px' }}
            transition={{ duration: 0.5 }}
            className="mb-4 mt-14 text-center font-[family-name:var(--font-display)] text-2xl font-bold tracking-tight md:text-3xl"
          >
            {c.tutorialsTitle}
          </motion.h2>
          <div className="flex flex-col gap-3">
            {c.tutorials.map((tut, i) => (
              <motion.div
                key={tut.title}
                initial={{ opacity: 0, y: 14 }}
                whileInView={{ opacity: 1, y: 0 }}
                viewport={{ once: true, margin: '-40px' }}
                transition={{ duration: 0.4, delay: Math.min(i * 0.05, 0.3) }}
              >
                <TutorialItem Icon={tut.Icon} title={tut.title} steps={tut.steps} />
              </motion.div>
            ))}
          </div>
        </div>
      </section>
    </Layout>
  );
}
