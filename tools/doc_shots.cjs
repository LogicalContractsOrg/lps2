/* doc_shots.cjs — the pictures in docs/lps_tutorial.md and
 * docs/IntroducingLPS2.md, taken from the running system.
 *
 * Both documents are meant to be *evidence*, so none of their screenshots are
 * drawn by hand: this drives the real IDE, the real LE2 editor and the real
 * WASM page in Chromium and photographs what they do. Re-run it after a change
 * and the documents tell the truth again.
 *
 *   ./lps ide --port 3060 &                       # ours
 *   (cd /LogicalEnglish2 && ./myswipl.sh -q -g "use_module(classic_web_api), \
 *      start_api_server(3050)" -g "thread_get_message(_)" &)   # LE2's, optional
 *   NODE_PATH=/usr/lib/node_modules node tools/doc_shots.cjs docs/images 3060 3050
 */
const { chromium } = require('playwright');
const fs = require('fs');

const outdir = process.argv[2] || 'docs/images';
const port = process.argv[3] || '3060';
const lePort = process.argv[4] || '3050';
const base = `http://localhost:${port}/`;

fs.mkdirSync(outdir, { recursive: true });
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
const problems = [];
let n = 0;

async function shot(page, name, note, clip) {
  await page.screenshot({ path: `${outdir}/${name}.png`, clip });
  n++;
  console.log(`  ${name}.png  ${note || ''}`);
}

async function loadExample(page, name, file) {
  await page.evaluate(async ([n2, f]) => {
    const r = await fetch('/lpsapi', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ operation: 'example', name: n2 }),
    }).then((x) => x.json());
    if (!r.ok) throw new Error(r.error);
    window.LPS.load(r.source, f);
  }, [name, file]);
  await wait(2600);
}

async function run(page) {
  await page.click('#run');
  await page.waitForFunction(
    () => /cycles|error/.test(document.getElementById('status').textContent),
    { timeout: 120000 });
  await wait(1500);
}

//  A menu closes on a document click outside it, and there is no other way:
//  Escape is not bound. Click the middle of the editor, well below the bar.
async function closeMenus(page) {
  await page.mouse.click(400, 700);
  await wait(400);
}

