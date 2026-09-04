import { motion } from 'motion/react';
import Layout from '../components/Layout';
import { useLang } from '../lib/i18n';

const copy = {
  es: {
    title: 'GNU Affero General Public License',
    version: 'Versión 3 · 19 de noviembre de 2007',
    project: 'PrismHub',
    desc: 'Aplicación multiplataforma open source para anime, manga, series y películas.',
    copyright: 'Copyright © 2026 Soul_Of_The_sun',
    permission:
      'Este programa es software libre: se puede redistribuir y/o modificar bajo los términos de la GNU AGPL v3 o posterior. Se distribuye con la esperanza de que sea útil, pero SIN GARANTÍA ALGUNA.',
    sections: [
      { title: 'Preámbulo', content: 'La GNU Affero General Public License es una licencia copyleft diseñada para garantizar la cooperación con la comunidad. A diferencia de las licencias permisivas, la AGPL-3.0 asegura que cualquier versión modificada distribuida — incluso como servicio de red — comparta su código fuente con los usuarios.' },
      { title: '0. Definiciones', content: '"La Licencia" es la versión 3 de la GNU AGPL. "El Programa" es cualquier obra protegida bajo esta licencia. "Modificar" significa copiar o adaptar la obra. "Obra cubierta" es el Programa sin modificar, o una obra basada en él.' },
      { title: '2. Permisos básicos', content: 'Se puede ejecutar, copiar y distribuir copias del Programa. Se puede modificar y distribuir versiones modificadas, siempre que se cumplan las condiciones de esta licencia.' },
      { title: '5. Distribución de versiones modificadas', content: 'Al distribuir versiones modificadas hay que indicar los cambios hechos, mantener esta licencia en el código distribuido, y publicar el código fuente completo bajo los mismos términos.' },
      { title: '13. Uso remoto (la cláusula AGPL)', content: 'Si el Programa interactúa con usuarios a través de una red, hay que ofrecer acceso al código fuente. Esto distingue a la AGPL-3.0 de la GPL estándar: asegura que las versiones en servidor también sean open source.' },
      { title: '15. Sin garantía', content: 'EL PROGRAMA SE DISTRIBUYE "TAL CUAL", SIN GARANTÍA DE NINGÚN TIPO, NI EXPRESA NI IMPLÍCITA, INCLUYENDO GARANTÍAS DE COMERCIABILIDAD O ADECUACIÓN PARA UN PROPÓSITO PARTICULAR.' },
      { title: '16. Limitación de responsabilidad', content: 'EN NINGÚN CASO EL TITULAR DEL COPYRIGHT SERÁ RESPONSABLE POR DAÑOS GENERALES, ESPECIALES, INCIDENTALES O CONSECUENTES DERIVADOS DEL USO O IMPOSIBILIDAD DE USO DEL PROGRAMA.' },
    ],
    fullTextTitle: 'Texto completo de la licencia',
    fullTextDesc: 'El texto legal completo en inglés está en el repositorio y en:',
  },
  en: {
    title: 'GNU Affero General Public License',
    version: 'Version 3 · 19 November 2007',
    project: 'PrismHub',
    desc: 'An open source cross-platform app for anime, manga, series and movies.',
    copyright: 'Copyright © 2026 Soul_Of_The_sun',
    permission:
      'This program is free software: you can redistribute it and/or modify it under the terms of the GNU AGPL v3 or later. It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY.',
    sections: [
      { title: 'Preamble', content: 'The GNU Affero General Public License is a copyleft license designed to guarantee cooperation with the community. Unlike permissive licenses, AGPL-3.0 ensures that any distributed modified version — even as a network service — shares its source code with users.' },
      { title: '0. Definitions', content: '"The License" refers to version 3 of the GNU AGPL. "The Program" is any work licensed under this License. "To modify" means to copy from or adapt the work. "A covered work" means either the unmodified Program or a work based on it.' },
      { title: '2. Basic permissions', content: 'You may run, copy and distribute copies of the Program. You may modify the Program and distribute modified versions, as long as this license\'s conditions are met.' },
      { title: '5. Conveying modified source versions', content: 'When you convey modified versions, you must state the changes made, keep this license in the distributed code, and publish the complete source code under the same terms.' },
      { title: '13. Remote network interaction (the AGPL clause)', content: 'If the Program interacts with users through a network, you must offer access to the source code. This is what sets AGPL-3.0 apart from the standard GPL — it ensures server-side versions stay open source too.' },
      { title: '15. Disclaimer of warranty', content: 'THERE IS NO WARRANTY FOR THE PROGRAM, TO THE EXTENT PERMITTED BY APPLICABLE LAW, INCLUDING ANY IMPLIED WARRANTY OF MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.' },
      { title: '16. Limitation of liability', content: 'IN NO EVENT WILL THE COPYRIGHT HOLDER BE LIABLE FOR GENERAL, SPECIAL, INCIDENTAL OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE THE PROGRAM.' },
    ],
    fullTextTitle: 'Full license text',
    fullTextDesc: 'The complete legal text in English is in the repository and at:',
  },
} as const;

