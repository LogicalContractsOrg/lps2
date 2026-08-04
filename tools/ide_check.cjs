/* ide_check.cjs — drive the IDE in a real browser and photograph it.
 *
 * §I.10 asks for an IDE; a page that has never been rendered is not one. This
 * walks the panes with Playwright, captures a screenshot of each, and — more
 * usefully than the pictures — fails loudly on any console error, page error
 * or failed request, so that a pane which silently renders nothing is caught
 * rather than admired.
 *
 *   ./lps ide --port 3060 &
 *   NODE_PATH=/usr/lib/node_modules node tools/ide_check.cjs [outdir] [port]
 */
const { chromium } = require('playwright');
const fs = require('fs');

const outdir = process.argv[2] || 'build/ide-shots';
const port = process.argv[3] || '3060';
const base = `http://localhost:${port}/`;
//  `/` is the start page now; the editor is at /ide.
const ide = `${base}ide`;

fs.mkdirSync(outdir, { recursive: true });

const problems = [];
/*  A corpus program is allowed to be wrong about the world. `badlight.pl` names
    a clipart URL on a host that may be unreachable, and that is a fact about
    the program, not a defect in the IDE — so a failure whose URL is not ours is
    a note rather than a problem. */
const notes = [];
const ours = (s) => !/https?:\/\/(?!localhost)/.test(String(s))
  //  Chromium logs the same failure twice: once with the URL, once as a bare
  //  "Failed to load resource". The second carries no URL to judge it by, and
  //  the first is already classified.
  && !/^Failed to load resource/.test(String(s));
let shots = 0;

async function shot(page, name, note) {
  const file = `${outdir}/${name}.png`;
  await page.screenshot({ path: file, fullPage: false });
  shots++;
  console.log(`  ${name}.png ${note || ''}`);
}

const wait = (ms) => new Promise((r) => setTimeout(r, ms));

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1500, height: 940 } });

  page.on('console', (m) => {
    if (m.type() === 'error') (ours(m.text()) ? problems : notes).push(`console: ${m.text()}`);
  });
  page.on('pageerror', (e) => problems.push(`pageerror: ${e.message}`));
  page.on('requestfailed', (r) => (ours(r.url()) ? problems : notes).push(`request failed: ${r.url()}`));
  page.on('response', (r) => {
    if (r.status() >= 400) problems.push(`HTTP ${r.status()}: ${r.url()}`);
  });

  console.log(`driving ${base}`);
  await page.goto(ide, { waitUntil: 'networkidle' });
  await page.waitForSelector('.monaco-editor', { timeout: 20000 });
  await wait(2500);                                  // the 1500 ms analysis debounce
  await shot(page, '01-editor', '(Monaco, LPS syntax, declarative goat)');

  const text = await page.evaluate(() => document.querySelector('#editor')?.innerText || '');
  if (!/achieve|lps_engine/.test(text)) problems.push('the editor did not load the example');

  //  Menus
  await page.click('#menubar .menu:has-text("Misc")');
  await wait(300);
  await shot(page, '02-menu', '(Misc menu: themes, fonts, keys, WASM)');
  await page.keyboard.press('Escape');
  await page.click('body', { position: { x: 700, y: 500 } });

  //  Run
  await page.click('#run');
  await page.waitForFunction(() => /cycles|error/.test(document.getElementById('status').textContent), { timeout: 60000 });
  await wait(1200);
  const status = await page.textContent('#status');
  console.log(`  status: ${status}`);
  if (/error/.test(status)) problems.push(`run failed: ${status}`);
  await shot(page, '03-timeline', '(§I.10.2)');

  const lanes = await page.locator('#pane-timeline svg rect.hold').count();
  if (!lanes) problems.push('timeline drew no intervals');

  //  Panes
  for (const [pane, name, check] of [
    ['changes', '04-changes', '#pane-changes table tr, #pane-changes .empty'],
    ['automaton', '05-automaton', '#pane-automaton svg .state'],
    ['scene', '06-scene2d', '#pane-scene canvas, #pane-scene .empty'],
    ['internal', '07-internal', '#pane-internal pre'],
  ]) {
    await page.click(`#tabs button[data-pane="${pane}"]`);
    await wait(1400);
    await shot(page, name, `(${pane})`);
    const n = await page.locator(check).count();
    if (!n) problems.push(`${pane} pane drew nothing (${check})`);
  }

  /*  Explanations. There is no explain pane any more — the question is asked
   *  where the thing is, by right-clicking it — so drive the modal the way a
   *  reader would, from the timeline. */
  await page.click('#tabs button[data-pane="timeline"]');
  await wait(1200);
  const askable = page.locator('#pane-timeline .askable').first();
  if (await askable.count()) {
    await askable.click({ button: 'right' });
    await wait(1600);
    await shot(page, '08-explain', '(§I.10.5, from a right-click)');
    if (!(await page.locator('#dialog .explanation .node').count())) problems.push('the why modal drew no tree');
    await page.click('#dialog-close');
  } else {
    problems.push('the timeline offered nothing to ask about');
  }

  //  A program with a visual mapping, and the 2D pane
  await page.evaluate(async () => {
    const r = await fetch('/lpsapi', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ operation: 'example', name: 'badlight' }),
    }).then((x) => x.json());
    window.LPS.load(r.source, 'badlight.pl');
  });
  await wait(2600);
  await page.click('#run');
  await page.waitForFunction(() => /cycles|error/.test(document.getElementById('status').textContent), { timeout: 60000 });
  await page.click('#tabs button[data-pane="scene"]');
  await wait(1800);
  await page.fill('#cycle-slider', '4');
  await page.dispatchEvent('#cycle-slider', 'input');
  await wait(1800);
  await shot(page, '09-scene2d-badlight', '(Konva, bottom-left origin)');
  if (!(await page.locator('#pane-scene canvas').count())) problems.push('2D pane drew no canvas');

  //  A syntax error must squiggle, and must never read as "no problems"
  await page.evaluate(() => {
    window.LPS.state.editor.setValue('maxTime(3).\nfluents f(_).\nif f(X) at T then\n');
  });
  await wait(2600);
  await shot(page, '10-diagnostics', '(a program that does not parse)');
  //  The problem strip is gone: diagnostics are markers in the text and a
  //  count in the top bar. Both have to say something went wrong.
  const probs = await page.textContent('#status');
  if (/no problems|ready/.test(probs)) problems.push('a program that does not parse reported "' + probs + '"');
  const markers = await page.evaluate(() => window.LPS.monaco.editor
    .getModelMarkers({ resource: window.LPS.state.editor.getModel().uri }).length);
  if (!markers) problems.push('a program that does not parse produced no markers');

  await browser.close();

  console.log(`\n${shots} screenshots in ${outdir}`);
  if (notes.length) {
    console.log(`\n${notes.length} note(s) — third-party URLs a corpus program asks for:`);
    for (const n of [...new Set(notes)]) console.log(`  · ${n}`);
  }
  if (problems.length) {
    console.log(`\n${problems.length} problem(s):`);
    for (const p of [...new Set(problems)]) console.log(`  ! ${p}`);
    process.exit(1);
  }
  console.log('no console errors, no failed requests, every pane drew something');
})().catch((e) => { console.error(e); process.exit(2); });
