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
 * command templates; nothing here understands English.
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
      games.clear(); remember(play, null); renderPicker();
      setButtons(true);
      statusEl.textContent = `playing ${body.name}`;
      turnRange = [0, r.cycle ?? 0];
      for (const l of r.lines || []) line(l, 'story');
      syncPanes(r);
      line('Type a command, or press Commands to see what would work from here.', 'muted');
      input.focus();
    } catch (e) { statusEl.textContent = 'failed'; line(e.message, 'error'); }
  }

  async function stop() {
    if (play) { try { await api.api({ operation: 'play_stop', play }); } catch { /* gone */ } }
    play = null;
    games.clear();
    setButtons(false);
    statusEl.textContent = 'not playing';
  }

  async function turn() {
    const text = input.value.trim();
    if (!text || !play) return;
    input.value = '';
    const typed = line('> ' + text, 'typed');
    try {
      const r = await api.api({ operation: 'play_turn', play, text });
      if (!r.ok) { line(r.error, 'error'); return; }
      if (r.cycles && r.cycles.length === 2) {
        turnRange = r.cycles;
        typed.dataset.from = r.cycles[0]; typed.dataset.to = r.cycles[1];
        typed.title = `cycles ${r.cycles[0]}–${r.cycles[1]} — click to see them in the panes`;
      }
      if (r.commands) {
        //  `commands` typed in the box: the same list the button gives.
        line(r.commands.length ? 'You could:' : 'Nothing can be done from here.', 'muted');
        for (const c of r.commands) {
          const d = line('  ' + c.text, 'command');
          d.title = 'click to type it';
          d.addEventListener('click', (ev) => { ev.stopPropagation(); input.value = c.text; input.focus(); });
        }
        return;
      }
      for (const l of r.lines || []) line(l, 'story');
      syncPanes(r);
      if (r.refused && r.refused.length) line(`refused on the player's channel: ${r.refused.join(', ')}`, 'muted');
      //  The panes may follow the game's cycles later; for now the status
      //  line says where the engine is.
      if (r.cycles && r.cycles.length === 2) statusEl.textContent = `turn ${r.turn} · cycles ${r.cycles[0]}–${r.cycles[1]}`;
    } catch (e) { line(e.message, 'error'); }
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
  }
  async function show(id) {
    play = id;
    clear();
    const r = await api.api({ operation: 'play_status', play: id });
    if (!r.ok) { line(r.error, 'error'); return; }
    for (const e of r.transcript || []) {
      const cs = (e.actions || []).map((a) => a.cycle);
      turnRange = cs.length ? [Math.min(...cs), Math.max(...cs)] : null;
      if (e.typed) line('> ' + e.typed, 'typed');
      for (const l of e.lines || []) line(l, 'story');
    }
    statusEl.textContent = `${id} · turn ${r.turn}`;
    renderPicker();
    syncPanes(r);
  }
  document.getElementById('play-fork').addEventListener('click', async () => {
    if (!play) return;
    const r = await api.api({ operation: 'play_fork', play });
    if (!r.ok) { line(r.error, 'error'); return; }
    remember(r.play, r.parent);
    await show(r.play);
    line(`— forked from ${r.parent}: this is ${r.play}; type on, then Diff —`, 'muted');
    input.focus();
  });
  document.getElementById('play-diff').addEventListener('click', async () => {
    const g = games.get(play);
    if (!g || !g.parent) { line('This game was not forked; Fork first.', 'muted'); return; }
    const r = await api.api({ operation: 'play_diff', play: g.parent, other: play });
    if (!r.ok) { line(r.error, 'error'); return; }
    for (const l of r.lines || []) line(l, 'why');
  });
  picker.addEventListener('change', () => { if (picker.value && picker.value !== play) show(picker.value); });

  /*  What could be done from here. Each line is a command that would
   *  succeed now — tried on a copy of the game, so the list is as
   *  contextual as the story's constraints — and a click puts it in the
   *  input. */
  async function commands() {
    if (!play) return;
    try {
      const r = await api.api({ operation: 'play_commands', play });
      if (!r.ok) { line(r.error, 'error'); return; }
      if (!(r.commands || []).length) { line('Nothing can be done from here.', 'muted'); return; }
      line('You could:', 'muted');
      for (const c of r.commands) {
        const d = line('  ' + c.text, 'command');
        d.title = 'click to type it';
        d.addEventListener('click', (ev) => { ev.stopPropagation(); input.value = c.text; input.focus(); });
      }
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
  return { start, stop, turn, why, id: () => play };
}
