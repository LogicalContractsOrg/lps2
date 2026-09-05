/* if_demo.cjs — a narrated screen recording of interactive fiction on LPS.
 *
 * The plan is the STEPS list below: one user event per step, with what the
 * presenter says while doing it. The narration is synthesised first, one
 * file per step, so that each step can last as long as its sentence; then
 * Playwright drives the IDE and records it; then ffmpeg lays the speech on
 * the video at the moment each step began.
 *
 *   ./lps ide --port 3061 &            # with GROQ_API_KEY set, for the guessing turn
 *   ELEVEN_API_KEY=… NODE_PATH=/usr/lib/node_modules \
 *     node tools/if_demo.cjs docs/introducingIFonLPS.mp4 3061
 *
 * Keys are read from the environment and go nowhere else. The speech files
 * are cached in build/demo/ by the text they say, so a rerun that changes
 * one sentence buys one sentence.
 */
const { chromium } = require('playwright');
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const out = process.argv[2] || 'docs/introducingIFonLPS.mp4';
const port = process.argv[3] || '3061';
const ide = `http://localhost:${port}/ide`;
const work = 'build/demo';
fs.mkdirSync(work, { recursive: true });

const VOICE = '0HN93OO0QQQR6Vh2gSAe';
const KEY = process.env.ELEVEN_API_KEY;
const SIZE = { width: 1440, height: 900 };

/*  The session, one user event at a time. `say` is spoken from the moment
 *  the step starts; `do` is the event; the step ends when both are over,
 *  plus a breath. */
