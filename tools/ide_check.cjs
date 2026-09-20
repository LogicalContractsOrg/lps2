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
  const browser = await chromium.launch(process.env.CHROME ? { executablePath: process.env.CHROME } : {});
  const page = await browser.newPage({ viewport: { width: 1500, height: 940 } });

  page.on('console', (m) => {
    if (m.type() === 'error') (ours(m.text()) ? problems : notes).push(`console: ${m.text()}`);
  });
  page.on('pageerror', (e) => problems.push(`pageerror: ${e.message}`));
  page.on('requestfailed', (r) => (ours(r.url()) ? problems : notes).push(`request failed: ${r.url()}`));
  page.on('response', async (r) => {
    if (r.status() < 400) return;
    //  Which operation, and what the server said: a bare 500 names nothing.
    let op = '';
    try { op = JSON.parse(r.request().postData() || '{}').operation || ''; } catch { /* not ours */ }
    let body = '';
    try { body = (await r.text()).slice(0, 300); } catch { /* gone */ }
    problems.push(`HTTP ${r.status()}: ${r.url()} ${op ? `(operation ${op})` : ''} ${body}`);
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

  /*  The three libraries a picture can be made of — icons, fills, 3D objects.
   *  A name in a manifest with no builder behind it is a name the assistant
   *  will offer and the renderer will ignore, which is the worst of both. */
  const libs = await page.evaluate(() => {
    const L = window.LPS?.libraries;
    if (!L) return null;
    return { icons: L.icons.length, fills: L.fills.length,
             objects: L.objects.length, missing: L.missingModels() };
  });
  if (!libs) problems.push('the icon/fill/object libraries are not loaded');
  else {
    console.log(`  libraries: ${libs.icons} icons, ${libs.fills} fills, ${libs.objects} objects`);
    if (!libs.fills || !libs.objects) problems.push('a library is empty');
    if (libs.missing.unbuilt.length) problems.push(`3D objects listed but not built: ${libs.missing.unbuilt}`);
    if (libs.missing.unlisted.length) problems.push(`3D objects built but not listed: ${libs.missing.unlisted}`);
  }

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

  /*  The run as a STRIP, and back (AnimationPlan §7, the review's R3/R4/R11).
   *
   *  Driven through the pane's own toolbar, which is where the control now
   *  lives: the checkbox it replaced sat in the assistant's dock, three panels
   *  away and invisible on a server with no API key. The way back from a
   *  zoomed frame is the same button, and that is what the reviewer could not
   *  find, so it is checked here rather than described in a document. */
  const tools = () => page.$$eval('#pane-scene .scene-tools button', (n) => n.map((b) => b.textContent));
  const before = await tools();
  if (before[0] !== 'Scenes') problems.push(`the 2D toolbar does not offer Scenes first (${before.join(', ')})`);
  await page.click('#pane-scene .scene-tools button');
  await wait(2500);
  const frames = await page.locator('#pane-scene .strip-frame').count();
  if (frames < 2) problems.push(`the scene strip drew ${frames} frames`);
  const stripTools = await tools();
  if (!stripTools.includes('PNG') || !stripTools.some((t) => /Single scene/.test(t))) {
    problems.push(`the strip has no toolbar of its own (${stripTools.join(', ')})`);
  }
  await shot(page, '09b-scene-strip', `(the run as ${frames} scenes)`);
  if (frames >= 2) {
    await page.click('#pane-scene .strip-frame >> nth=1');
    await wait(2000);
    const back = await tools();
    if (back[0] !== '\u25c0 Scenes') problems.push(`no way back to the strip from a frame (${back.join(', ')})`);
    await page.click('#pane-scene .scene-tools button');
    await wait(2500);
    if (!(await page.locator('#pane-scene .strip-frame').count())) problems.push('the way back to the strip did not go back');
  }
  //  …and leave the pane the way it was found: the choice is remembered, and
  //  everything after this reads the single scene.
  await page.click('#pane-scene .scene-tools button >> nth=0');
  await wait(1500);
  console.log(`  the strip: ${frames} scenes, zoomed one, came back`);

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

    /*  Interactive fiction (docs/project/plans/InformPlan.md phase 2). A story is a Logical
     *  English document that includes the library; the Play panel starts it
     *  from the tab, takes what a player types, and narrates the trace. The
     *  first thing typed is refused — the door is closed — and the refusal
     *  is the engine's explanation, so this is also `why_not` in a browser. */
    //  Opened as a landing-page link opens it: no extension. The server
    //  answers with the file as found, so the tab is `doors.le` and the
    //  editor knows it is Logical English; opened as `doors` it was read as
    //  LPS, did not compile, and could not be played.
    await page.goto(`${ide}?example=if/doors`, { waitUntil: 'networkidle' });
    await wait(4000);
    if (!/doors\.le/.test(await page.textContent('#tabs, .tabs, body'))) problems.push('?example=if/doors did not open a tab named doors.le');
    /*  Show definition on the `includes these resources:` line opens the
     *  resource — a document, in a tab of its own — and Go back returns. */
    {
      const placed = await page.evaluate(() => {
        const ed = window.LPS.state.editor, m = ed.getModel();
        for (let i = 1; i <= m.getLineCount(); i++) {
          const l = m.getLineContent(i), k = l.indexOf('resources:');
          if (k < 0) continue;
          const col = l.indexOf('world', k) + 2;
          ed.setPosition({ lineNumber: i, column: col });
          return true;
        }
        return false;
      });
      if (!placed) problems.push('doors.le has no "includes these resources:" line to test Show definition on');
      else {
        await page.evaluate(() => window.LPS.state.editor.getAction('lps.showDefinition').run());
        await wait(2500);
        const tabsNow = await page.evaluate(() => ({ names: window.LPS.tabs.allTabs().map((t) => t.name), active: window.LPS.tabs.activeTab()?.name }));
        if (!tabsNow.names.includes('world.le')) problems.push(`Show definition on a resource did not open world.le (tabs: ${tabsNow.names.join(', ')})`);
        else if (tabsNow.active !== 'world.le') problems.push(`Show definition opened world.le but did not switch to it (active: ${tabsNow.active})`);
        else console.log('  show definition: "world" on the resources line opened world.le');
        await page.evaluate(() => window.LPS.state.editor.getAction('lps.goBack').run());
        await wait(500);
        const back = await page.evaluate(() => window.LPS.tabs.activeTab()?.name);
        if (back !== 'doors.le') problems.push(`Go back after a resource jump landed on ${back}, not doors.le`);
      }
    }
    /*  Live on a Logical English story compiles the story, not the English
     *  as Prolog: it used to answer "syntax error: operator_expected (line
     *  1)" because the panel compiled the buffer as legacy LPS. */
    {
      await page.click('#live-toggle');
      await wait(500);
      await page.click('#live-start');
      await wait(3000);
      const feed = await page.textContent('#live-feed');
      if (/syntax error/.test(feed)) problems.push(`Live on a .le story: ${feed.match(/syntax error[^\n]*/)[0]}`);
      else if (!/started live/.test(feed)) problems.push(`Live on a .le story did not start (feed: ${feed.slice(0, 200)})`);
      else console.log('  live: a Logical English story started as a live session');
      if (await page.locator('#live-stop').isVisible()) await page.click('#live-stop');
      await wait(500);
      await page.click('#live-toggle');
      await wait(300);
    }
    if (await page.locator('#play-toggle').isDisabled()) problems.push('Play was disabled on a story');
    //  Before anything has run, the placeholder offers Play for a story.
    await page.click('#tabs button[data-pane="timeline"]');
    await wait(800);
    const placeholder = await page.locator('#pane-timeline .start-here');
    if (!(await placeholder.count())) problems.push('no "Nothing has been run yet" page for a story just opened');
    else if (!/Or play it/.test(await placeholder.textContent())) problems.push('the "Nothing has been run yet" page did not offer Play for a story');
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
    /*  The log keeps track of turns: every typed line wears its turn and
     *  cycles, the slider's cycle marks the turn it fell in, and a click on
     *  a thing in a scene pane (here: the event the panes send) marks the
     *  turn of that thing's last change. */
    const badges = await page.locator('#play-feed .play-line.typed .play-turn').allTextContents();
    if (!badges.some((t) => /turn \d+ · cycles? \d+/.test(t))) problems.push(`the typed lines carry no turn badges: ${badges.join(' | ')}`);
    const turns = await page.evaluate(() => {
      const ds = [...document.querySelectorAll('#play-feed .play-line.typed[data-turn]')];
      return ds.map((d) => ({ turn: Number(d.dataset.turn), from: Number(d.dataset.from), to: Number(d.dataset.to) }));
    });
    const opened = turns.find((t) => t.turn === 2);   // "open the door" was the second turn
    if (!opened) problems.push(`no line for turn 2 in the log: ${JSON.stringify(turns)}`);
    else {
      await page.evaluate((c) => window.LPS.setCycle(c), opened.from);
      await wait(500);
      const current = await page.evaluate(() => [...document.querySelectorAll('#play-feed .play-line.current[data-turn]')].map((d) => d.dataset.turn));
      if (!current.includes('2')) problems.push(`the slider at cycle ${opened.from} did not mark turn 2 (marked: ${current.join(',')})`);
    }
    //  A pick answers as of the slider's cycle; back at the end, the player's last move is the last turn.
    await page.evaluate(() => window.LPS.setCycle(window.LPS.state.maxCycle));
    await page.evaluate(() => window.dispatchEvent(new CustomEvent('lps-pick', { detail: { term: 'in(player,hall)', kind: 'fluent' } })));
    await wait(2500);
    const pickSaid = (await page.textContent('#play-feed')).slice(-300);
    if (!/player: last changed on turn \d+, cycle \d+/.test(pickSaid)) problems.push(`a pick on the player did not find its last change: ${pickSaid}`);
    const picked = await page.evaluate(() => ({ cycle: window.LPS.state.cycle,
      marked: [...document.querySelectorAll('#play-feed .play-line.current[data-turn]')].map((d) => d.dataset.turn) }));
    if (!picked.marked.length) problems.push(`the pick marked no turn: ${JSON.stringify(picked)}`);
    await page.click('#play-why');
    await wait(1500);
    const played = await page.textContent('#play-feed');
    if (!/why\(happened\(go\(player,(east|west)\)\)/.test(played)) problems.push('Why? on a play turn gave no explanation');
    await shot(page, '13-play-doors', '(a story played from the editor; a refusal is a why_not)');
    /*  Diff compares a fork with its parent, so it is off until the picker's
     *  last item, "Fork this game…", has made one; "commands each turn" lists
     *  what would work after the next turn; and a line the parser does not
     *  understand either stays not understood (no key) or is handed to a
     *  model (a key in the server's environment), which picks or declines. */
    if (!(await page.locator('#play-diff').isDisabled())) problems.push('Diff was enabled on a game that is not a fork');
    await page.selectOption('#play-game', '__fork__');
    await wait(3000);
    if (await page.locator('#play-diff').isDisabled()) problems.push('Diff stayed disabled on a fork');
    if (!/fork of/.test(await page.locator('#play-game option:checked').textContent())) problems.push('the picker did not switch to the fork');
    await page.check('#play-auto');
    await page.fill('#play-input', 'look');
    await page.press('#play-input', 'Enter');
    await wait(4000);
    if (!/You could:/.test((await page.textContent('#play-feed')).slice(-600))) problems.push('"commands each turn" listed nothing after a turn');
    await page.uncheck('#play-auto');
    await page.fill('#play-input', 'xyzzy plugh');
    await page.press('#play-input', 'Enter');
    await page.waitForFunction(() => /I don't understand that|I really don't understand that|I take that as/.test(document.getElementById('play-feed').textContent.slice(-400)),
      { timeout: 90000 });
    if ((await page.getAttribute('#play-input', 'placeholder')) !== '> open the door   (Commands lists what would work now)') problems.push('the input placeholder was not restored after a guess');
    console.log('  play: the door refused, opened, and was gone through; Why? answered; forked, listed, guessed');
    await page.click('#play-stop');

    /*  A document with a companion (docs/user/reference/le-for-lps.md §7). `badlight.le`
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

  /*  Every link on the start page must open. The page and the picker are
   *  built from the same list, but the lookup is another predicate, and the
   *  two drifted once: LE2's examples were listed as `bank_transfer.le` and
   *  found only as `le/bank_transfer.le`, so the link opened an empty buffer
   *  with no more than a status-line complaint. */
  const links = await page.evaluate(async (base) => {
    const html = await fetch(base).then((r) => r.text());
    const names = [...new Set([...html.matchAll(/\?example=([^"&]+)/g)].map((m) => decodeURIComponent(m[1])))];
    const failed = [];
    for (const name of names) {
      try { await window.LPS.api.example(name); } catch (e) { failed.push(`${name}: ${e.message}`); }
    }
    return { total: names.length, failed };
  }, base);
  if (!links.total) problems.push('the start page listed no examples');
  if (links.failed.length) problems.push(`start-page links that do not open: ${links.failed.join('; ')}`);
  console.log(`  start page: ${links.total} example links, ${links.failed.length} failed`);

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

  /*  The documentation: its search (static/docs-extras.js), the integrations
      map with its links to LE2, and "Documentation for this". */
  {
    const ctx = page.context();
    await page.goto(`${base}docs/search?q=fluents`, { waitUntil: 'networkidle' });
    await page.waitForSelector('.docs-search-results li a', { timeout: 20000 }).catch(() => {});
    const hits = await page.$$eval('.docs-search-results li a', (as) => as.map((a) => a.getAttribute('href')));
    if (!hits.length) problems.push('the documentation search found nothing for "fluents"');
    else if (!hits.every((h) => h.startsWith('/docs/user/'))) problems.push('a search result does not link a document: ' + hits.find((h) => !h.startsWith('/docs/user/')));
    await shot(page, '11-docs-search', '(the documentation search)');
    await page.goto(`${base}docs/user/integrations/index`, { waitUntil: 'networkidle' });
    await page.waitForSelector('.docs-diagram svg', { timeout: 30000 }).catch(() => problems.push('the integrations map was not drawn'));
    const links = await page.$$eval('.docs-diagram a', (as) => as.map((a) => a.getAttribute('xlink:href') || a.getAttribute('href')));
    if (!links.includes('pddl')) problems.push('the integrations map does not link the PDDL document');
    if (links.some((l) => /logicalcontracts\.com/.test(l)) && /localhost/.test(base)) problems.push('a link of the map to LE2 was not rewritten to the local LE2');
    await shot(page, '12-integrations-map', '(the integrations map)');
    await page.goto(`${base}ide`, { waitUntil: 'networkidle' });
    await wait(3000);
    const popup = ctx.waitForEvent('page', { timeout: 10000 }).catch(() => null);
    await page.evaluate(() => {
      const ed = window.LPS.state.editor;
      ed.setValue('fluents open.\nevents opens(Door).\nopens(D) initiates open.\n');
      ed.setPosition({ lineNumber: 2, column: 16 });
      ed.getSupportedActions().find((a) => /documentationForThis$/.test(a.id)).run();
    });
    const doc = await popup;
    const q = doc && new URL(doc.url()).searchParams.get('q');
    if (q !== 'variables') problems.push(`Documentation for this on a variable searched for ${q}`);
    if (doc) await doc.close();
  }

  /*  File ▸ Open with several files: a PDDL domain and its problem are one
   *  program (paired the way the example picker pairs them), and an Inform 7
   *  story opens as Logical English. Its tooltip names what the server
   *  converts. */
  {
    await page.goto(`${base}ide`, { waitUntil: 'networkidle' });
    await page.waitForSelector('.monaco-editor', { timeout: 20000 });
    await wait(1500);
    const ex = require('path').join(__dirname, '..', 'examples');
    const names = () => page.$$eval('#filetabs .ft-name', (ns) => ns.map((n) => n.textContent));
    const n0 = (await names()).length;
    await page.setInputFiles('#file-input', [`${ex}/planning/blocks-domain.pddl`, `${ex}/planning/blocks-p1.pddl`, `${ex}/if/inform/BostonCream.ni`]);
    await page.waitForFunction((n) => document.querySelectorAll('#filetabs .ft-name').length >= n + 2, n0, { timeout: 60000 }).catch(() => {});
    const ns = await names();
    if (ns.length !== n0 + 2 || !ns.includes('blocks-p1.lps') || !ns.some((n) => /^bostoncream.*\.le$/.test(n))) {
      problems.push(`File ▸ Open of a PDDL pair and an Inform story opened ${JSON.stringify(ns.slice(n0))}`);
    }
    await page.click('#menubar .menu:has-text("File")');
    await wait(300);
    const tip = await page.getAttribute('#menubar .menu:has-text("File") .item:has-text("Open…")', 'title') || '';
    if (!/\.pddl/.test(tip) || !/\.ni\b/.test(tip)) problems.push(`File ▸ Open's tooltip does not name what the server converts: ${tip}`);
    await page.keyboard.press('Escape');
    await shot(page, '13-open-several', '(File ▸ Open: a PDDL pair and an Inform story)');
  }

  /*  Logical English that is not an LPS program. The legal view this IDE
   *  opens (`the target language is: prolog.`) was compiled as LPS, and its
   *  status line said "unknown error": a refused compile's problems were in
   *  `issues`, which nothing read. Now a document for another target says
   *  what it is, with no markers; and an LPS document LPS cannot read has
   *  its problems at their lines, not one message on line 1. */
  {
    const prologDoc = 'the target language is: prolog.\n\nthe templates are:\n    *a person* may vote.\n    *a person* is an adult.\n\n'
      + 'the knowledge base voting includes:\n\na person may vote if\n    for all cases in which\n        the person is an adult\n    it is the case that\n        the person is an adult.\n\nbob is an adult.\n';
    const lpsDoc = prologDoc.replace('prolog.', 'lps.');
    const statusAndMarkers = async (name, text) => {
      await page.setInputFiles('#file-input', { name, mimeType: 'text/plain', buffer: Buffer.from(text) });
      await page.waitForFunction((n) => window.LPS?.state?.fileName === n, name, { timeout: 30000 }).catch(() => {});
      await wait(5000);                              // the analysis debounce and two round trips
      return page.evaluate(() => ({
        status: document.getElementById('status').textContent,
        markers: window.LPS.monaco.editor.getModelMarkers({ resource: window.LPS.state.editor.getModel().uri })
          .map((m) => ({ line: m.startLineNumber, severity: m.severity, message: m.message })),
      }));
    };
    const p = await statusAndMarkers('voting_prolog.le', prologDoc);
    const pErrs = p.markers.filter((m) => m.severity === 8);    // LE2's own warnings may stay
    if (!/not for LPS/.test(p.status) || pErrs.length) {
      problems.push(`a Logical English document for Prolog was analysed as LPS: status "${p.status}", ${JSON.stringify(pErrs)}`);
    }
    const l = await statusAndMarkers('voting_lps.le', lpsDoc);
    const errs = l.markers.filter((m) => m.severity === 8);
    if (/unknown error/.test(l.status) || !errs.length || errs.some((m) => m.line === 1 || /unknown error/.test(m.message))) {
      problems.push(`an LPS document LPS cannot read did not get its problems at their lines: status "${l.status}", ${JSON.stringify(errs)}`);
    }
    console.log(`  not LPS: "${p.status}"; unreadable LPS: "${l.status}", errors at line(s) ${errs.map((m) => m.line).join(', ')}`);
  }

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
