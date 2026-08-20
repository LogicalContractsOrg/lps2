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
    document.title = (/^#\s+(.+)$/m.exec(md)?.[1] || name) + ' — LPS2';
    root.innerHTML = marked.parse(md);
    addHeadingIds(root);
    //  Links between documents keep working: docs/foo.md → /docs/foo
    for (const a of root.querySelectorAll('a[href$=".md"]')) {
      a.setAttribute('href', '/docs/' + a.getAttribute('href').replace(/\.md$/, '').replace(/^\.\//, ''));
    }
    if (location.hash) scrollToHash();
    window.addEventListener('hashchange', scrollToHash);
  })
  .catch((e) => { root.textContent = e.message; });

/*  Every heading gets the id GitHub would give it.
 *
 *  marked stopped generating them, and nothing here noticed: every table of
 *  contents in every document, and the `?` beside each pane in the editor —
 *  which links to `/docs/UsingTheIDE#timeline` and its neighbours — pointed at
 *  elements that did not exist. The rule is GitHub's, because the documents are
 *  also read on GitHub and there must be one set of anchors: lower-case, drop
 *  anything that is not a letter, digit, space, hyphen or underscore, then turn
 *  each space into a hyphen. Runs of hyphens are kept, and so is a trailing one
 *  ("How do I …" is `how-do-i-`). A repeated heading gets `-1`, `-2`, … */
function addHeadingIds(el) {
  const seen = new Map();
  for (const h of el.querySelectorAll('h1, h2, h3, h4, h5, h6')) {
    const base = h.textContent.toLowerCase()
      .replace(/[^\w\s-]/g, '')
      .replace(/\s/g, '-');
    const n = seen.get(base) || 0;
    seen.set(base, n + 1);
    h.id = n ? `${base}-${n}` : base;
  }
}

/*  `scrollIntoView` on a bare `location.hash` throws for an id that starts with
 *  a digit — `#1-getting-it-running` is not a valid CSS selector — which is
 *  most of the section links in the tutorial and the tour. */
function scrollToHash() {
  const id = decodeURIComponent(location.hash.slice(1));
  if (id) document.getElementById(id)?.scrollIntoView();
}
