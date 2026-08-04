/* world.mjs — a Minecraft server, so the demo needs no account and no client.
 *
 * flying-squid is a Minecraft server in JavaScript. It is not the real game and
 * does not pretend to be: no world generation worth the name, no mob AI, no
 * survival mechanics. What it is, is a server the bot can connect to in offline
 * mode, on this machine, with a flat world and whatever entities we spawn — and
 * that is enough to watch an LPS agent decide things.
 *
 *   node world.mjs                 # then, in another shell, node bot.mjs
 *
 * Against a real server instead, run `node bot.mjs --host … --port …`; the bot
 * does not care which it is talking to.
 */
import { createMCServer } from 'flying-squid';

const port = Number(process.env.PORT || 25565);

createMCServer({
  motd: 'LPS(2) test world',
  port,
  'max-players': 10,
  'online-mode': false,
  logging: true,
  gameMode: 0,
  difficulty: 1,
  worldFolder: 'world',
  generation: { name: 'diamond_square', options: { worldHeight: 80 } },
  kickTimeout: 10000,
  plugins: {},
  modpe: false,
  'view-distance': 6,
  'player-list-text': { header: 'LPS(2)', footer: 'test world' },
  version: '1.18.2',
});

console.log(`flying-squid on :${port} — offline mode, no account needed`);
