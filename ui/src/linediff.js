/* linediff.js — the lines an edit adds and removes (the assistant's "Show the
 * change"). No imports, so that tools/linediff_test.mjs runs it under node. */

/*  What an edit changes, as hunks of lines: `+` added, `-` removed, one line
 *  of context either side, each hunk with the line of the new text it starts
 *  at.
 *
 *  A line-by-line longest common subsequence rather than "the lines of the
 *  new text that do not occur in the old": a program repeats its lines
 *  (every constraint on an action begins with the same two), so a new
 *  constraint was shown as its one novel line, and "2 line(s) added" was said
 *  of an edit that added five. Programs are a few hundred lines, so the
 *  quadratic table is small; the common prefix and suffix are trimmed first,
 *  which leaves an assistant's edit a table of a few cells. */
export function lineHunks(a, b, context = 1) {
  let pre = 0;
  while (pre < a.length && pre < b.length && a[pre] === b[pre]) pre++;
  let suf = 0;
  while (suf < a.length - pre && suf < b.length - pre
         && a[a.length - 1 - suf] === b[b.length - 1 - suf]) suf++;
  const A = a.slice(pre, a.length - suf), B = b.slice(pre, b.length - suf);
  const n = A.length, m = B.length;
  const L = Array.from({ length: n + 1 }, () => new Uint32Array(m + 1));
  for (let i = n - 1; i >= 0; i--) {
    for (let j = m - 1; j >= 0; j--) {
      L[i][j] = A[i] === B[j] ? L[i + 1][j + 1] + 1 : Math.max(L[i + 1][j], L[i][j + 1]);
    }
  }
  //  The whole text as one sequence of operations, with each line's number in
  //  the new text (for `-`, the line it would have been before).
  const ops = [];
  for (let k = 0; k < pre; k++) ops.push({ op: ' ', text: a[k], line: k + 1 });
  let i = 0, j = 0;
  while (i < n || j < m) {
    if (i < n && j < m && A[i] === B[j]) { ops.push({ op: ' ', text: A[i], line: pre + j + 1 }); i++; j++; }
    else if (i < n && (j === m || L[i + 1][j] >= L[i][j + 1])) { ops.push({ op: '-', text: A[i], line: pre + j + 1 }); i++; }
    else { ops.push({ op: '+', text: B[j], line: pre + j + 1 }); j++; }
  }
  for (let k = 0; k < suf; k++) ops.push({ op: ' ', text: b[b.length - suf + k], line: b.length - suf + k + 1 });
  const hunks = [];
  let cur = null, lastChange = -Infinity;
  ops.forEach((o, k) => {
    if (o.op === ' ') return;
    if (!cur || k - lastChange > 2 * context + 1) {
      cur = { at: o.line, lines: [], from: Math.max(0, k - context), to: k };
      hunks.push(cur);
    }
    cur.to = k;
    lastChange = k;
  });
  for (const h of hunks) {
    const to = Math.min(ops.length - 1, h.to + context);
    h.lines = ops.slice(h.from, to + 1).map(({ op, text }) => ({ op, text }));
    delete h.from; delete h.to;
  }
  return hunks;
}
