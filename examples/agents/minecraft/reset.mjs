/* reset.mjs — throw away saved players so the next run can spawn.
 *
 *   node reset.mjs           (or: npm run reset)
 *
 * The terrain is kept — it is what makes the second start fast, and it is never
 * the thing that is broken. Only `world/playerdata` goes.
 */
import { readdirSync, unlinkSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { savedPlayers, describe } from './playerdata.mjs';

const dir = join('world', 'playerdata');
if (!existsSync(dir)) {
  console.log('nothing to reset — no world/playerdata (the world has never been played in)');
  process.exit(0);
}

for (const p of await savedPlayers('world')) {
  console.log(p.ok ? `  ${p.file} at y=${Math.round(p.y)} — was fine` : `  ${describe(p)}`);
}

const files = readdirSync(dir).filter((f) => f.endsWith('.dat'));
for (const f of files) unlinkSync(join(dir, f));
console.log(`removed ${files.length} saved player${files.length === 1 ? '' : 's'}; `
  + 'the terrain is untouched');
