/* build.mjs — bundle the IDE into src/ide/dist/.
 *
 * The engine has no build step and never will: it is SWI-Prolog and nothing
 * else. The *IDE* does, since M14, because Monaco, Konva and three.js are not
 * things you paste into a page. The output is plain files under
 * src/ide/dist/, served by the same Prolog endpoint as everything else, so a
 * deployment still runs one process and needs no Node at run time.
 *
 *   npm --prefix ui install
 *   npm --prefix ui run build      (or `watch` while developing)
 */
import * as esbuild from 'esbuild';
import { rmSync, mkdirSync, copyFileSync, readdirSync, statSync, writeFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const outdir = join(here, '..', 'src', 'ide', 'dist');
const watch = process.argv.includes('--watch');

rmSync(outdir, { recursive: true, force: true });
mkdirSync(outdir, { recursive: true });

/* The Monarch grammar's keyword lists are generated from src/core/lps_ops.pl,
 * so the editor cannot drift from the parser. Regenerating is part of the
 * build rather than a thing to remember. */
try {
  execFileSync(join(here, '..', 'myswipl.sh'),
    ['-q', '-g', "consult('tools/gen_monarch.pl')", '-g', 'gen_monarch:main', '-t', 'halt'],
    { cwd: join(here, '..'), stdio: 'inherit' });
} catch (e) {
  console.error('could not regenerate the Monarch keyword lists — using the checked-in copy');
}

const common = {
  bundle: true,
  minify: !watch,
  sourcemap: watch,
  logLevel: 'info',
  loader: {
    '.ttf': 'file', '.woff': 'file', '.woff2': 'file',
    '.svg': 'dataurl', '.png': 'dataurl',
  },
  define: { 'process.env.NODE_ENV': '"production"' },
};

const app = {
  ...common,
  entryPoints: { app: join(here, 'src', 'main.js'), docs: join(here, 'src', 'docs.js'),
                 'live-view': join(here, 'src', 'live-view.js') },
  outdir,
  format: 'esm',
  splitting: true,
  chunkNames: 'chunks/[name]-[hash]',
};

/*  `editor.worker.js`, not `editor.worker.start.js`: the second only *exports*
 *  a `start` function, so a bundle of it is a worker that loads, says nothing
 *  and answers nothing — which is what the IDE shipped with. The editor then
 *  waits for ever on a worker that is there, and every feature computed in it
 *  (links, word suggestions, diffs) silently does nothing. The first is the
 *  entry point that installs the message handler and starts it. */
const worker = {
  ...common,
  entryPoints: { 'editor.worker': join(here, 'node_modules', 'monaco-editor', 'esm', 'vs', 'editor', 'editor.worker.js') },
  outdir,
  format: 'iife',
};

/*  Not cpSync: on a virtiofs mount (a container over a macOS folder) Node's
 *  cpSync has left a zero-length, mode-000 file that nothing could then stat,
 *  remove or overwrite. copyFileSync takes the ordinary path and is fine. */
function copyTree(src, dst) {
  mkdirSync(dst, { recursive: true });
  for (const name of readdirSync(src)) {
    const s = join(src, name), d = join(dst, name);
    if (statSync(s).isDirectory()) copyTree(s, d); else copyFileSync(s, d);
  }
}

function copyStatic() {
  copyTree(join(here, 'static'), outdir);
  writeFileSync(join(outdir, 'BUILD.txt'), new Date().toISOString() + '\n');
}

if (watch) {
  const c1 = await esbuild.context(app);
  const c2 = await esbuild.context(worker);
  await c1.watch(); await c2.watch();
  copyStatic();
  console.log('watching; ^C to stop');
} else {
  await esbuild.build(app);
  await esbuild.build(worker);
  copyStatic();
  console.log('built into src/ide/dist/');
}
