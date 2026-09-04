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
export function mountPlay({ state, api, setStatus, el, tabs }) {
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

  const line = (text, cls) => {
    const div = el('div', { class: 'play-line ' + (cls || '') });
    //  A narration may carry several lines (a room description); keep them.
    div.textContent = text;
    feed.appendChild(div);
    feed.scrollTop = feed.scrollHeight;
    return div;
  };
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
      for (const l of r.lines || []) line(l, 'story');
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
    line('> ' + text, 'typed');
    try {
      const r = await api.api({ operation: 'play_turn', play, text });
      if (!r.ok) { line(r.error, 'error'); return; }
      for (const l of r.lines || []) line(l, 'story');
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
      if (e.typed) line('> ' + e.typed, 'typed');
      for (const l of e.lines || []) line(l, 'story');
    }
    statusEl.textContent = `${id} · turn ${r.turn}`;
    renderPicker();
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
