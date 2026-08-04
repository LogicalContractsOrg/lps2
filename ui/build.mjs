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
import { rmSync, mkdirSync, cpSync, writeFileSync } from 'node:fs';
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

const worker = {
  ...common,
  entryPoints: { 'editor.worker': join(here, 'node_modules', 'monaco-editor', 'esm', 'vs', 'editor', 'editor.worker.start.js') },
  outdir,
  format: 'iife',
};

function copyStatic() {
  cpSync(join(here, 'static'), outdir, { recursive: true });
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