async function pane(page, id, ms = 1800) {
  await page.click(`#tabs button[data-pane="${id}"]`);
  await wait(ms);
}

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1500, height: 900 } });
  page.on('pageerror', (e) => problems.push('pageerror: ' + e.message));
  page.on('console', (m) => { if (m.type() === 'error') problems.push('console: ' + m.text()); });
  page.on('response', (r) => { if (r.status() >= 400) problems.push(`HTTP ${r.status()} ${r.url()}`); });

  console.log(`driving ${base}`);
  await page.goto(base, { waitUntil: 'networkidle' });
  await page.waitForSelector('.monaco-editor', { timeout: 30000 });
  await wait(2600);

  /* ---- the editor ------------------------------------------------------ */
  await shot(page, 'ide-overview', 'the IDE, declarative goat loaded');

  await page.click('#menubar .menu:has-text("Misc")');
  await wait(400);
  await shot(page, 'ide-menu', 'the Misc menu', { x: 0, y: 0, width: 700, height: 420 });
  await closeMenus(page);

  await page.click('#menubar .menu:has-text("File")');
  await wait(300);
  await page.click('text=Open example from server…');
  await wait(2500);
  await shot(page, 'ide-examples', 'the examples browser: 160 corpus programs');
  await page.click('#dialog-close');
  await wait(400);

  /* ---- running the goat, and every reading of its trace ---------------- */
  await run(page);
  await shot(page, 'ide-timeline', 'the timeline (§I.10.2)');

  await page.evaluate(() => window.LPS.setCycle(3));
  await wait(1200);
  await pane(page, 'changes');
  await shot(page, 'ide-changes', 'state changes, with the causal law that fired');

  await pane(page, 'internal');
  await shot(page, 'ide-internal', 'the internal syntax the engine actually runs');

  await pane(page, 'explain');
  await page.fill('#ask', 'why(happened(A), 2)');
  await page.click('#ask-go');
  await wait(1500);
  await shot(page, 'ide-explain', 'why did that happen?');

  await page.fill('#ask', 'why_not(happened(transport(wolf,south,north)), 1)');
  await page.click('#ask-go');
  await wait(1500);
  await shot(page, 'ide-why-not', 'why did it *not* happen?');

  /* ---- the automaton, on a program that loops --------------------------
     The goat never revisits a state, so its diagram is a chain and says
     nothing the timeline does not. Five philosophers put down their forks
     and the diagram closes. */
  await loadExample(page, 'dining_philosophers_terse', 'dining_philosophers_terse.pl');
  await run(page);
  await pane(page, 'automaton', 2800);
  await shot(page, 'ide-automaton', 'the state-transitions diagram');

  /* ---- animation, 2D and 3D ------------------------------------------- */
  await loadExample(page, 'CLOUT_workshop/burning', 'burning.pl');
  await run(page);
  await pane(page, 'scene', 2200);
  await page.evaluate(() => window.LPS.setCycle(6));
  await wait(2200);
  await shot(page, 'ide-2d', 'the 2D animation on Konva, bottom-left origin');

  await loadExample(page, 'blocks3d', 'blocks3d.lps');
  await run(page);
  await pane(page, 'scene3d', 2500);
  await page.evaluate(() => window.LPS.setCycle(4));
  await wait(2500);
  await shot(page, 'ide-3d', 'the 3D pane on three.js, driven by display3d/2');

  /* ---- diagnostics ----------------------------------------------------- */
  await page.evaluate(() => {
    window.LPS.state.editor.setValue(
      'maxTime(6).\nfluents light(_).\nactions switch(_).\n\n'
      + 'initially light(off).\n\n'
      + 'switch(New) initiates light(New).\n\n'
      + 'if light(off) at T\nthen switch(on) from T to\n');
  });
  await wait(2800);
  await shot(page, 'ide-diagnostics', 'a program that does not parse');

  /* ---- the assistant --------------------------------------------------- */
  await loadExample(page, 'goat_declarative', 'goat_declarative.pl');
  await page.click('#assistant-toggle');
  await wait(600);
  const models = await page.locator('#assistant-model option').count();
  if (models > 0 && !(await page.locator('#assistant-model option').first().textContent()).includes('no models')) {
    await page.click('#animate-2d');
    console.log('  (waiting for the assistant…)');
    for (let i = 0; i < 100; i++) {
      const t = await page.textContent('#assistant-log');
      if (/Apply to editor|error|no LLM/i.test(t)) break;
      await wait(2000);
    }
    await wait(1000);
    await shot(page, 'ide-assistant', 'the assistant writing display/2 clauses');
    const apply = page.locator('#assistant-log button.apply');
    if (await apply.count()) {
      await apply.first().click();
      await wait(2600);
      await run(page);
      await pane(page, 'scene', 2500);
      await page.evaluate(() => window.LPS.setCycle(4));
      await wait(2500);
      await shot(page, 'ide-assistant-2d', 'one click from no visual mapping to this');
    }
  } else {
    console.log('  (no LLM key configured — skipping the assistant shots)');
  }

  /* ---- a live session -------------------------------------------------- */
  await loadExample(page, 'thermostat', 'thermostat.lps');
  await page.click('#live-toggle');
  await wait(400);
  await page.click('#live-start');
  await wait(2200);
  await page.fill('#live-event', 'temperature(14)');
  await page.click('#live-send');
  await wait(2200);
  await page.fill('#live-event', 'window(open)');
  await page.click('#live-send');
  await wait(2600);
  await shot(page, 'ide-live', 'a session that does not end, taking events');

  const liveId = await page.evaluate(() => window.LPS.state.live);
  if (liveId) {
    const view = await browser.newPage({ viewport: { width: 760, height: 620 } });
    await view.goto(`${base}live-view.html?live=${liveId}&kind=2d`, { waitUntil: 'networkidle' });
    await wait(3500);
    await view.screenshot({ path: `${outdir}/live-2d.png` });
    n++;
    console.log('  live-2d.png  a live view, following a running session');
    await view.click('#kill');            // which also disables the IDE's Stop
    await view.close();
    await wait(1500);
  }
  if (await page.locator('#live-stop').isEnabled()) await page.click('#live-stop');

  /* ---- WASM ------------------------------------------------------------ */
  const html = await page.evaluate(async () => {
    const src = await fetch('/lpsapi', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ operation: 'example', name: 'CLOUT_workshop/bankTransfer' }),
    }).then((r) => r.json());
    const r = await fetch('/lpsapi', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ operation: 'wasm_bundle', source: src.source, title: 'bankTransfer.pl' }),
    }).then((x) => x.json());
    return r.html;
  });
  fs.writeFileSync('src/ide/dist/doc-wasm.html', html);
  const wasm = await browser.newPage({ viewport: { width: 1200, height: 700 } });
  await wasm.goto(`${base}doc-wasm.html`, { waitUntil: 'networkidle' });
  for (let i = 0; i < 60; i++) {
    if ((await wasm.textContent('#status')) === 'ready') break;
    await wait(1000);
  }
  if ((await wasm.textContent('#status')) === 'ready') {
    await wasm.click('#run');
    for (let i = 0; i < 40; i++) {
      if (/done|error/.test(await wasm.textContent('#status'))) break;
      await wait(1000);
    }
    await wait(800);
    await wasm.screenshot({ path: `${outdir}/wasm.png` });
    n++;
    console.log('  wasm.png  the engine in a browser, no server');
  }
  await wasm.close();

  /* ---- LE2, if it is running ------------------------------------------- */
  try {
    const le = await browser.newPage({ viewport: { width: 1500, height: 900 } });
    await le.goto(`http://localhost:${lePort}/editor/lps.html`, { waitUntil: 'networkidle', timeout: 15000 });
    await wait(3500);
    await le.click('text=compile & run');
    for (let i = 0; i < 40; i++) {
      if (/cycles|error/i.test(await le.textContent('body'))) break;
      await wait(1000);
    }
    await wait(2500);
    await le.screenshot({ path: `${outdir}/le2-lps.png` });
    n++;
    console.log('  le2-lps.png  Logical English, compiled and run on LPS(2)');
    await le.close();
  } catch (e) {
    console.log(`  (LE2 not reachable on :${lePort} — skipping)`);
  }

  await browser.close();
  console.log(`\n${n} images in ${outdir}`);
  if (problems.length) {
    console.log(`${problems.length} problem(s):`);
    for (const p of [...new Set(problems)].slice(0, 10)) console.log(`  ! ${p}`);
  }
})().catch((e) => { console.error(e); process.exit(1); });
