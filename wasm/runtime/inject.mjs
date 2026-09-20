/* inject.mjs — put the runtime's script tags into the pages that need them.
 *
 * A page of the IDE is written against a server, and what makes it work
 * without one is boot.js replacing `fetch` before the page's own scripts run.
 * That means a *classic* script tag in <head>: the IDE's bundle is a module
 * script and therefore deferred, so a plain one ahead of it has finished
 * before it starts, and nothing else can take a reference to the original
 * fetch first.
 *
 * Which pages: the IDE and the live view. Not the landing page and not the
 * documentation — they are static text, and booting a 3 MB engine to read
 * them would be a cost with nothing on the other side of it.
 *
 * Usage: node inject.mjs <dist-dir>
 */
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';

const dist = process.argv[2];
if (!dist) { console.error('usage: node inject.mjs <dist-dir>'); process.exit(2); }

const PAGES = ['ide.html', 'live-view.html'];
/*  No <link rel=preload> for the runtime and the payload, though they are the
 *  page's critical path and it is the obvious thing to reach for. A preload
 *  is the *document's* fetch, and these two are fetched by the worker, which
 *  is a different context: Chromium downloads them twice and then warns that
 *  the preload went unused. Starting the worker from <head> — which boot.js
 *  does, rather than waiting for DOMContentLoaded — buys the same overlap
 *  honestly. */
const TAGS = [
    '<script src="/lps-wasm/config.js"></script>',
    '<script src="/lps-wasm/boot.js"></script>'
].join('\n') + '\n';

let touched = 0;
for (const name of PAGES) {
    const file = join(dist, name);
    if (!existsSync(file)) continue;
    let html = readFileSync(file, 'utf8');
    if (html.includes('/lps-wasm/boot.js')) continue;
    const head = html.search(/<head[^>]*>/i);
    if (head >= 0) {
        const at = html.indexOf('>', head) + 1;
        html = html.slice(0, at) + '\n' + TAGS + html.slice(at);
    } else {
        html = TAGS + html;
    }
    writeFileSync(file, html);
    touched++;
}
console.log(`  runtime injected into ${touched} pages`);