const STEPS = [
  { name: 'principles',
    say: 'Hello. What you see is LPS, the Logic Production System, running in a browser, and the subject today is interactive fiction: text adventures, of the kind Inform 7 is used to write. The principles are simple. A story is a document in Logical English, written on a small library that plays the part of Inform\'s standard rules: rooms, things, doors, containers, people. A turn is a burst of engine cycles. What the player types becomes an event. Reactive rules respond to it, causal laws change the state, and constraints, written as "it must not be true that", refuse what the world does not allow. Nothing here is scripted: the narration is read off the trace, and a refusal is the engine\'s own explanation of why the action did not happen. The machinery that explains a legal rule, or a robot\'s plan, is the machinery that tells the story.',
    do: async (p) => {
      await p.goto(`${ide}?example=if/alice`, { waitUntil: 'networkidle' });
      await p.waitForTimeout(2500);
    } },
  { name: 'alice source',
    say: 'This is Alice\'s Adventures in Wonderland, chapters one and two, as a story. The header says what it is for: the same choices as the book, or different ones. The logic is all in the English document. Below the header come the story\'s own commands, and a few dozen assertions: the rooms, the things, and who is where.',
    do: async (p) => {
      await p.waitForTimeout(6000);
      await scrollEditor(p, 40, 12000);
    } },
  { name: 'companion',
    say: 'The companion file holds the words: Carroll\'s narration, keyed on the actions, and a description of how the state is to be drawn. Nothing in this file changes what happens.',
    do: async (p) => {
      await p.locator('#filetabs .filetab', { hasText: 'alice.lps' }).first().click();
      await p.waitForTimeout(3000);
      await scrollEditor(p, 30, 6000);
    } },
  { name: 'start',
    say: 'I go back to the story, press Play, and start. The opening is what the rules did before the first turn, and where you are. On the right, the timeline already shows the cycles that ran.',
    do: async (p) => {
      await p.locator('#filetabs .filetab', { hasText: /^alice\.le/ }).first().click();
      await p.waitForTimeout(1500);
      await p.click('#play-toggle');
      await p.waitForTimeout(800);
      await p.click('#play-start');
      await p.waitForFunction(() => /sister/.test(document.getElementById('play-feed').textContent), { timeout: 90000 });
    } },
  { name: 'wait',
    say: 'I wait one turn. Time passes, and the White Rabbit runs by, in Carroll\'s words. That sentence is not scripted: the rabbit\'s rule fired, the action is in the trace, and the companion has a line for that action.',
    do: async (p) => {
      await type(p, 'wait', /White Rabbit/);
    } },
  { name: 'guess',
    say: 'Now I type something the parser does not know: jump down the rabbit hole. The parser is deterministic, and it gives up. But with a language-model key set, the line, and the commands the story could take right now, are shown to a model, which picks one, or none. The placeholder says: let me see if I understand. It took it as: go down. And the story accepts, or refuses, that command on its own terms, exactly as if I had typed it.',
    do: async (p) => {
      await type(p, 'jump down the rabbit hole', /I take that as|really don't understand/, 120000);
      await p.waitForTimeout(2500);
    } },
  { name: 'commands',
    say: 'The Commands button lists what would work from here. Each line was checked against the story\'s constraints on the current state, something Inform cannot do, because Inform cannot try an action without doing it. A click on one does it: I wait again, and the Rabbit hurries on.',
    do: async (p) => {
      await p.click('#play-commands');
      await p.waitForFunction(() => /You could:/.test(document.getElementById('play-feed').textContent), { timeout: 30000 });
      await p.waitForTimeout(5000);
      await p.locator('#play-feed .play-line.command', { hasText: /^\s*wait\s*$/ }).last().click();
      await p.waitForTimeout(3000);
    } },
  { name: 'timeline',
    say: 'The panes follow the game. The timeline shows which facts held in which cycles, and which events occurred. Moving the slider back marks, in the log, the turn that cycle belonged to. And a click on a turn in the log takes the slider to the end of that turn.',
    do: async (p) => {
      await p.click('#tabs button[data-pane="timeline"]');
      await p.waitForTimeout(3000);
      await p.focus('#cycle-slider');
      for (let i = 0; i < 12; i++) { await p.keyboard.press('ArrowLeft'); await p.waitForTimeout(350); }
      await p.waitForTimeout(2500);
      await p.locator('#play-feed .play-line.typed').first().click();
      await p.waitForTimeout(1500);
    } },
  { name: '2d',
    say: 'The 2D view draws the state at the current cycle, from the drawing clauses in the companion. A click on Alice takes the log to the turn in which she last changed, and says which facts changed then.',
    do: async (p) => {
      await p.click('#tabs button[data-pane="scene"]');
      await p.waitForTimeout(3500);
      await clickSubject(p, 'in(player');
      await p.waitForTimeout(2000);
    } },
  { name: 'changes',
    say: 'Changes lists what each cycle started and stopped: the state transitions, one cycle at a time, with the rule that caused each.',
    do: async (p) => {
      await p.click('#tabs button[data-pane="changes"]');
      await p.waitForTimeout(2000);
    } },
  { name: 'why',
    say: 'And Why asks the engine about the last turn: which rule fired, from which goal, in which cycle. This is the explanation facility the engine offers to any program; a story is just a program.',
    do: async (p) => {
      await p.click('#play-why');
      await p.waitForTimeout(3000);
    } },
  { name: 'iqtest',
    say: 'The second story did not start as Logical English. It is IQ Test, from Inform\'s recipe book, and this document was generated from the Inform source by the LPS front end: Inform\'s assertions became a story on the library, and its test script became the scenario.',
    do: async (p) => {
      await p.click('#play-stop');
      await p.waitForTimeout(800);
      await p.goto(`${ide}?example=if/inform/IQTest`, { waitUntil: 'networkidle' });
      await p.waitForTimeout(3000);
      await scrollEditor(p, 24, 5000);
    } },
  { name: 'original',
    say: 'Under View, the original, as Inform wrote it. The two Before rules in it, about opening the case and giving what is asked for, were not translated: the library\'s fetch plan does what they did by hand.',
    do: async (p) => {
      await p.locator('.menu-title', { hasText: /^View$/ }).first().click();
      await p.waitForTimeout(700);
      await p.getByText('The original this was converted from').first().click();
      await p.waitForTimeout(6000);
      await p.keyboard.press('Escape');
      await p.waitForTimeout(500);
    } },
  { name: 'open case',
    say: 'The generated story has the world but not the three verbs those rules supplied: the order, the giving, and eating. The hand-completed version in the examples adds them, in three lines of templates, and that is the one I play. Start. The donuts are in a locked case. Open case is refused, and the refusal comes with its reason: the case is locked.',
    do: async (p) => {
      await p.goto(`${ide}?example=if/iqtest`, { waitUntil: 'networkidle' });
      await p.waitForTimeout(2500);
      await scrollEditor(p, 16, 4000);
      await p.click('#play-toggle');
      await p.waitForTimeout(600);
      await p.click('#play-start');
      await p.waitForFunction(() => /Ogg is here/i.test(document.getElementById('play-feed').textContent), { timeout: 90000 });
      await p.waitForTimeout(1500);
      await type(p, 'open case', /the case is locked/i);
    } },
  { name: 'ask ogg',
    say: 'So I ask Ogg. An order to a character is a goal for him. He unlocks the case with the key he carries, opens it, and takes the donuts. That is a plan the engine found, not a script.',
    do: async (p) => {
      await type(p, 'og, get donuts', /Ogg (unlocks|opens|takes)/i);
      await p.waitForTimeout(1500);
    } },
  { name: 'eat',
    say: 'He gives me the donuts when asked, and I eat them. That is the end of Inform\'s own test script, reached with the same commands.',
    do: async (p) => {
      await type(p, 'og, give me the donuts', /Ogg gives/i);
      await p.waitForTimeout(1200);
      await type(p, 'eat donuts', /You eat/i);
    } },
  { name: 'close',
    say: 'That is interactive fiction on LPS: a story is a logic program, a turn is a run, and every sentence in the log can be traced to a rule. The examples, and a guide for Inform authors, are in the repository. Thank you.',
    do: async (p) => {
      await p.click('#tabs button[data-pane="timeline"]');
      await p.waitForTimeout(2000);
    } },
];

//  ---- helpers -------------------------------------------------------------

async function type(p, text, expect, timeout = 60000) {
  await p.fill('#play-input', text);
  await p.waitForTimeout(600);
  await p.press('#play-input', 'Enter');
  if (expect) {
    await p.waitForFunction((src) => {
      const lines = [...document.querySelectorAll('#play-feed .play-line:not(.typed)')].slice(-8).map((d) => d.textContent);
      return new RegExp(src, 'i').test(lines.join('\n'));
    }, expect.source, { timeout });
  }
  await p.waitForTimeout(1200);
}

//  Scroll the editor gently down to a line, then back to the top.
async function scrollEditor(p, line, ms) {
  const steps = 8;
  for (let i = 1; i <= steps; i++) {
    await p.evaluate((l) => window.LPS.state.editor.revealLineNearTop(l), Math.round(line * i / steps));
    await p.waitForTimeout(ms / (steps + 2));
  }
  await p.waitForTimeout(ms / (steps + 2));
  await p.evaluate(() => window.LPS.state.editor.revealLineNearTop(1));
}

//  A real click on a drawn object: Konva keeps its stages, the renderer
//  tags each group with the subject it stands for.
async function clickSubject(p, prefix) {
  const box = await p.evaluate((pre) => {
    const st = Konva.stages[0];
    if (!st) return null;
    const g = st.find((n) => { const s = n.getAttr('lpsSubject'); return s && String(s.term || s).startsWith(pre); })[0];
    if (!g) return null;
    const r = g.getClientRect();
    const c = st.container().getBoundingClientRect();
    return { x: c.left + r.x + r.width / 2, y: c.top + r.y + r.height / 2 };
  }, prefix);
  if (!box) { console.log('  (no drawn object for', prefix, ')'); return; }
  await p.mouse.move(box.x, box.y);
  await p.waitForTimeout(400);
  await p.mouse.click(box.x, box.y);
}

function ffprobeDuration(file) {
  return parseFloat(execFileSync('ffprobe', ['-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', file]).toString());
}

//  ---- 1. the speech --------------------------------------------------------

async function speak(step, i) {
  //  DRY=1 rehearses the actions with the sentence's expected length, no speech.
  if (process.env.DRY) return { file: null, duration: step.say.split(/\s+/).length / 2.9 };
  const h = crypto.createHash('sha1').update(VOICE + '|' + step.say).digest('hex').slice(0, 12);
  const file = path.join(work, `seg-${String(i).padStart(2, '0')}-${h}.mp3`);
  if (!fs.existsSync(file)) {
    if (!KEY) throw new Error('ELEVEN_API_KEY is not set and the speech is not cached');
    const r = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${VOICE}?output_format=mp3_44100_128`, {
      method: 'POST',
      headers: { 'xi-api-key': KEY, 'content-type': 'application/json' },
      body: JSON.stringify({ text: step.say, model_id: 'eleven_multilingual_v2',
        voice_settings: { stability: 0.6, similarity_boost: 0.75, style: 0.0 } }),
    });
    if (!r.ok) throw new Error(`elevenlabs ${r.status}: ${(await r.text()).slice(0, 300)}`);
    fs.writeFileSync(file, Buffer.from(await r.arrayBuffer()));
  }
  return { file, duration: ffprobeDuration(file) };
}

//  ---- 2. the recording -----------------------------------------------------

(async () => {
  const audio = [];
  for (let i = 0; i < STEPS.length; i++) {
    audio.push(await speak(STEPS[i], i));
    console.log(`  ${STEPS[i].name.padEnd(12)} ${audio[i].duration.toFixed(1)}s of speech`);
  }
  const spoken = audio.reduce((a, s) => a + s.duration, 0);
  console.log(`speech: ${spoken.toFixed(0)}s in ${STEPS.length} steps`);

  const browser = await chromium.launch();
  const ctx = await browser.newContext({ viewport: SIZE, recordVideo: { dir: work, size: SIZE }, deviceScaleFactor: 1 });
  const page = await ctx.newPage();
  const t0 = Date.now();
  const starts = [];
  for (let i = 0; i < STEPS.length; i++) {
    const s = STEPS[i];
    const at = (Date.now() - t0) / 1000;
    starts.push(at);
    console.log(`  ${at.toFixed(1).padStart(6)}s  ${s.name}`);
    try { await s.do(page); } catch (e) { console.log(`  !! ${s.name}: ${e.message.split('\n')[0]}`); }
    //  The step lasts at least as long as its sentence, plus a breath.
    const need = audio[i].duration + 0.9;
    const spent = (Date.now() - t0) / 1000 - at;
    if (spent < need) await page.waitForTimeout((need - spent) * 1000);
  }
  await page.waitForTimeout(1500);
  const tEnd = (Date.now() - t0) / 1000;
  const video = page.video();
  await ctx.close();
  await browser.close();
  const webm = await video.path();
  const vdur = ffprobeDuration(webm);
  console.log(`recorded ${tEnd.toFixed(1)}s, video ${vdur.toFixed(1)}s`);

  if (process.env.DRY) { console.log('dry run: no speech, no output;', webm); return; }
  //  ---- 3. speech on picture ------------------------------------------------
  //  The video clock and ours agree to within a few hundred milliseconds
  //  (recording begins when the page is created); each segment is delayed
  //  to the moment its step began, and the segments are summed.
  const inputs = ['-i', webm];
  const chains = [];
  const mix = [];
  audio.forEach((a, i) => {
    inputs.push('-i', a.file);
    const ms = Math.round(starts[i] * 1000);
    chains.push(`[${i + 1}:a]adelay=${ms}|${ms}[a${i}]`);
    mix.push(`[a${i}]`);
  });
  const filter = chains.join(';') + `;${mix.join('')}amix=inputs=${audio.length}:normalize=0:dropout_transition=0[aout]`;
  fs.mkdirSync(path.dirname(out), { recursive: true });
  execFileSync('ffmpeg', ['-y', '-hide_banner', '-loglevel', 'error', ...inputs,
    '-filter_complex', filter, '-map', '0:v', '-map', '[aout]',
    '-c:v', 'libx264', '-preset', 'medium', '-crf', '20', '-pix_fmt', 'yuv420p', '-r', '25',
    '-c:a', 'aac', '-b:a', '128k', '-movflags', '+faststart', out], { stdio: 'inherit' });
  console.log(`wrote ${out}: ${ffprobeDuration(out).toFixed(1)}s`);
})().catch((e) => { console.error(e); process.exit(1); });
