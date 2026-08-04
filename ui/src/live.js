/* live.js — perpetual sessions in the IDE (M18, §II.0).
 *
 * A finite run is a trace you read afterwards. A *live* session is a program
 * that keeps cycling and takes events from outside while it does — which is
 * what an agent is, and what the old engine could do with `go(F,[background(T)])`
 * plus `inject_events/3`.
 *
 * The panel gives it: start, pause, resume, stop; a form to inject a precise
 * event; a natural-language box that asks the assistant to turn a sentence into
 * one of the program's declared events (and shows you the term before it is
 * sent, because a mistranslated event is an event you did not mean); and a
 * button to open the 2D or 3D animation in its own window, following the live
 * session rather than a slider.
 */
export function mountLive({ state, api, setStatus, el }) {
  const panel = document.getElementById('live');
  const statusEl = document.getElementById('live-status');
  const evInput = document.getElementById('live-event');
  const nlInput = document.getElementById('live-nl');
  const feed = document.getElementById('live-feed');
  let live = null, timer = null;

  const setButtons = (running, paused) => {
    document.getElementById('live-start').disabled = !!running;
    document.getElementById('live-pause').disabled = !running || paused;
    document.getElementById('live-resume').disabled = !running || !paused;
    document.getElementById('live-stop').disabled = !running;
    document.getElementById('live-send').disabled = !running;
    document.getElementById('live-nl-send').disabled = !running;
    setViewButtons(running);
  };

  /*  The 2D and 3D buttons open a window that draws whatever `display/2` and
   *  `display3d/2` say. A program with neither draws nothing, and an empty
   *  window is a worse answer than a disabled button that says why. */
  function setViewButtons(running) {
    const prof = state.profile || {};
    for (const [id, key, decl] of [['live-2d', 'display', 'display/2'],
                                   ['live-3d', 'display3d', 'display3d/2']]) {
      const b = document.getElementById(id);
      const has = !!prof[key];
      b.disabled = !running || !has;
      b.title = has
        ? `Open a live ${id.endsWith('2d') ? '2D' : '3D'} view in its own window`
        : `This program has no ${decl} clauses, so there is nothing to draw. `
          + 'Write some, or ask the assistant to.';
    }
  }
  window.addEventListener('lps-profile', () => setViewButtons(!!live));
  setButtons(false, false);

  /*  The placeholder is one of *this* program's events. `payment(alice, 100)`
   *  was a hint about a program the user is not looking at. */
  function setHints() {
    const evs = state.profile?.events || [];
    evInput.placeholder = evs.length
      ? `event term, e.g. ${evs[0]}`
      : 'this program declares no events — nothing to send';
    evInput.disabled = !live || !evs.length;
    nlInput.placeholder = evs.length
      ? '…or say it in English, and the assistant will pick the term'
      : '…or say it in English: “alice pays a hundred”';

    /*  Every event the program declares, as a menu. Typing a term from memory
     *  is fine once you know the program; picking one is what you want the
     *  first time, and it is also the only way to *discover* that a program
     *  takes mouse events at all. */
    const pick = document.getElementById('live-event-pick');
    if (!pick) return;
    const mouse = evs.filter((e) => /^lps_mouse/.test(e));
    pick.replaceChildren(el('option', { value: '', text: evs.length ? 'pick an event…' : 'no events' }),
      ...evs.map((e) => el('option', { value: e, text: e })));
    pick.disabled = !evs.length;
    pick.title = mouse.length
      ? `this program handles ${mouse.join(', ')} — clicks in a live 2D or 3D window arrive as those`
      : 'this program handles no mouse events, so clicking its animation does nothing';
  }
  window.addEventListener('lps-profile', setHints);

  /*  The feed, and a copy of it. The panel keeps 400 lines on screen; `log`
   *  keeps the lot, because "what happened in that session" is a question
   *  asked after the session, and a live session is otherwise unrepeatable. */
  const log = [];
  const note = (text, cls) => {
    log.push(text);
    feed.appendChild(el('div', { class: 'live-line ' + (cls || ''), text }));
    while (feed.childElementCount > 400) feed.firstChild.remove();
    feed.scrollTop = feed.scrollHeight;
  };

  async function start() {
    try {
      //  A live session runs until it is stopped. A program that declares
      //  maxTime ends on its own, and then sits there "running" and doing
      //  nothing, which looks like a hang. Say so once, and start anyway —
      //  watching a finite program tick past its end is a legitimate thing to
      //  want, and refusing would be the tool deciding.
      const mt = state.profile?.max_time;
      if (mt != null) {
        note(`this program declares maxTime(${mt}); it will stop by itself at cycle ${mt} `
             + 'and the session will end. Remove maxTime for a session that keeps going.', 'warn');
      }
      const c = await api.compile(state.editor.getValue(), 'legacy');
      const r = await api.api({
        operation: 'live_start',
        program: c.program,
        cycle_ms: Number(document.getElementById('live-rate').value) || 500,
      });
      live = r.live;
      state.live = live;
      setButtons(true, false);
      setHints();
      note(`started ${live}`, 'ok');
      timer = setInterval(tick, 700);
    } catch (e) { note(e.message, 'error'); }
  }

  async function tick() {
    if (!live) return;
    try {
      const r = await api.api({ operation: 'live_status', live });
      //  Elapsed time and the rate actually achieved against the one asked
      //  for: a session that cannot keep up should say so rather than look
      //  slow for no reason.
      const want = Number(document.getElementById('live-rate').value) || 500;
      const got = r.rate ? (1000 / r.rate) : null;
      const lag = got && got > want * 1.35 ? `  ·  ${Math.round(got)} ms/cycle, asked for ${want}` : '';
      const secs = r.elapsed ? `  ·  ${r.elapsed < 60 ? r.elapsed.toFixed(0) + ' s' : (r.elapsed / 60).toFixed(1) + ' min'}` : '';
      statusEl.textContent = `cycle ${r.cycle} · ${r.status}${r.paused ? ' · paused' : ''}${secs}${lag}`;
      //  Pause may have come from the pop-out window rather than this panel.
      if (r.status === 'running') setButtons(true, !!r.paused);
      for (const line of r.recent || []) note(line);
      if (r.status !== 'running') { stopPolling(); setButtons(false, false); }
      window.dispatchEvent(new CustomEvent('lps-live-tick', { detail: r }));
    } catch (e) {
      note(e.message, 'error');
      stopPolling();
    }
  }

  function stopPolling() { clearInterval(timer); timer = null; }

  async function command(op, extra) {
    if (!live) return;
    try {
      const r = await api.api({ operation: op, live, ...(extra || {}) });
      if (op === 'live_stop') { stopPolling(); live = null; state.live = null; setButtons(false, false); note('stopped'); }
      if (op === 'live_pause') setButtons(true, true);
      if (op === 'live_resume') setButtons(true, false);
      return r;
    } catch (e) { note(e.message, 'error'); }
  }

  document.getElementById('live-start').addEventListener('click', start);
  document.getElementById('live-pause').addEventListener('click', () => command('live_pause'));
  document.getElementById('live-resume').addEventListener('click', () => command('live_resume'));
  document.getElementById('live-stop').addEventListener('click', () => command('live_stop'));

  document.getElementById('live-send').addEventListener('click', async () => {
    const t = evInput.value.trim();
    if (!t) return;
    const r = await command('live_observe', { events: [t] });
    if (r) { note(`→ ${t}`, 'sent'); evInput.value = ''; }
  });
  evInput.addEventListener('keydown', (e) => { if (e.key === 'Enter') document.getElementById('live-send').click(); });

  //  Natural language → an event term, via the assistant. Shown, not sent:
  //  the user confirms. An agent that acts on a mistranslated observation is
  //  the failure mode this whole design is meant to make impossible.
  document.getElementById('live-nl-send').addEventListener('click', async () => {
    const t = nlInput.value.trim();
    if (!t || !live) return;
    note(`“${t}” …`, 'muted');
    try {
      const r = await api.api({
        operation: 'live_translate', live, text: t,
        model: document.getElementById('assistant-model')?.value || null,
        api_keys: JSON.parse(localStorage.getItem('lps.keys') || '{}'),
      });
      if (!r.events || !r.events.length) { note('no event matched that', 'error'); return; }
      const row = el('div', { class: 'live-line proposal' },
        el('span', { text: r.events.join(', ') }),
        el('button', {
          text: 'send', onclick: async () => {
            await command('live_observe', { events: r.events });
            note(`→ ${r.events.join(', ')}`, 'sent');
            row.remove();
          },
        }),
        el('button', { text: 'discard', onclick: () => row.remove() }));
      feed.appendChild(row);
      feed.scrollTop = feed.scrollHeight;
      nlInput.value = '';
    } catch (e) { note(e.message, 'error'); }
  });

  document.getElementById('live-event-pick').addEventListener('change', (e) => {
    if (!e.target.value) return;
    //  Filled in, not sent: the arguments are the user's to write.
    evInput.value = e.target.value;
    evInput.focus();
    const i = evInput.value.indexOf('(');
    if (i > 0) evInput.setSelectionRange(i + 1, evInput.value.length - 1);
    e.target.value = '';
  });

  document.getElementById('live-verbose').addEventListener('change', (e) => {
    command('live_verbose', { verbose: e.target.checked });
  });

  document.getElementById('live-save').addEventListener('click', () => {
    const a = document.createElement('a');
    a.href = URL.createObjectURL(new Blob([log.join('\n') + '\n'], { type: 'text/plain' }));
    a.download = (state.fileName || 'session').replace(/\.\w+$/, '') + '-live.log';
    a.click();
  });

  document.getElementById('live-2d').addEventListener('click', () => openViewer('2d'));
  document.getElementById('live-3d').addEventListener('click', () => openViewer('3d'));

  function openViewer(kind) {
    if (!live) return;
    const u = new URL('./live-view.html', location.href);
    u.searchParams.set('live', live);
    u.searchParams.set('kind', kind);
    window.open(u.toString(), 'lps-live-' + kind, 'width=760,height=620');
  }

  window.addEventListener('lps-observe', (e) => {
    if (!live) { setStatus('start a live session first'); return; }
    evInput.value = e.detail;
    document.getElementById('live-send').click();
  });

  document.getElementById('live-toggle').addEventListener('click', () => {
    panel.classList.toggle('collapsed');
    window.dispatchEvent(new Event('lps-dock'));
  });
}
