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
  /*  A tokened server refuses everything, so hand the token over the way a
   *  person would — the IDE reads `?token=` once and stores it. This is what
   *  makes the tool usable against a deployment and not only against a laptop. */
  const TOKEN = process.env.LPS_TOKEN || '';
  await page.goto(TOKEN ? `${ide}?token=${encodeURIComponent(TOKEN)}` : ide,
    { waitUntil: 'networkidle' });
  await page.waitForSelector('.monaco-editor', { timeout: 20000 });
  await wait(2500);                                  // the 1500 ms analysis debounce
  await shot(page, '01-editor', '(Monaco, LPS syntax, declarative goat)');
  //  Play is for stories: on an LPS program the button is off, with a reason.
  if (!(await page.locator('#play-toggle').isDisabled())) problems.push('Play was enabled on a program that is not a story');
  else if (!/includes these resources: world/.test(await page.getAttribute('#play-toggle', 'title'))) problems.push('the disabled Play button does not say why');

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

  /*  A right-click on a fluent in a state box of the automaton asks about
   *  that fluent alone. The boxes pack two or three fluents to a line, and
   *  the whole line — "turn(2), + 17 unchanged" — was once the term asked
   *  about, which is not a term. */
  await page.click('#tabs button[data-pane="automaton"]');
  await wait(1200);
  const stateFluent = page.locator('#pane-automaton tspan.askable').first();
  if (await stateFluent.count()) {
    await stateFluent.click({ button: 'right' });
    await wait(1500);
    const q = await page.textContent('#dialog');
    if (/unchanged|syntax_error/.test(q) || !/why\(holds\(/.test(q)) {
      problems.push(`the automaton asked a malformed question: ${q.slice(0, 120)}`);
    }
    await page.click('#dialog-close');
    await wait(300);
  } else problems.push('no askable fluent in the automaton pane');

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

  /*  A program with a visual mapping, and the 2D pane.
   *
   *  Through the page's own client rather than a bare `fetch`: on a tokened
   *  server a raw POST has no token and comes back "unauthorised", and the
   *  only symptom here was "2D pane drew no canvas" — a true statement about
   *  a program that never loaded. */
  await page.evaluate(async () => {
    const r = await window.LPS.api.example('badlight');
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

  /*  Logical English, when this server can compile it (§3.5). Open one of
   *  LE2's own examples, run it, and follow a line of the generated program
   *  back to the English sentence that produced it — which is the whole claim
   *  of the provenance array, checked in a browser. */
  const le = await page.evaluate(() => window.LPS.api.api({ operation: 'le_status' })
    .catch((e) => ({ available: false, error: e.message })));
  if (le.available) {
    await page.goto(`${ide}?example=le/goat.le`, { waitUntil: 'networkidle' });
    await wait(4000);
    const lang = await page.evaluate(() => window.LPS.state.editor.getModel().getLanguageId());
    if (lang !== 'logicalenglish') problems.push(`a .le opened as ${lang}`);
    await page.click('#run');
    await page.waitForFunction(() => /cycles|error/.test(document.getElementById('status').textContent),
      { timeout: 60000 });
    const st = await page.textContent('#status');
    if (!/success/.test(st)) problems.push(`a Logical English program did not run: ${st}`);
    await page.click('#tabs button[data-pane="internal"]');
    await wait(1500);
    await shot(page, '11-logical-english', '(edited and run here, no LE2 server)');
    const linked = await page.locator('#pane-internal .generated .iline.has-source').count();
    if (!linked) problems.push('the generated program showed no provenance links');
    else {
      await page.locator('#pane-internal .generated .iline.has-source').first().click();
      await wait(600);
      const line = await page.evaluate(() => window.LPS.state.editor.getPosition().lineNumber);
      if (!(line > 0)) problems.push('following a provenance link went nowhere');
    }

    /*  Interactive fiction (docs/InformPlan.md phase 2). A story is a Logical
     *  English document that includes the library; the Play panel starts it
     *  from the tab, takes what a player types, and narrates the trace. The
     *  first thing typed is refused — the door is closed — and the refusal
     *  is the engine's explanation, so this is also `why_not` in a browser. */
    await page.goto(`${ide}?example=if/doors.le`, { waitUntil: 'networkidle' });
    await wait(4000);
    if (await page.locator('#play-toggle').isDisabled()) problems.push('Play was disabled on a story');
    await page.click('#play-toggle');
    await page.click('#play-start');
    await page.waitForFunction(() => /Hall/.test(document.getElementById('play-feed').textContent),
      { timeout: 60000 });
    await page.fill('#play-input', 'e');
    await page.press('#play-input', 'Enter');
    await page.waitForFunction(() => /You can't go east/.test(document.getElementById('play-feed').textContent),
      { timeout: 60000 });
    await page.fill('#play-input', 'open the door');
    await page.press('#play-input', 'Enter');
    await page.waitForFunction(() => /You open the oak door/.test(document.getElementById('play-feed').textContent),
      { timeout: 60000 });
    await page.fill('#play-input', 'e');
    await page.press('#play-input', 'Enter');
    await page.waitForFunction(() => /Garden/.test(document.getElementById('play-feed').textContent),
      { timeout: 60000 });
    await page.click('#play-commands');
    await wait(4000);
    const offered = await page.locator('#play-feed .play-line.command').allTextContents();
    if (!offered.some((t) => /go west/.test(t))) problems.push(`Commands in the garden did not offer "go west": ${offered.join(' | ')}`);
    if (offered.some((t) => /go east/.test(t))) problems.push('Commands in the garden offered "go east", which has no exit');
    /*  The panes follow the game: after these turns the IDE's session is the
     *  game's, the timeline draws it, and `commands` typed in the box lists
     *  what would work. */
    const following = await page.evaluate(() => ({ s: window.LPS.state.session, max: window.LPS.state.maxCycle }));
    if (!following.s || !(following.max > 0)) problems.push(`the panes do not follow the game: ${JSON.stringify(following)}`);
    await page.click('#tabs button[data-pane="timeline"]');
    await wait(1500);
    if (!(await page.locator('#pane-timeline svg rect.hold').count())) problems.push('the timeline drew nothing for the game');
    await page.fill('#play-input', 'commands');
    await page.press('#play-input', 'Enter');
    await wait(2500);
    const typedList = await page.locator('#play-feed .play-line.command').allTextContents();
    if (!typedList.some((t) => /go west/.test(t))) problems.push('`commands` typed in the box listed nothing usable');
    //  A click on a command does it: back through the door, into the Hall.
    await page.locator('#play-feed .play-line.command', { hasText: 'go west' }).last().click();
    await wait(3000);
    if (!/Hall/.test((await page.textContent('#play-feed')).slice(-400))) problems.push('clicking "go west" did not go west');
    await page.click('#play-why');
    await wait(1500);
    const played = await page.textContent('#play-feed');
    if (!/why\(happened\(go\(player,(east|west)\)\)/.test(played)) problems.push('Why? on a play turn gave no explanation');
    await shot(page, '13-play-doors', '(a story played from the editor; a refusal is a why_not)');
    console.log('  play: the door refused, opened, and was gone through; Why? answered');
    await page.click('#play-stop');

    /*  A document with a companion (docs/le_lps_surface.md §7). `badlight.le`
     *  says in its own header that the picture lives in `badlight.lps`, and
     *  the two compile together — so opening it must bring both halves, and
     *  running it must draw the scene the companion describes. The IDE
     *  brought only the English for a while, and the 2D pane, seeing no
     *  `display/2`, offered to write some: that is how an assistant came to
     *  append Prolog to a document written in English. */
    await page.goto(`${ide}?example=le/badlight.le`, { waitUntil: 'networkidle' });
    await wait(4000);
    const names = await page.evaluate(() => window.LPS.tabs.allTabs().map((t) => t.name));
    if (!names.includes('badlight.lps')) {
      problems.push(`the .lps companion did not open with the document: ${names.join(', ')}`);
    }
    await page.click('#run');
    await page.waitForFunction(() => /cycles|error/.test(document.getElementById('status').textContent),
      { timeout: 60000 });
    await page.click('#tabs button[data-pane="scene"]');
    await wait(1800);
    if (!(await page.locator('#pane-scene canvas').count())) {
      problems.push('a Logical English document with a companion drew no scene');
    }
    await shot(page, '12-le-companion', '(a .le and its .lps companion, one program)');

    /*  And the assistant's edits land in the right half.
     *
     *  This is the bug the companion work came from: "Animate in 2D" on a
     *  `.le` document appended `display/2` clauses to the *English*, and LE2
     *  reported an unknown section on a file the user had not touched. The
     *  model is stubbed here — a browser check must not need an API key, and
     *  what is being checked is the routing, not the plan — so the reply is
     *  the shape `lps_assistant.pl` produces for a Logical English buffer: a
     *  new companion and no change to the document. */
    const STUB_COMPANION = 'display(light(Room, on),\n'
      + "\t[type:circle, center:[0, 0], radius:10, fillColor:yellow, label:Room]).\n";
    let asked = null;
    await page.route('**/lpsapi', async (route) => {
      let body = {};
      try { body = route.request().postDataJSON() || {}; } catch { /* not JSON */ }
      if (body.operation === 'assistant_command') {
        asked = body;
        return route.fulfill({ contentType: 'application/json', body: JSON.stringify({ ok: true, job: 'stub' }) });
      }
      if (body.operation === 'assistant_status') {
        return route.fulfill({
          contentType: 'application/json',
          body: JSON.stringify({
            ok: true, status: 'done', output: [], error: null,
            explanation: 'stubbed', new_content: null, new_companion: STUB_COMPANION,
          }),
        });
      }
      return route.continue();
    });
    const before = await page.evaluate(() => window.LPS.state.editor.getValue());
    //  Clicked through the DOM: the button lives in the assistant dock, which
    //  may be collapsed — and its own handler is what opens the dock.
    await page.evaluate(() => document.getElementById('animate-2d').click());
    await page.waitForSelector('#assistant-log button.apply', { timeout: 30000 });
    if (!asked || asked.name !== 'badlight.le' || !asked.companion) {
      problems.push(`the assistant was not told which file it is looking at: ${JSON.stringify(asked && { name: asked.name, companion: !!asked.companion })}`);
    }
    await page.click('#assistant-log button.apply');
    await wait(2500);
    const after = await page.evaluate(() => ({
      le: window.LPS.tabs.allTabs().find((t) => t.name === 'badlight.le')?.model.getValue(),
      lps: window.LPS.tabs.allTabs().find((t) => t.name === 'badlight.lps')?.model.getValue(),
    }));
    if (after.le !== before) problems.push('an assistant scene edit changed the Logical English document');
    if (!/display\(light\(Room, on\)/.test(after.lps || '')) {
      problems.push('an assistant scene edit did not reach the .lps companion');
    }
    console.log('  assistant: a scene edit went to badlight.lps, not to the English');

    /*  And a document that has no companion yet gets one. This is the first
     *  time anybody animates a `.le` file, and it is where the pane strip used
     *  to go on saying "this program declares no display/2 clauses" about a
     *  program that had just been given some: the edit went into a model the
     *  editor was not showing, so nothing re-analysed. */
    //  The companion just edited is an unsaved buffer, and the IDE restores
    //  those on load — which would open it beside the next document and make
    //  the tab that is lit the wrong one.
    //  (and they are saved again on the way out, so the flag goes too)
    await page.evaluate(() => {
      window.LPS.tabs.allTabs().forEach((t) => { t.dirty = false; });
      localStorage.removeItem('lps.buffers');
    });
    await page.goto(`${ide}?example=le/goat.le`, { waitUntil: 'networkidle' });
    await wait(4000);
    await page.evaluate(() => document.getElementById('animate-2d').click());
    await page.waitForSelector('#assistant-log button.apply', { timeout: 30000 });
    await page.click('#assistant-log button.apply');
    await wait(4000);
    const made = await page.evaluate(() => ({
      names: window.LPS.tabs.allTabs().map((t) => t.name),
      display: !!window.LPS.state.profile?.display,
    }));
    if (!made.names.includes('goat.lps')) {
      problems.push(`no companion was opened for a document without one: ${made.names.join(', ')}`);
    }
    if (!made.display) problems.push('the program still reported no display/2 after the scene was applied');
    await page.unroute('**/lpsapi');
    console.log('  assistant: a document with no companion got one');
  } else {
    notes.push('Logical English skipped: no LE2 configured (set LPS_LE2_LIB)');
  }

  /*  A tokened server refuses everything, and the IDE has to *say so* rather
   *  than open an empty buffer and hang the example browser on "loading…" —
   *  which is what a first fly.io deployment looked like. The check is on this
   *  server: pretend the stored token is wrong and watch what one refused
   *  operation does. */
  await page.evaluate(() => localStorage.setItem('lps-token', 'definitely-not-the-token'));
  const refused = await page.evaluate(async () => {
    const r = await fetch('/lpsapi', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ operation: 'list_examples', token: 'definitely-not-the-token' }),
    }).then((x) => x.json());
    return r;
  });
  //  Only meaningful when this server *has* a token; without one it accepts
  //  the nonsense and there is nothing to check.
  if (refused.ok === false && /unauthoris/i.test(refused.error || '')) {
    await page.reload({ waitUntil: 'networkidle' });
    await wait(3000);
    const title = await page.textContent('#dialog-title');
    if (!/token/i.test(title || '')) problems.push('a refused server did not ask for a token');
  }
  await page.evaluate(() => localStorage.removeItem('lps-token'));

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