export default function License() {
  const { lang } = useLang();
  const c = copy[lang];

  return (
    <Layout>
      <section className="px-5 py-16 md:px-10 md:py-24">
        <div className="mx-auto max-w-3xl">
          <motion.div initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.5 }} className="mb-10 text-center">
            <h1 className="mb-2 font-[family-name:var(--font-display)] text-2xl font-bold tracking-tight md:text-4xl">{c.title}</h1>
            <p className="text-sm" style={{ color: 'var(--text-faint)' }}>{c.version}</p>
            <div className="surface mt-4 rounded-2xl px-5 py-4 text-left">
              <p className="mb-1 text-sm font-semibold" style={{ color: 'var(--accent)' }}>{c.project}</p>
              <p className="text-xs leading-relaxed" style={{ color: 'var(--text-muted)' }}>
                {c.desc}
                <br />
                {c.copyright} (
                <a href="https://github.com/Litdemonick" target="_blank" rel="noopener noreferrer" className="underline" style={{ color: 'var(--accent)' }}>
                  github.com/Litdemonick
                </a>
                )
              </p>
              <p className="mt-3 text-xs leading-relaxed" style={{ color: 'var(--text-faint)' }}>{c.permission}</p>
            </div>
          </motion.div>

          <div className="flex flex-col gap-4">
            {c.sections.map((section, i) => (
              <motion.div
                key={section.title}
                initial={{ opacity: 0, y: 16 }}
                whileInView={{ opacity: 1, y: 0 }}
                viewport={{ once: true, margin: '-40px' }}
                transition={{ duration: 0.4, delay: Math.min(i * 0.04, 0.24) }}
                className="surface rounded-2xl px-6 py-5"
              >
                <h2 className="mb-3 text-base font-semibold">{section.title}</h2>
                <p className="text-xs leading-relaxed md:text-sm" style={{ color: 'var(--text-muted)' }}>{section.content}</p>
              </motion.div>
            ))}

            <motion.div
              initial={{ opacity: 0, y: 16 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true }}
              transition={{ duration: 0.4 }}
              className="surface rounded-2xl px-6 py-5"
            >
              <h2 className="mb-3 text-base font-semibold">{c.fullTextTitle}</h2>
              <p className="mb-3 text-xs leading-relaxed" style={{ color: 'var(--text-faint)' }}>{c.fullTextDesc}</p>
              <a
                href="https://www.gnu.org/licenses/agpl-3.0.html"
                target="_blank"
                rel="noopener noreferrer"
                className="text-sm underline"
                style={{ color: 'var(--accent)' }}
              >
                gnu.org/licenses/agpl-3.0.html →
              </a>
            </motion.div>
          </div>
        </div>
      </section>
    </Layout>
  );
}
