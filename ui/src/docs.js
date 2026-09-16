/* docs.js — the Help menu's target.
 *
 * The container already carries docs/, and LE2's editor serves its own
 * reference the same way (/docs/user/reference/language). This renders one of ours from
 * markdown, so "Language reference" is a link rather than an instruction to go
 * and find a file.
 */
import { marked } from 'marked';

const params = new URLSearchParams(location.search);
const name = String(window.LPS_DOC || params.get('doc') || 'user/reference/lps')
  .replace(/[^A-Za-z0-9_./-]/g, '').replace(/\.\.+/g, '.');

marked.setOptions({ gfm: true, breaks: false });

const root = document.getElementById('doc');

/*  The anchors addHeadingIds gives, for the search's links too. */
const slug = (text) => text.toLowerCase().replace(/[^\w\s-]/g, '').replace(/\s/g, '-');

if (name === 'search') {
  //  /docs/search?q=…: the documentation's full-text search (docs-extras.js).
  document.getElementById('docsearch')?.remove();
  window.DocsExtras.renderSearchPage(root, {
    self: 'lps2', navUrl: '/docs/user/nav.json', searchUrl: '/docs/search', slug,
    rawUrl: (p) => `/docs-raw/user/${p}.md`, docUrl: (p) => `/docs/user/${p}` });
} else fetch(`/docs-raw/${name}.md`)
  .then((r) => { if (!r.ok) throw new Error(`no such document: ${name}`); return r.text(); })
  .then((md) => {
    document.title = (/^#\s+(.+)$/m.exec(md)?.[1] || name) + ' — LPS2';
    root.innerHTML = marked.parse(md);
    addHeadingIds(root);
    //  Links between documents keep working: `../guide/ide.md#x`, relative to
    //  this document, opens /docs/user/guide/ide#x, rendered.
    for (const a of root.querySelectorAll('a[href]')) {
      const href = a.getAttribute('href');
      if (/^[a-z]+:/i.test(href) || href.startsWith('#')) continue;
      const url = new URL(href, location.href);
      if (url.origin === location.origin && url.pathname.endsWith('.md')) {
        //  Developer and project documents are not served: read them on GitHub.
        a.setAttribute('href', url.pathname.startsWith('/docs/user/')
          ? url.pathname.slice(0, -3) + url.hash
          : `https://github.com/mcalejo/lps2/blob/main${url.pathname}${url.hash}`);
      }
    }
    //  Links to LE2's documents go to where it is; diagrams are drawn.
    window.DocsExtras?.rewritePeerLinks(root, 'lps2');
    return window.DocsExtras?.renderMermaid(root, 'lps2', { mermaidSrc: '/mermaid.min.js',
      dark: document.body.dataset.theme !== 'light' });
  })
  .then(() => {
    if (location.hash) scrollToHash();
    window.addEventListener('hashchange', scrollToHash);
  })
  .catch((e) => { root.textContent = e.message; });

/*  Every heading gets the id GitHub would give it.
 *
 *  marked stopped generating them, and nothing here noticed: every table of
 *  contents in every document, and the `?` beside each pane in the editor —
 *  which links to `/docs/user/guide/ide#timeline` and its neighbours — pointed at
 *  elements that did not exist. The rule is GitHub's, because the documents are
 *  also read on GitHub and there must be one set of anchors: lower-case, drop
 *  anything that is not a letter, digit, space, hyphen or underscore, then turn
 *  each space into a hyphen. Runs of hyphens are kept, and so is a trailing one
 *  ("How do I …" is `how-do-i-`). A repeated heading gets `-1`, `-2`, … */
function addHeadingIds(el) {
  const seen = new Map();
  for (const h of el.querySelectorAll('h1, h2, h3, h4, h5, h6')) {
    const base = slug(h.textContent);
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
