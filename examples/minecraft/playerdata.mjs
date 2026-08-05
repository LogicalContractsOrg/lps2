/* playerdata.mjs — the saved player, and when to throw it away.
 *
 * flying-squid persists each player's position into `world/playerdata/<uuid>.dat`
 * and restores it on the next connection. That is right for a server and wrong
 * for a demo, because one bad run poisons every later one: a bot that fell out
 * of the world is saved at y = -13826, is put back there when it reconnects, and
 * mineflayer then never emits `spawn` — there is no chunk at that height to
 * spawn into. The bot sits connected and silent for ever, the viewer never
 * starts, and nothing says why.
 *
 * So: before the server comes up, any saved player outside the world's own
 * height range is deleted. They respawn at the spawn point, which is the only
 * position that is certainly inside a chunk.
 *
 * Vanilla worlds are [minY, minY + height) = [-64, 320) since 1.18; the margin
 * below is deliberately generous, because the failure this guards against is off
 * by thousands of blocks, not by one.
 */
import { readdirSync, readFileSync, unlinkSync, existsSync } from 'node:fs';
import { join } from 'node:path';

export const WORLD_FLOOR = -64;
export const WORLD_CEILING = 320;

/*  Every player the world has saved, with the position it would be restored to.
 *
 *  Two ways a record is unusable, and the one that broke this demo was both at
 *  once: a position outside the world, and no `Health` — a partial save written
 *  as the server was going down. A file that cannot be parsed counts as bad
 *  too; unreadable player state fails the same way as impossible player state. */
export async function savedPlayers(worldFolder = 'world') {
  const dir = join(worldFolder, 'playerdata');
  if (!existsSync(dir)) return [];
  const nbt = await import('prismarine-nbt');
  const out = [];
  for (const file of readdirSync(dir).filter((f) => f.endsWith('.dat'))) {
    const path = join(dir, file);
    try {
      const { parsed } = await nbt.parse(readFileSync(path));
      const { Pos: pos, Health: health } = nbt.simplify(parsed);
      const y = Array.isArray(pos) ? pos[1] : null;
      const inWorld = typeof y === 'number' && y > WORLD_FLOOR && y < WORLD_CEILING;
      const alive = typeof health === 'number' && health > 0;
      out.push({ file, path, pos, y, health, inWorld, alive, ok: inWorld && alive });
    } catch (e) {
      out.push({ file, path, pos: null, y: null, ok: false, error: e.message });
    }
  }
  return out;
}

/*  Delete the ones that would not spawn. Returns what was deleted, so the caller
 *  can say so — a silent repair of a fault that presented as silence is not an
 *  improvement. */
export async function resetStalePlayers(worldFolder = 'world') {
  const bad = (await savedPlayers(worldFolder)).filter((p) => !p.ok);
  for (const p of bad) unlinkSync(p.path);
  return bad;
}

export function describe(p) {
  if (!p.pos) return `${p.file} — unreadable (${p.error})`;
  const why = [!p.inWorld && `y=${Math.round(p.y)}, outside the world`,
    !p.alive && `Health ${p.health === undefined ? 'missing' : p.health}`].filter(Boolean);
  return `${p.file} — ${why.join(', ')}`;
}
