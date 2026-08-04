/* docs.js — the Help menu's target.
 *
 * The container already carries docs/, and LE2's editor serves its own
 * reference the same way (/docs/le_summary). This renders one of ours from
 * markdown, so "Language reference" is a link rather than an instruction to go
 * and find a file.
 */
import { marked } from 'marked';

const params = new URLSearchParams(location.search);
const name = String(window.LPS_DOC || params.get('doc') || 'lps_summary')
  .replace(/[^A-Za-z0-9_.-]/g, '');

marked.setOptions({ gfm: true, breaks: false });

const root = document.getElementById('doc');

fetch(`/docs-raw/${name}.md`)
  .then((r) => { if (!r.ok) throw new Error(`no such document: ${name}`); return r.text(); })
  .then((md) => {
    document.title = (/^#\s+(.+)$/m.exec(md)?.[1] || name) + ' — LPS(2)';
    root.innerHTML = marked.parse(md);
    //  Links between documents keep working: docs/foo.md → /docs/foo
    for (const a of root.querySelectorAll('a[href$=".md"]')) {
      a.setAttribute('href', '/docs/' + a.getAttribute('href').replace(/\.md$/, '').replace(/^\.\//, ''));
    }
    if (location.hash) document.querySelector(location.hash)?.scrollIntoView();
  })
  .catch((e) => { root.textContent = e.message; });
