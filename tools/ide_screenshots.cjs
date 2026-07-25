/* ide_screenshots.cjs — drive the IDE in a real browser and photograph it.
 *
 * §I.10 asks for an IDE; a page that has never been rendered is not one. This
 * walks the four panes with Playwright, captures a screenshot of each, and —
 * more usefully than the pictures — fails loudly on any console error, page
 * error or failed request, so that a pane which silently renders nothing is
 * caught rather than admired.
 *
 *   ./lps ide --port 3060 &
 *   NODE_PATH=/usr/lib/node_modules node tools/ide_screenshots.cjs [outdir] [port]
 */
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const OUT = process.argv[2] || 'build/ide-shots';
const PORT = process.argv[3] || 3060;
const BASE = `http://localhost:${PORT}/`;

const problems = [];

const shot = async (page, name, note) => {
  fs.mkdirSync(OUT, { recursive: true });
  const file = path.join(OUT, name + '.png');
  await page.screenshot({ path: file, fullPage: false });
  console.log(`  ${name}.png  ${note || ''}`);
  return file;
};

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1400, height: 900 } });

  page.on('console', m => {
    if (m.type() === 'error') problems.push(`console: ${m.text()}`);
  });
  page.on('pageerror', e => problems.push(`pageerror: ${e.message}`));
  page.on('requestfailed', r => {
    // External image URLs in display/2 clauses will not load offline; that is
    // the corpus's link rot, not the page's problem.
    if (!r.url().startsWith(BASE)) return;
    problems.push(`request failed: ${r.url()} ${r.failure()?.errorText}`);
  });

  console.log(`\n=== ${BASE} ===`);
  await page.goto(BASE, { waitUntil: 'networkidle' });
  console.log('title:', await page.title());
  await shot(page, '01-initial', '(declarative goat preloaded, analysed)');

  // --- compile and run -------------------------------------------------
  await page.click('#run');
  await page.waitForFunction(() => /cycles/.test(document.getElementById('status').textContent),
                             null, { timeout: 30000 });
  console.log('status:', await page.textContent('#status'));
  console.log('analysis:', await page.textContent('#analysis'));
  await page.waitForTimeout(400);
  await shot(page, '02-timeline', '(§I.10.2)');

  const lanes = await page.locator('#pane-timeline svg rect').count();
  const labels = await page.locator('#pane-timeline svg text').count();
  console.log(`timeline: ${lanes} interval bars, ${labels} labels`);
  if (lanes === 0) problems.push('timeline drew no intervals');

  // --- scrub, and watch the cursor move --------------------------------
  const cursorX = () => page.getAttribute('#cursor', 'x1');
  const x0 = await cursorX();
  await page.fill('#cycle', '5');
  await page.dispatchEvent('#cycle', 'input');
  await page.waitForTimeout(200);
  const x5 = await cursorX();
  console.log(`cursor at cycle 0: x=${x0}, at cycle 5: x=${x5}`);
  if (x0 === x5) problems.push('the timeline cursor did not move when scrubbing');
  await shot(page, '03-timeline-scrubbed', '(cursor at cycle 5)');

  // --- state changes ----------------------------------------------------
  await page.click('.tabs button[data-pane="changes"]');
  await page.waitForTimeout(600);
  const rows = await page.locator('#pane-changes table tr').count();
  console.log(`state changes at cycle 5: ${rows - 1} change rows`);
  await shot(page, '04-changes', '(§I.10.3, with the causal law)');
  if (rows <= 1) problems.push('state-change pane drew no rows');

  // --- the state-transitions automaton (godfa/1) ------------------------
  await page.click('.tabs button[data-pane="automaton"]');
  await page.waitForTimeout(900);
  const dfaNodes = await page.locator('#pane-automaton svg rect').count();
  const dfaEdges = await page.locator('#pane-automaton svg path[marker-end]').count();
  console.log(`state transitions: ${dfaNodes} states, ${dfaEdges} transitions`);
  await shot(page, '04b-automaton', '(the run as a finite automaton)');
  if (dfaNodes === 0) problems.push('state-transitions pane drew no states');
  if (dfaEdges === 0) problems.push('state-transitions pane drew no transitions');
  const bold = await page.locator('#pane-automaton svg rect[stroke-width="3"]').count();
  if (bold !== 1) problems.push(`expected exactly one initial state, marked; found ${bold}`);

  // --- explanations -----------------------------------------------------
  await page.click('.tabs button[data-pane="explain"]');
  await page.fill('#question', 'why(happened(row(south,north)), 2)');
  await page.click('#ask');
  await page.waitForSelector('#answer .verdict', { timeout: 20000 });
  console.log('verdict:', await page.textContent('#answer .verdict'));
  const nodes = await page.locator('#answer li').count();
  console.log(`explanation tree: ${nodes} nodes`);
  await shot(page, '05-explain', '(§I.10.5)');
  if (nodes < 2) problems.push('explanation tree has no children');
  const chain = await page.textContent('#answer');
  if (!/planner|reactive rule/.test(chain))
    problems.push('explanation names neither a rule nor the planner');

  await page.fill('#question', 'why_not(happened(transport(wolf,south,north)), 2)');
  await page.click('#ask');
  await page.waitForTimeout(1200);
  console.log('why_not verdict:', await page.textContent('#answer .verdict'));
  await shot(page, '06-why-not', '(the hard question form)');

  // --- animation, on a program that has a visual mapping ---------------
  const badlight = fs.readFileSync('legacy_lps1/examples/CLOUT_workshop/badlight.pl', 'utf8');
  await page.fill('#src', badlight);
  await page.click('#run');
  await page.waitForFunction(() => /cycles/.test(document.getElementById('status').textContent),
                             null, { timeout: 30000 });
  console.log('badlight:', await page.textContent('#status'));
  await page.click('.tabs button[data-pane="scene"]');
  await page.fill('#cycle', '4');
  await page.dispatchEvent('#cycle', 'input');
  await page.waitForTimeout(900);
  const shapes = await page.locator('#pane-scene svg > *').count();
  console.log(`scene at cycle 4: ${shapes} top-level shapes`);
  await shot(page, '07-animation', '(§I.10.4, badlight.pl)');
  if (shapes === 0) problems.push('animation pane drew nothing for a program with display/2');

  await page.fill('#cycle', '8');
  await page.dispatchEvent('#cycle', 'input');
  await page.waitForTimeout(900);
  await shot(page, '08-animation-later', '(same program, cycle 8)');

  // --- diagnostics on a broken program ---------------------------------
  await page.fill('#src', 'maxTime(4).\nfluents on.\nachieve on.\n');
  await page.waitForTimeout(2200);           // the 1500 ms debounce, plus slack
  const diagText = await page.textContent('#diags');
  console.log('diagnostics:', diagText.trim().slice(0, 120));
  await shot(page, '09-diagnostics', '(debounced analysis, §I.10.1)');
  if (!/achieve_without_planning_mode/.test(diagText))
    problems.push('the debounced analysis did not report the expected diagnostic');

  // --- dark mode --------------------------------------------------------
  await page.emulateMedia({ colorScheme: 'dark' });
  // The automaton on a program that revisits states: bankTransfer's two
  // accounts pass money back and forth, so the diagram is a cycle rather than
  // a chain -- which is the whole reason this diagram exists.
  const bank = fs.readFileSync('legacy_lps1/examples/CLOUT_workshop/bankTransfer.pl', 'utf8');
  await page.fill('#src', bank);
  await page.click('#run');
  await page.waitForFunction(() => /cycles/.test(document.getElementById('status').textContent),
                             null, { timeout: 30000 });
  await page.click('.tabs button[data-pane="automaton"]');
  await page.waitForTimeout(900);
  const bankStates = await page.locator('#pane-automaton svg rect').count();
  console.log(`bankTransfer automaton: ${bankStates} states`);
  await shot(page, '09-automaton-bank', '(recurring states collapse into one node)');
  if (bankStates < 3) problems.push('bankTransfer automaton has too few states');
  await page.check('#absnum');
  await page.waitForTimeout(900);
  await shot(page, '10-automaton-abstract', '(with numbers abstracted)');
  await page.uncheck('#absnum');

  await page.click('.tabs button[data-pane="timeline"]');
  await page.waitForTimeout(300);
  await shot(page, '10-dark', '(prefers-color-scheme: dark)');

  await browser.close();

  console.log('');
  if (problems.length) {
    console.log('PROBLEMS:');
    for (const p of problems) console.log('  ' + p);
    process.exit(1);
  }
  console.log('no console errors, no page errors, every pane drew something.');
})().catch(e => { console.error('FAILED:', e.message); process.exit(1); });
