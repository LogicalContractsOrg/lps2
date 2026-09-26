/* doc_shots.cjs — the pictures in docs/user/tutorials/lps-tutorial.md and
 * docs/user/overview/introducing-lps2.md (and its companion, introducing-lps2-technical.md), taken from the running system.
 *
 * Both documents are meant to be *evidence*, so none of their screenshots are
 * drawn by hand: this drives the real IDE, the real LE2 editor and the real
 * WASM page in Chromium and photographs what they do. Re-run it after a change
 * and the documents tell the truth again.
 *
 *   ./lps ide --port 3060 &                       # ours
 *   (cd /LogicalEnglish2 && ./myswipl.sh -q -g "use_module(classic_web_api), \
 *      start_api_server(3050)" -g "thread_get_message(_)" &)   # LE2's, optional
 *   NODE_PATH=/usr/lib/node_modules node tools/doc_shots.cjs docs/user/images 3060 3050
 */
const { chromium } = require('playwright');
const fs = require('fs');

const outdir = process.argv[2] || 'docs/user/images';
const port = process.argv[3] || '3060';
const lePort = process.argv[4] || '3050';
const base = `http://localhost:${port}/`;
//  The IDE moved to /ide when `/` became the landing page.
const ide = `${base}ide`;

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
  await page.goto(ide, { waitUntil: 'networkidle' });
  await page.waitForSelector('.monaco-editor', { timeout: 30000 });
  await wait(2600);

  /*  The light theme, for the documents. The dark one is the default and the
   *  nicer one to work in; a page printed on white wants the other. */
  await page.evaluate(() => {
    window.LPS.monaco.editor.setTheme('lps-light');
    document.body.dataset.theme = 'light';
    localStorage.setItem('lps.theme', '"lps-light"');
    window.LPS.refresh();
  });
  await wait(1200);

  /* ---- the editor ------------------------------------------------------ */
  await shot(page, 'ide-overview', 'the IDE, declarative goat loaded');

  //  The landing page — what `/` is now, and the first thing anybody sees.
  {
    const home = await browser.newPage({ viewport: { width: 1200, height: 900 } });
    await home.goto(`${base}?expand=all`, { waitUntil: 'networkidle' });
    await wait(600);
    await home.screenshot({ path: `${outdir}/landing.png` });
    console.log('· landing  the start page: every example, grouped');
    await home.close();
  }

  await page.click('#menubar .menu:has-text("Misc")');
  await wait(400);
  await shot(page, 'ide-menu', 'the Misc menu', { x: 0, y: 0, width: 700, height: 420 });
  await closeMenus(page);

  await page.click('#menubar .menu:has-text("File")');
  await wait(300);
  await page.click('text=Open example from server…');
  await wait(2500);
  await shot(page, 'ide-examples', 'the examples browser: every program on the server');
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

  /* ---- "why?", asked where the thing is -------------------------------
     There is no explain pane any more: right-click what a pane drew. */
  await pane(page, 'timeline', 2000);
  await page.locator('#pane-timeline .ev.askable').first().click({ button: 'right' });
  await wait(2200);
  await shot(page, 'ide-explain', 'right-click an event: why did that happen?');

  await page.fill('.why-not', 'happened(transport(wolf,south,north))');
  await page.click('.why-notrow button');
  await wait(2200);
  await shot(page, 'ide-why-not', '…and why did it *not*?');
  await page.click('#dialog-close');
  await wait(400);

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

  await loadExample(page, 'start/blocks3d', 'blocks3d.lps');
  await run(page);
  await pane(page, 'scene3d', 2500);
  await page.evaluate(() => window.LPS.setCycle(4));
  await wait(2500);
  await shot(page, 'ide-3d', 'the 3D pane on three.js, driven by display3d/2');

  /* ---- several files at once ------------------------------------------- */
  await loadExample(page, 'start/thermostat', 'thermostat.lps');
  await page.evaluate(async () => {
    const r = await fetch('/lpsapi', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ operation: 'example', name: 'start/goat_declarative' }),
    }).then((x) => x.json());
    window.LPS.tabs.openTab(r.source, 'goat_declarative.pl');
  });
  await wait(2400);
  await run(page);
  await pane(page, 'timeline', 1800);
  await shot(page, 'ide-tabs', 'two files, each with its own run');

  /* ---- diagnostics ----------------------------------------------------- */
  await page.evaluate(() => {
    window.LPS.load(
      'maxTime(6).\nfluents light(_).\nactions switch(_).\n\n'
      + 'initially light(off).\n\n'
      + 'switch(New) initiates light(New).\n\n'
      + 'if light(off) at T\nthen switch(on) from T to\n', 'broken.lps');
  });
  await wait(2800);
  await shot(page, 'ide-diagnostics', 'a program that does not parse');

  /* ---- the assistant --------------------------------------------------- */
  await loadExample(page, 'start/goat_declarative', 'goat_declarative.pl');
  await page.evaluate(() => window.LPS.toggleDock('assistant'));
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
  await loadExample(page, 'start/thermostat', 'thermostat.lps');
  if (await page.locator('#assistant').evaluate((e) => !e.classList.contains('collapsed'))) {
    await page.evaluate(() => window.LPS.toggleDock('assistant'));  // give the feed the room
    await wait(400);
  }
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

  /*  Interactive fiction (docs/project/plans/InformPlan.md): Alice, played from the editor,
   *  forked at the bottle. The refusal on the second line of the transcript is
   *  the engine's own why_not, rendered. */
  await page.goto(`${ide}?example=if/alice.le`, { waitUntil: 'networkidle' });
  await wait(4000);
  //  A dock left open by the section above would leave Start hidden, and the
  //  program of that section is still open in a tab: make the story's tab the
  //  active one, since Play plays the document on screen.
  if (await page.locator('#live-stop').isVisible()) await page.click('#live-stop');
  await page.evaluate((n) => { const t = window.LPS.tabs.allTabs().find((x) => x.name === n); if (t) window.LPS.tabs.setActive(t.id); }, 'alice.le');
  if (!(await page.locator('#play-start').isVisible())) await page.click('#play-toggle');
  await page.click('#play-start');
  try {
    await page.waitForFunction(() => /Riverbank/.test(document.getElementById('play-feed').textContent), { timeout: 180000 });
  } catch (e) {
    console.log('  play did not start:', await page.textContent('#play-status'), '|', (await page.textContent('#play-feed')).slice(0, 300));
    throw e;
  }
  for (const t of ['z', 'z', 'd', 'd', 'drink bottle', 'take key']) {
    await page.fill('#play-input', t);
    await page.press('#play-input', 'Enter');
    await wait(2500);
  }
  await page.selectOption('#play-game', '__fork__');
  await wait(2500);
  await shot(page, 'ide-play-alice', 'Alice in the hall, small, the key out of reach — and a fork');
  await page.click('#play-stop');
  /*  docs/user/tutorials/inform-users.md: an Inform source opened as a story, the IQ
   *  Test played with a why, Alice forked with the diff, and Alice's scripted
   *  run on the timeline and the state-transition diagram. */
  await page.goto(`${ide}?example=if/inform/IQTest.ni`, { waitUntil: 'networkidle' });
  await wait(4500);
  await shot(page, 'guide-inform-import', 'an Inform 7 source, opened as the Logical English story its assertions make');
  await page.goto(`${ide}?example=if/iqtest.le`, { waitUntil: 'networkidle' });
  await wait(4000);
  await page.evaluate((n) => { const t = window.LPS.tabs.allTabs().find((x) => x.name === n); if (t) window.LPS.tabs.setActive(t.id); }, 'iqtest.le');
  if (!(await page.locator('#play-start').isVisible())) await page.click('#play-toggle');
  await page.click('#play-start');
  await page.waitForFunction(() => /Shop/.test(document.getElementById('play-feed').textContent), { timeout: 180000 });
  for (const t of ['open case', 'get donuts', 'og, get donuts', 'og, give donuts to me']) {
    await page.fill('#play-input', t);
    await page.press('#play-input', 'Enter');
    await wait(3000);
  }
  await page.click('#play-why');
  await wait(2000);
  await shot(page, 'guide-iqtest-play', 'Inform\'s IQ Test on LPS: two refusals explained, Ogg\'s plan found, and why');
  await page.click('#play-stop');
  await page.goto(`${ide}?example=if/alice.le`, { waitUntil: 'networkidle' });
  await wait(4000);
  await page.evaluate((n) => { const t = window.LPS.tabs.allTabs().find((x) => x.name === n); if (t) window.LPS.tabs.setActive(t.id); }, 'alice.le');
  await page.click('#run');
  await page.waitForFunction(() => /cycles|error/.test(document.getElementById('status').textContent), { timeout: 120000 });
  await page.click('#tabs button[data-pane="timeline"]');
  await wait(2500);
  await shot(page, 'guide-alice-timeline', 'the book\'s path through Alice, as a timeline');
  await page.click('#tabs button[data-pane="automaton"]');
  await wait(3000);
  await shot(page, 'guide-alice-automaton', 'the same run as a state-transition diagram');
  if (!(await page.locator('#play-start').isVisible())) await page.click('#play-toggle');
  await page.click('#play-start');
  await page.waitForFunction(() => /Riverbank/.test(document.getElementById('play-feed').textContent), { timeout: 180000 });
  for (const t of ['z', 'z', 'd', 'd']) {
    await page.fill('#play-input', t);
    await page.press('#play-input', 'Enter');
    await wait(2500);
  }
  await page.selectOption('#play-game', '__fork__');
  await wait(2500);
  for (const t of ['take key', 'drink bottle', 'unlock door with key', 'open door', 's']) {
    await page.fill('#play-input', t);
    await page.press('#play-input', 'Enter');
    await wait(2500);
  }
  await page.click('#play-diff');
  await wait(2500);
  await shot(page, 'guide-alice-fork', 'Alice forked at the bottle: the garden path, and the diff against the book\'s');
  await page.click('#play-stop');

  /*  The stories drawn: display/2 and display3d/2 clauses a model wrote into
   *  the companions (see the header of examples/if/alice.lps). The pictures
   *  regenerate from those clauses; the clauses themselves do not. */
  for (const [story, cycle] of [['alice', 40], ['iqtest', 12]]) {
    await page.goto(`${ide}?example=if/${story}.le`, { waitUntil: 'networkidle' });
    await wait(4000);
  await page.evaluate((n) => { const t = window.LPS.tabs.allTabs().find((x) => x.name === n); if (t) window.LPS.tabs.setActive(t.id); }, `${story}.le`);
    await run(page);
    await pane(page, 'scene', 2500);
    await page.evaluate((c) => window.LPS.setCycle(c), cycle);
    await wait(2500);
    await shot(page, `guide-${story}-2d`, `${story}, drawn in 2D at cycle ${cycle}`);
    await pane(page, 'scene3d', 5000);
    await page.evaluate((c) => window.LPS.setCycle(c), cycle);
    await wait(3000);
    await shot(page, `guide-${story}-3d`, `${story}, drawn in 3D at cycle ${cycle}`);
  }

  //  The page was reloaded for the story, which closed the docks the sections
  //  below expect: the live panel open, the play panel not.
  await page.click('#play-toggle');
  if (!(await page.locator('#live-start').isVisible())) await page.click('#live-toggle');
  await wait(500);

  /*  Logical English, edited and run here — when this server has a checkout to
   *  load. It is a documented feature only where it is configured, so the shot
   *  is skipped rather than faked. */
  {
    const st = await page.evaluate(() => fetch('/lpsapi', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ operation: 'le_status' }),
    }).then((r) => r.json()));
    if (st.available) {
      const lep = await browser.newPage({ viewport: { width: 1500, height: 900 } });
      //  A fresh page is a fresh localStorage, and the documents are shot in
      //  the light theme.
      await lep.goto(base, { waitUntil: 'domcontentloaded' });
      await lep.evaluate(() => localStorage.setItem('lps.theme', '"lps-light"'));
      await lep.goto(`${ide}?example=le/goat.le`, { waitUntil: 'networkidle' });
      await wait(4500);
      await lep.click('#run');
      await wait(4000);
      await lep.click('#tabs button[data-pane="internal"]');
      await wait(1800);
      await lep.screenshot({ path: `${outdir}/ide-le.png` });
      console.log('  ide-le.png  Logical English, edited and run in this IDE');
      n++;
      await lep.close();
    } else {
      console.log('  (no LE2 configured: skipping the Logical English shot)');
    }
  }

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
  //  Visible, not enabled: the live panel now hides the controls that have no
  //  session to act on rather than greying them out, and a hidden button still
  //  reports itself as enabled.
  if (await page.locator('#live-stop').isVisible()) await page.click('#live-stop');

  /* ---- an animation you can click on ------------------------------------ */
  {
    const src = fs.readFileSync('examples/start/lights.lps', 'utf8');
    await page.evaluate((t) => window.LPS.load(t, 'lights.lps'), src);
    await wait(2400);
    await page.click('#live-start');
    await wait(2200);
    const id = await page.evaluate(() => window.LPS.state.live);
    const v = await browser.newPage({ viewport: { width: 720, height: 560 } });
    await v.goto(`${base}live-view.html?live=${id}&kind=2d`, { waitUntil: 'networkidle' });
    await wait(3000);
    const box = await v.locator('#view').boundingBox();
    await v.mouse.click(box.x + 120, box.y + 300);       // the first lamp
    await wait(3000);
    await v.screenshot({ path: `${outdir}/live-click.png` });
    n++;
    console.log('  live-click.png  a program being clicked on');
    await v.click('#kill');
    await v.close();
    await wait(1200);
  }

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
  //  Not `networkidle`: the SWI-Prolog runtime streams its .wasm and its
  //  data files for a while, and the page is interactive long before the
  //  network goes quiet. The loop below waits for the status it actually cares
  //  about.
  await wasm.goto(`${base}doc-wasm.html`, { waitUntil: 'domcontentloaded' });
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
    console.log('  le2-lps.png  Logical English, compiled and run on LPS2');
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
