import { motion } from 'motion/react';
import Navbar from '../components/Navbar';
import PrismBg from '../components/PrismBg';

const sections = [
  { title: 'Preámbulo', content: 'La GNU Affero General Public License es una licencia copyleft para software, diseñada específicamente para garantizar la cooperación con la comunidad. A diferencia de licencias permisivas, la AGPL-3.0 asegura que cualquier versión modificada distribuida (incluso como servicio de red) debe compartir su código fuente con los usuarios.' },
  { title: '0. Definiciones', content: '"La Licencia" se refiere a la versión 3 de la GNU AGPL. "El Programa" es cualquier obra protegida bajo esta licencia. "Modificar" significa copiar o adaptar la obra. "Obra cubierta" es el Programa sin modificar o una obra basada en él.' },
  { title: '2. Permisos básicos', content: 'Puedes ejecutar, copiar y distribuir copias del Programa. Puedes modificar el Programa y distribuir versiones modificadas. Todo esto es válido siempre que se cumplan las condiciones de esta licencia.' },
  { title: '5. Distribución de versiones modificadas', content: 'Si distribuyes versiones modificadas, debes indicar los cambios realizados, mantener esta licencia en el código distribuido, y publicar el código fuente completo bajo los mismos términos.' },
  { title: '13. Uso remoto (clave AGPL)', content: 'Si el Programa interactúa con usuarios a través de una red, debes ofrecer acceso al código fuente. Esto distingue a la AGPL-3.0 de la GPL estándar y asegura que las versiones en servidor también sean open source.' },
  { title: '15. Sin garantía', content: 'EL PROGRAMA SE DISTRIBUYE "TAL CUAL", SIN GARANTÍA DE NINGÚN TIPO, NI EXPRESA NI IMPLÍCITA, INCLUYENDO GARANTÍAS DE COMERCIABILIDAD O ADECUACIÓN PARA UN PROPÓSITO PARTICULAR.' },
  { title: '16. Limitación de responsabilidad', content: 'EN NINGÚN CASO EL TITULAR DEL COPYRIGHT SERÁ RESPONSABLE POR DAÑOS, INCLUYENDO DAÑOS GENERALES, ESPECIALES, INCIDENTALES O CONSECUENTES DERIVADOS DEL USO O IMPOSIBILIDAD DE USO DEL PROGRAMA.' },
];

export default function License() {
  return (
    <div className="w-full min-h-screen flex items-start justify-center p-3 md:p-5 bg-[#08080f]">
      <section className="relative w-full max-w-[1536px] min-h-[calc(100vh-1.5rem)] rounded-[1.5rem] md:rounded-[3rem] overflow-hidden flex flex-col items-center">
        <PrismBg />
        <div className="relative z-10 w-full h-full flex flex-col items-center">
          <Navbar />
          <div className="flex-1 w-full max-w-3xl px-6 pb-16 pt-4">
            <motion.div initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.5 }} className="mb-10 text-center">
              <h1 className="text-2xl md:text-4xl font-normal text-white tracking-tight mb-2">
                GNU Affero General Public License
              </h1>
              <p className="text-white/30 text-sm">Version 3 · 19 November 2007</p>
              <div className="mt-4 glass-card rounded-2xl px-5 py-4 text-left">
                <p className="text-violet-400 text-sm font-normal mb-1">PrismHub</p>
                <p className="text-white/50 text-xs leading-relaxed">
                  Aplicación multiplataforma open source para anime, manga y series.<br />
                  Copyright © 2026 Soul_Of_The_sun (<a href="https://github.com/Litdemonick" target="_blank" rel="noopener noreferrer" className="text-violet-400 hover:text-violet-300 underline">github.com/Litdemonick</a>)
                </p>
                <p className="text-white/30 text-xs mt-3 leading-relaxed">
                  Este programa es software libre: puedes redistribuirlo y/o modificarlo bajo los términos de la GNU AGPL v3 o posterior. Se distribuye con la esperanza de que sea útil, pero SIN GARANTÍA ALGUNA.
                </p>
              </div>
            </motion.div>

            <div className="flex flex-col gap-4">
              {sections.map((section, i) => (
                <motion.div key={i} initial={{ opacity: 0, y: 16 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.4, delay: i * 0.04 }} className="rounded-2xl glass-card px-6 py-5">
                  <h2 className="text-white text-base font-normal mb-3">{section.title}</h2>
                  <p className="text-white/50 text-xs md:text-sm font-normal leading-relaxed">{section.content}</p>
                </motion.div>
              ))}

              <motion.div initial={{ opacity: 0, y: 16 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.4, delay: sections.length * 0.04 }} className="rounded-2xl glass-card px-6 py-5">
                <h2 className="text-white text-base font-normal mb-3">Texto completo de la licencia</h2>
                <p className="text-white/40 text-xs leading-relaxed mb-3">El texto legal completo en inglés se encuentra en el repositorio y en:</p>
                <a href="https://www.gnu.org/licenses/agpl-3.0.html" target="_blank" rel="noopener noreferrer" className="text-violet-400 hover:text-violet-300 underline text-sm transition-colors">
                  gnu.org/licenses/agpl-3.0.html →
                </a>
              </motion.div>
            </div>
          </div>
        </div>
      </section>
    </div>
  );
}
