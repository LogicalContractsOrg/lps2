/* doctor.mjs — why the viewer will not start, and what to do about it.
 *
 *   node doctor.mjs            (or: npm run doctor)
 *
 * The bot runs headless when `canvas` will not load, and says so in one line —
 * which is the right thing for a bot and the wrong thing for somebody trying to
 * get the picture working. This is the long version: what this machine is, what
 * the module is, why the two disagree, and the command that fixes it.
 *
 * `canvas` is not optional decoration for prismarine-viewer, even in browser
 * mode: `viewer/lib/atlas.js` builds the block-texture atlas server-side and
 * `viewer/lib/entities.js` draws nametags, both with node-canvas, and
 * `require('prismarine-viewer')` reaches them. So either canvas loads or there
 * is no viewer.
 */
import { execSync } from 'node:child_process';
import { statSync, readFileSync, existsSync } from 'node:fs';
import { createRequire } from 'node:module';
import os from 'node:os';

const require = createRequire(import.meta.url);
const say = (...a) => console.log(...a);
const run = (cmd) => { try { return execSync(cmd, { stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim(); } catch { return null; } };

say('node        ', process.version, process.arch, process.platform);
say('cpu         ', os.cpus()[0]?.model || '(unknown)');

/*  Rosetta: an x64 node on an Apple Silicon Mac. npm then installs x64
 *  prebuilds, which is correct for that node — but if the node you *run* the
 *  demo with is the arm64 one, the two disagree and dlopen says exactly what
 *  the user saw: "slice is not valid mach-o file". */
if (process.platform === 'darwin') {
  const translated = run('sysctl -n sysctl.proc_translated');
  const apple = /Apple/.test(os.cpus()[0]?.model || '');
  if (translated === '1') say('rosetta      yes — this node is x64 running under Rosetta');
  else if (apple && process.arch === 'x64') say('rosetta      probably: Apple Silicon CPU, x64 node');
  else say('rosetta      no');
}

const NATIVE = 'node_modules/canvas/build/Release/canvas.node';
let magicKind = null;
if (existsSync(NATIVE)) {
  const { size } = statSync(NATIVE);
  say('canvas.node ', `${size} bytes`);
  //  A "prebuild" that is actually an error page is a classic, and it fails
  //  with the same dlopen message as a real architecture mismatch.
  const head = readFileSync(NATIVE, { length: 4 });
  const magic = [...head.subarray(0, 4)].map((b) => b.toString(16).padStart(2, '0')).join('');
  magicKind = { '7f454c46': 'ELF (Linux)', 'cffaedfe': 'mach-o 64 (arm64 or x64)',
    'cafebabe': 'mach-o universal', 'feedfacf': 'mach-o 64 (big-endian)',
    '4d5a9000': 'PE (Windows)' }[magic] || null;
  say('            ', magicKind ? `${magicKind}, magic ${magic}` : `magic ${magic} — not a native module at all`);
  if (size < 100000) say('             ^ suspiciously small: a truncated or failed download');
  const archs = run(`lipo -archs ${NATIVE}`);
  if (archs) say('architecture', archs, `(this node wants ${process.arch === 'x64' ? 'x86_64' : 'arm64'})`);
} else {
  say('canvas.node  not present');
}

/*  The other way to see nothing at :3007, and the one that looks least like a
 *  fault: canvas is fine, the viewer would start, but the bot never spawns
 *  because its saved position is outside the world, so nothing gets that far.
 *  See playerdata.mjs. */
const { savedPlayers, describe } = await import('./playerdata.mjs');
const players = await savedPlayers('world');
const stale = players.filter((p) => !p.ok);
say('saved players', players.length ? `${players.length} in world/playerdata` : 'none');
for (const p of stale) say('             ', describe(p));
if (stale.length) {
  say('');
  say('A player saved outside the world never spawns again: mineflayer waits for');
  say('the chunk it is standing in and there is no chunk down there. The bot sits');
  say('connected and silent, and the viewer never starts. Throw them away:');
  say('  npm run reset');
  say('(the terrain is kept; only the saved players go)');
}

let ok = false, err = null;
try { require('canvas'); ok = true; } catch (e) { err = e; }

say('');
if (ok) {
  say('canvas loads, so the viewer will start — provided the bot spawns at all.');
  if (stale.length) say('It will not, until `npm run reset` (above).');
  say('  node demo.mjs --program safety.lps --seconds 60');
  say('  then open http://localhost:3007');
  process.exit(stale.length ? 1 : 0);
}

const m = String(err.message);
say('canvas does NOT load:');
say('  ' + m.split('\n')[0]);
say('');

const brew = 'brew install pkg-config cairo pango libpng jpeg giflib librsvg';
const rebuild = 'npm rebuild canvas --build-from-source';

if (/Cannot find module/.test(m)) {
  say('It is not installed. From this directory:');
  say('  npm install');
} else if (/mach-o|slice is not valid|wrong architecture|incompatible architecture/i.test(m)
           && /ELF|PE /.test(magicKind || '')) {
  /*  macOS says "slice is not valid mach-o file" for a binary from another
      *operating system* too, so the message alone cannot tell the two apart —
      the magic bytes can, and the remedies are different. */
  say(`That is a ${magicKind} binary on ${process.platform}: this node_modules was`);
  say('built somewhere else and copied here. Delete it and install again:');
  say('  rm -rf node_modules package-lock.json && npm install');
} else if (/mach-o|slice is not valid|wrong architecture|incompatible architecture/i.test(m)) {
  say('It is installed but built for a different architecture than this node.');
  say('That is npm having fetched an x64 prebuild for an arm64 node or the other');
  say('way round — most often because two nodes are installed and the one that');
  say('did the install is not the one running the demo.');
  say('');
  say('Build it here instead of downloading one, which cannot get the architecture');
  say('wrong:');
  say('  ' + brew);
  say('  ' + rebuild);
  say('');
  say('If that still disagrees, check you are using one node:');
  say('  which -a node && node -p process.arch');
} else if (/invalid ELF header|not a mach-o|is not a valid Win32/i.test(m)) {
  say('That module was built for another *operating system* — a node_modules');
  say('copied between machines, most likely. Delete it and install again here:');
  say('  rm -rf node_modules package-lock.json && npm install');
} else if (/file too short|not a mach-o file|bad magic|premature end/i.test(m)) {
  say('That file is not a native module at all — a failed download saved under');
  say('its name, which is what "file too short" means. Fetch it again:');
  say('  rm -rf node_modules/canvas && npm install');
  say('or build it here, which does not depend on the download:');
  say('  ' + brew);
  say('  ' + rebuild);
} else if (/Library not loaded|image not found|libcairo|libpango/i.test(m)) {
  say('The module loaded but its own libraries are missing:');
  say('  ' + brew + '        # macOS');
  say('  sudo apt install libcairo2 libpango-1.0-0 libjpeg-dev libgif-dev   # Debian');
} else {
  say('Unrecognised failure. The two things worth trying, in order:');
  say('  ' + brew);
  say('  ' + rebuild);
}

say('');
say('None of this stops the demo: without a viewer the bot runs headless, which');
say('exercises every part of the LPS side. Pass --no-viewer to stop it trying.');
process.exit(1);
