/* linediff_test.mjs — ui/src/linediff.js, the hunks the assistant's "Show the
 * change" lists.   node tools/linediff_test.mjs */
import assert from 'node:assert/strict';
import { lineHunks } from '../ui/src/linediff.js';

const flat = (hs) => hs.map((h) => [h.at, h.lines.map((l) => l.op + l.text)]);

//  A new constraint whose first two lines repeat the one above it: all of it
//  is added, not only its one novel line (the set difference said "1 added").
const before = ['% create', 'it must not be true that', '    a party creates an iou', '    and the party is not the issuer.', '', 'when a party creates an iou', 'then it is.'];
const after = ['% create', 'it must not be true that', '    a party creates an iou', '    and the party is not the issuer.', '',
  'it must not be true that', '    a party creates an iou', '    and the amount > 500.', '', 'when a party creates an iou', 'then it is.'];
const h = lineHunks(before, after);
assert.equal(h.length, 1);
const added = h[0].lines.filter((l) => l.op === '+').map((l) => l.text);
assert.equal(added.length, 4);
assert.ok(added.includes('    and the amount > 500.'));
assert.equal(added.filter((l) => l === 'it must not be true that').length, 1);
assert.equal(h[0].lines.filter((l) => l.op === '-').length, 0);

//  Two separate edits are two hunks, each at its line of the new text, with
//  one line of context.
const h2 = lineHunks(['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'], ['a', 'B', 'c', 'd', 'e', 'f', 'g', 'h', 'i']);
assert.deepEqual(flat(h2), [[2, [' a', '-b', '+B', ' c']], [9, [' h', '+i']]]);

//  Nothing changed, nothing listed; a removal is a `-`.
assert.deepEqual(lineHunks(['x', 'y'], ['x', 'y']), []);
assert.deepEqual(flat(lineHunks(['x', 'y', 'z'], ['x', 'z'])), [[2, [' x', '-y', ' z']]]);
console.log('linediff: ok');
