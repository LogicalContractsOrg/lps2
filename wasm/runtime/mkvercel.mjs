/* mkvercel.mjs — the host's half of the routing.
 *
 * Almost nothing: a static site is mostly files at the paths they are already
 * at. What is left is the addresses the SWI-Prolog server answered with
 * something other than a file of the same name:
 *
 *   /ide                 the editor, whose index.html cannot be *this* site's
 *                        index.html — that is the landing page — so it is
 *                        ide.html with a rewrite. Its own assets are relative
 *                        (`./app.js`), and resolve to the site root either way
 *   /assets/<file>       the IDE asks for its files under this prefix as well
 *                        as flat; the server served one directory for both
 *   /swipl/<file>        where a "Deploy as WASM" page looks for the
 *                        SWI-Prolog runtime — the same three files this build
 *                        already carries, rather than a second copy of them
 *   /docs/<name>         a document by name, without the .md: one shell page
 *                        per document, written by build.sh from the server's
 *                        own rendering, so the Help menu's links keep working
 *   /docs-raw/<path>     the Markdown and its pictures, which the shell fetches
 *
 * Caching: everything under /lps-wasm/ changes only when the build does, and
 * it is 3 MB of it, so it is immutable for a year — with the payload and the
 * pages deliberately not, since a redeploy has to be able to change them.
 *
 * Usage: node mkvercel.mjs <dist-dir>
 */
import { writeFileSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

const dist = process.argv[2];
if (!dist) { console.error('usage: node mkvercel.mjs <dist-dir>'); process.exit(2); }

/*  A document's old address. The server answers those with a 301
 *  (`doc_moved/2`), and a link in a year-old paper is exactly the kind of
 *  thing that has to keep working; build.sh asks the Prolog for the list, so
 *  this file does not carry a second copy of it that could go stale. */
let redirects = [];
try {
    redirects = readFileSync(join(dist, '.doc-redirects'), 'utf8').split('\n')
        .map((line) => line.trim().split(/\s+/))
        .filter((pair) => pair.length === 2 && pair[0])
        .map(([from, to]) => ({ source: `/docs/${from}`, destination: `/docs/${to}`, permanent: true }));
} catch { /* no list: the build was made without one */ }

const config = {
    $schema: 'https://openapi.vercel.sh/vercel.json',
    cleanUrls: false,
    trailingSlash: false,
    headers: [
        {
            source: '/lps-wasm/swipl/(.*)',
            headers: [{ key: 'Cache-Control', value: 'public, max-age=31536000, immutable' }]
        },
        {
            source: '/lps-wasm/payload.bin',
            headers: [
                { key: 'Cache-Control', value: 'public, max-age=300, must-revalidate' },
                { key: 'Content-Type', value: 'application/octet-stream' }
            ]
        }
    ],
    redirects,
    rewrites: [
        { source: '/ide', destination: '/ide.html' },
        { source: '/ide/', destination: '/ide.html' },
        { source: '/assets/:path*', destination: '/:path*' },
        { source: '/swipl/:path*', destination: '/lps-wasm/swipl/:path*' },
        { source: '/docs', destination: '/docs/user/reference/lps.html' },
        { source: '/docs/', destination: '/docs/user/reference/lps.html' },
        { source: '/docs/:path*', destination: '/docs/:path*.html' }
    ]
};

writeFileSync(join(dist, 'vercel.json'), JSON.stringify(config, null, 4) + '\n');
console.log(`  vercel.json: ${config.rewrites.length} rewrites, ${config.redirects.length} redirects`);

writeFileSync(join(dist, 'STATIC-HOSTS.md'), `# Serving this directory somewhere other than Vercel

Everything here is a file, and the addresses that are not files are listed in
\`vercel.json\`. On another host, do the same:

| Address | Serve |
|---------|-------|
| \`/ide\` | \`/ide.html\` |
| \`/assets/<file>\` | \`/<file>\` |
| \`/swipl/<file>\` | \`/lps-wasm/swipl/<file>\` |
| \`/docs/<name>\` | \`/docs/<name>.html\` |

\`redirects\` are the old addresses of documents that have moved: a 301 each,
generated from the server's own \`doc_moved/2\`.

Without any of them the site still works — the IDE is at \`/ide.html\` and the
documents at their own \`.html\` — so a plain \`python3 -m http.server\` in this
directory is a fair way to try it.

The one thing a host must not do is strip or re-encode
\`/lps-wasm/payload.bin\`: it is gzip, and the worker un-gzips it itself when
the host has not.
`);
