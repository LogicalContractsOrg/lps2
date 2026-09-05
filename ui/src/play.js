/* play.js — playing an interactive-fiction story in the IDE (docs/InformPlan.md
 * phase 2).
 *
 * A story is a Logical English document that includes examples/if/world.le.
 * The panel starts a game from the document on screen (and its companion, if
 * one is open), shows the transcript, and takes what a player types. A turn is
 * a burst of engine cycles run by src/edges/lps_play.pl; the words are the
 * narrator's, and a refusal is the engine's own explanation of why the action
 * did not happen. `Why?` asks about the last turn.
 *
 * The typed line goes to the parser on the server, which knows the story's
 * command templates; nothing here understands English. A line the parser
 * does not understand is offered, with the commands the story could take,
 * to a model — if the browser has a key for one — which picks one or none.
 */
export function mountPlay({ state, api, setStatus, el, tabs, setCycle, setCycleBounds, refreshPane, markPaneAvailability }) {
  const panel = document.getElementById('play');
  const statusEl = document.getElementById('play-status');
  const feed = document.getElementById('play-feed');
  const input = document.getElementById('play-input');
  let play = null;

  const setButtons = (running) => {
    panel.classList.toggle('idle', !running);
    panel.classList.toggle('running', !!running);
  };
  setButtons(false);

  //  Every line belongs to a turn, and a turn spans a range of cycles: that
  //  is what ties the transcript to the panes in both directions.
  let turnRange = null;
  const line = (text, cls) => {
    const div = el('div', { class: 'play-line ' + (cls || '') });
    //  A narration may carry several lines (a room description); keep them.
    div.textContent = text;
    if (turnRange) { div.dataset.from = turnRange[0]; div.dataset.to = turnRange[1]; }
    feed.appendChild(div);
    feed.scrollTop = feed.scrollHeight;
    return div;
  };
  /*  Every turn is numbered in the log, with the cycles it took: the badge on
   *  the typed line, or a heading for the opening, which nobody typed. */
  const badge = (div, turn, cycles) => {
    if (!cycles || cycles.length !== 2) return;
    turnRange = cycles;
    div.dataset.from = cycles[0]; div.dataset.to = cycles[1]; div.dataset.turn = turn;
    const b = el('span', { class: 'play-turn' });
    b.textContent = cycles[0] === cycles[1] ? `turn ${turn} · cycle ${cycles[0]}`
                                            : `turn ${turn} · cycles ${cycles[0]}–${cycles[1]}`;
    div.title = 'click to see this turn in the panes';
    div.appendChild(b);
  };
  const opening = (cycles) => {
    turnRange = null;
    const h = line('— the opening —', 'turnhead');
    badge(h, 0, cycles);
  };

  /*  The panes follow the game. A play reply carries the id of the game's
   *  session, registered on the server after every turn, and the last
   *  cycle it recorded; setting them as a run would makes the Timeline,
   *  Changes, Automaton and the 2D and 3D panes show the game so far, and
   *  the slider scrubs it. */
  function syncPanes(r) {
    if (!r || !r.session) return;
    state.session = r.session;
    state.maxCycle = r.cycle;
    state.lastRun = `playing ${play} · turn ${r.turn ?? ''}`;
    if (setCycleBounds) setCycleBounds();
    if (setCycle) setCycle(r.cycle);
    if (markPaneAvailability) { try { markPaneAvailability(); } catch { /* optional */ } }
    if (refreshPane) refreshPane();
  }

  /*  The other direction: a click in the Timeline (or a nudge of the slider)
   *  marks the turn that cycle fell in, and a click on a turn's line in the
   *  transcript takes the panes to the end of that turn. */
  function markCycle(c) {
    let hit = null;
    for (const d of feed.querySelectorAll('.play-line[data-from]')) {
      const inTurn = c >= Number(d.dataset.from) && c <= Number(d.dataset.to);
      d.classList.toggle('current', inTurn);
      if (inTurn && !hit) hit = d;
    }
    if (hit) hit.scrollIntoView({ block: 'nearest' });
  }
  window.addEventListener('lps-cycle', (e) => { if (play) markCycle(e.detail); });

  /*  A click on a thing in the 2D or 3D pane, while a game is on: the log
   *  goes to the turn in which that thing last changed — as of the cycle the
   *  slider is at, so scrubbing back and clicking again walks its history.
   *  The server does the looking (the trace is there); the panel marks the
   *  turn and says what changed. */
  window.addEventListener('lps-pick', async (e) => {
    const term = e.detail?.term;
    if (!play || !term) return;
    try {
      const r = await api.api({ operation: 'play_last_change', play, term: String(term), cycle: state.cycle });
      if (!r.ok) { line(r.error, 'error'); return; }
      const what = (r.things || []).join(', ');
      if (r.cycle < 0) {
        line(`Nothing about ${what} had changed by cycle ${state.cycle}.`, 'muted');
        return;
      }
      line(`${what}: last changed on turn ${r.turn}, cycle ${r.cycle}: ${(r.changed || []).join(', ')}`, 'muted');
      if (setCycle && state.session) setCycle(r.cycle); else markCycle(r.cycle);
    } catch (err) { line(err.message, 'error'); }
  });
  feed.addEventListener('click', (e) => {
    const d = e.target.closest('.play-line[data-to]');
    if (d && setCycle && state.session) setCycle(Number(d.dataset.to));
  });
  const clear = () => { while (feed.firstChild) feed.removeChild(feed.firstChild); };

  /*  The story is the document on screen — the .le tab, with its .lps
   *  companion as text, exactly as `le_compile` sends it. A tab that is not a
   *  Logical English document is not a story. */
  function storyRequest() {
    const pair = tabs.lePair();
    if (!pair) return null;
    const body = {
      operation: 'play_start', source: pair.le.model.getValue(), name: pair.le.name,
      model: document.getElementById('assistant-model')?.value || null,
      api_keys: JSON.parse(localStorage.getItem('lps.keys') || '{}'),
    };
    if (pair.lps) { body.companion = pair.lps.model.getValue(); body.companion_name = pair.lps.name; }
    return body;
  }

  async function start() {
    const body = storyRequest();
    if (!body) { setStatus('open a Logical English story (.le) to play it'); return; }
    statusEl.textContent = 'starting…';
    clear();
    try {
      const r = await api.api(body);
      if (!r.ok) {
        statusEl.textContent = 'did not compile';
        for (const d of r.diagnostics || []) line(d.message || JSON.stringify(d), 'error');
        return;
      }
      play = r.play;
      state.playing = true;
      games.clear(); remember(play, null); renderPicker();
      setButtons(true);
      statusEl.textContent = `playing ${body.name}`;
      opening([0, Math.max(0, (r.cycle ?? 1) - 1)]);
      for (const l of r.lines || []) line(l, 'story');
      syncPanes(r);
      line('Type a command, or press Commands to see what would work from here.', 'muted');
      await autoCommands();
      input.focus();
    } catch (e) { statusEl.textContent = 'failed'; line(e.message, 'error'); }
  }

  async function stop() {
    if (play) { try { await api.api({ operation: 'play_stop', play }); } catch { /* gone */ } }
    play = null;
    state.playing = false;
    games.clear();
    setButtons(false);
    statusEl.textContent = 'not playing';
  }

  //  The Commands list, as lines that do the command when clicked.
  function listCommands(cs) {
    line(cs.length ? 'You could:' : 'Nothing can be done from here.', 'muted');
    for (const c of cs) {
      const d = line('  ' + c.text, 'command');
      d.title = 'click to do it';
      d.addEventListener('click', (ev) => { ev.stopPropagation(); send(c.text); });
    }
  }

  /*  "Commands each turn": after the opening and after every turn that ran,
   *  the list of what would work from there. Remembered across sessions. */
  const auto = document.getElementById('play-auto');
  try { auto.checked = localStorage.getItem('lps.play.auto') === '1'; } catch { /* no storage */ }
  auto.addEventListener('change', () => {
    try { localStorage.setItem('lps.play.auto', auto.checked ? '1' : '0'); } catch { /* no storage */ }
    if (auto.checked && play) commands();
  });
  const autoCommands = () => { if (auto.checked && play) return commands(); };

  async function turn() {
    const text = input.value.trim();
    if (!text || !play) return;
    input.value = '';
    await send(text);
  }

  const PLACEHOLDER = input.placeholder;
  async function send(text) {
    if (!text || !play) return;
    const typed = line('> ' + text, 'typed');
    try {
      const r = await api.api({ operation: 'play_turn', play, text });
      if (!r.ok) { line(r.error, 'error'); return; }
      if (r.cycles && r.cycles.length === 2) badge(typed, r.turn, r.cycles);
      if (r.commands) { listCommands(r.commands); return; }   // `commands` typed in the box
      if (r.understood === false) { await guess(text, r); return; }
      for (const l of r.lines || []) line(l, 'story');
      syncPanes(r);
      if (r.refused && r.refused.length) line(`refused on the player's channel: ${r.refused.join(', ')}`, 'muted');
      if (r.cycles && r.cycles.length === 2) {
        statusEl.textContent = `turn ${r.turn} · cycles ${r.cycles[0]}–${r.cycles[1]}`;
        await autoCommands();
      }
    } catch (e) { line(e.message, 'error'); }
  }

  /*  The parser did not understand the line. A model — the assistant's, or
   *  the default for a key the browser holds — is shown the commands the
   *  story could take and picks one, which is then played as if typed; or
   *  none, and it says so. Without a key the parser's answer stands. The
   *  input's placeholder is the progress report, since that is where the
   *  player is looking. */
  async function guess(text, r) {
    let picked = null;
    input.placeholder = 'let me see if I understand…';
    input.disabled = true;
    try {
      const g = await api.api({ operation: 'play_guess', play, text });
      if (!g.ok) { line(g.error, 'error'); return; }
      if (!g.available) {
        for (const l of r.lines || []) line(l, 'story');
        line('(With an API key set in Misc ▸ API keys, a model would try to guess what you meant.)', 'muted');
        return;
      }
      if (g.note) line(`(${g.note})`, 'muted');
      if (!g.command) { line(g.note ? "I don't understand that." : "I really don't understand that.", 'story'); return; }
      line(`(I take that as: ${g.command})`, 'muted');
      picked = g.command;
    } finally {
      input.placeholder = PLACEHOLDER;
      input.disabled = false;
      input.focus();
    }
    if (picked) await send(picked);
  }

  async function why() {
    if (!play) return;
    try {
      const r = await api.api({ operation: 'play_why', play, question: 'last' });
      if (!r.ok) { line(r.error, 'error'); return; }
      if (!(r.lines || []).length) { line('Nothing to explain yet.', 'muted'); return; }
      for (const l of r.lines) line(l, 'why');
    } catch (e) { line(e.message, 'error'); }
  }

  /*  Forks. A session is an immutable term, so a fork is the same game under
   *  a second name; the two diverge with what is typed into each, and Diff
   *  says how. The picker switches the transcript between them. */
  const picker = document.getElementById('play-game');
  const diffBtn = document.getElementById('play-diff');
  const FORK = '__fork__';
  const games = new Map();               // id → { parent, transcript }
  function remember(id, parent) { if (!games.has(id)) games.set(id, { parent, lines: [] }); }
  function renderPicker() {
    picker.innerHTML = '';
    for (const [id, g] of games) {
      const o = document.createElement('option');
      o.value = id; o.textContent = g.parent ? `${id} (fork of ${g.parent})` : id;
      if (id === play) o.selected = true;
      picker.appendChild(o);
    }
    //  The last item is not a game but the way to make one.
    const f = document.createElement('option');
    f.value = FORK; f.textContent = 'Fork this game…';
    picker.appendChild(f);
    picker.value = play;
    //  Diff compares a fork with its parent; there is nothing to compare otherwise.
    const forked = !!games.get(play)?.parent;
    diffBtn.disabled = !forked;
    diffBtn.title = forked ? `What happened in ${play} and not in ${games.get(play).parent}, the game it was forked from`
                           : 'Diff compares a fork with the game it was forked from: choose “Fork this game…” in the picker first';
  }
  async function show(id) {
    play = id;
    clear();
    const r = await api.api({ operation: 'play_status', play: id });
    if (!r.ok) { line(r.error, 'error'); return; }
    state.playing = true;
    for (const e of r.transcript || []) {
      if (e.typed) badge(line('> ' + e.typed, 'typed'), e.turn, e.cycles);
      else opening(e.cycles);
      for (const l of e.lines || []) line(l, 'story');
    }
    statusEl.textContent = `${id} · turn ${r.turn}`;
    renderPicker();
    syncPanes(r);
  }
  async function fork() {
    if (!play) return;
    const r = await api.api({ operation: 'play_fork', play });
    if (!r.ok) { line(r.error, 'error'); return; }
    remember(r.play, r.parent);
    await show(r.play);
    line(`— forked from ${r.parent}: this is ${r.play}; type on, then Diff —`, 'muted');
    input.focus();
  }
  diffBtn.addEventListener('click', async () => {
    const g = games.get(play);
    if (!g || !g.parent) { line('This game was not forked; choose “Fork this game…” in the picker first.', 'muted'); return; }
    const r = await api.api({ operation: 'play_diff', play: g.parent, other: play });
    if (!r.ok) { line(r.error, 'error'); return; }
    for (const l of r.lines || []) line(l, 'why');
  });
  picker.addEventListener('change', () => {
    if (picker.value === FORK) { picker.value = play; fork(); return; }
    if (picker.value && picker.value !== play) show(picker.value);
  });

  /*  What could be done from here. Each line is a command that would
   *  succeed now — judged against the story's own constraints — and a
   *  click on one does it, as if typed. */
  async function commands() {
    if (!play) return;
    try {
      const r = await api.api({ operation: 'play_commands', play });
      if (!r.ok) { line(r.error, 'error'); return; }
      listCommands(r.commands || []);
    } catch (e) { line(e.message, 'error'); }
  }
  document.getElementById('play-commands').addEventListener('click', commands);

  document.getElementById('play-start').addEventListener('click', start);
  document.getElementById('play-restart').addEventListener('click', async () => { await stop(); await start(); });
  document.getElementById('play-stop').addEventListener('click', stop);
  document.getElementById('play-send').addEventListener('click', turn);
  document.getElementById('play-why').addEventListener('click', why);
  input.addEventListener('keydown', (e) => { if (e.key === 'Enter') turn(); });

  const toggle = document.getElementById('play-toggle');
  const startBtn = document.getElementById('play-start');
  toggle.addEventListener('click', () => {
    if (toggle.disabled) return;
    panel.classList.toggle('collapsed');
    window.dispatchEvent(new Event('lps-dock'));
    if (!panel.classList.contains('collapsed') && play) input.focus();
  });

  /*  Play is for a story, and a story is a Logical English document that
   *  includes the interactive-fiction library. Anything else — an LPS
   *  program, a Logical English document about loans — has no commands for
   *  a player to type, so the button is off and its tooltip says why. The
   *  test is textual and cheap: `includes these resources:` naming `world`
   *  in the document on screen (or the .le half of its pair). */
  const STORY_TIP = 'Open the play panel: play this Logical English story as interactive fiction';
  const NOT_STORY_TIP = 'Play needs a story: a Logical English document that includes the '
    + 'interactive-fiction library with “includes these resources: world” (see examples/if/). '
    + 'The document on screen does not.';
  function isStory() {
    const pair = tabs.lePair();
    if (!pair) return false;
    return /includes\s+these\s+resources\s*:[^.]*\bworld\b/.test(pair.le.model.getValue());
  }
  function refreshToggle() {
    const ok = isStory();
    toggle.disabled = !ok;
    toggle.title = ok ? STORY_TIP : NOT_STORY_TIP;
    startBtn.disabled = !ok;
    startBtn.title = ok ? 'Start playing the Logical English story in the editor' : NOT_STORY_TIP;
  }
  refreshToggle();
  window.addEventListener('lps-profile', refreshToggle);
  window.addEventListener('lps-dock', refreshToggle);
  state.editor.onDidChangeModel(refreshToggle);
  let pending = null;
  state.editor.onDidChangeModelContent(() => {
    clearTimeout(pending);
    pending = setTimeout(refreshToggle, 400);
  });

  //  For the browser check and for anyone driving the IDE from the console.
  //  `open` shows the panel and starts the story: the "Nothing has been run
  //  yet" page offers it for a story, beside Run.
  async function open() {
    if (panel.classList.contains('collapsed')) toggle.click();
    if (!play) await start();
    input.focus();
  }
  return { start, stop, turn, send, why, fork, open, isStory, id: () => play };
}
