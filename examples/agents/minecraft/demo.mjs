/* demo.mjs — the whole Part III demonstration in one command.
 *
 * Starts the server, waits for it, starts the bot, and runs for a while so the
 * thing can be watched (or screenshotted) without three terminals. Assumes an
 * LPS server on :3060 — `./lps ide` from the repository root.
 *
 *   node demo.mjs [--program craft.lps] [--seconds 60]
 */
import { spawn } from 'node:child_process';
import { setTimeout as sleep } from 'node:timers/promises';

const arg = (n, d) => { const i = process.argv.indexOf('--' + n); return i > 0 ? process.argv[i + 1] : d; };
const seconds = Number(arg('seconds', 60));
const program = arg('program', 'safety.lps');

const children = [];
const start = (name, args) => {
  const c = spawn('node', args, { stdio: ['ignore', 'pipe', 'pipe'] });
  c.stdout.on('data', (d) => process.stdout.write(`[${name}] ${d}`));
  c.stderr.on('data', (d) => process.stderr.write(`[${name}!] ${d}`));
  children.push(c);
  return c;
};

/*  The LPS server is the one prerequisite this script cannot start itself, and
 *  a bot that finds nothing there exits a minute in. Ask first. */
const api = arg('api', 'http://localhost:3060/lpsapi');
try {
  await fetch(api, { method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ operation: 'compile', source: 'fluents f.', syntax: 'legacy' }) });
} catch {
  console.error(`no LPS server at ${api} — start one first:  (cd ../.. && ./lps ide)`);
  process.exit(1);
}

console.log('starting the world…');
start('world', ['world.mjs']);
await sleep(9000);

console.log(`starting the bot with ${program}…`);
start('bot', ['bot.mjs', '--program', program]);

//  The viewer is the visible half of the demo, and it starts a second or two
//  after the bot spawns. Saying where it is once it is actually there beats
//  printing a URL that is not yet listening.
(async () => {
  for (let i = 0; i < seconds; i++) {
    await sleep(1000);
    try {
      await fetch('http://localhost:3007/');
      console.log('watch it at http://localhost:3007');
      return;
    } catch { /* not up yet */ }
  }
})();

await sleep(seconds * 1000);
console.log('done — stopping');
for (const c of children) c.kill('SIGINT');
await sleep(1500);
process.exit(0);
