/* assistant.js — the LPS Assistant panel (M16).
 *
 * Docked beside the editor rather than in the pane strip, because it is about
 * the *program* and not about the run. The protocol is LE2's: a job id, a
 * poll, a progress tail, a cooperative interrupt, and a final
 * `{explanation, new_content}` the editor can apply — so the two assistants
 * behave the same way even though they share no code.
 *
 * The two canned prompts are buttons, not typed requests: the user sees
 * "Animate in 2D", the prompt behind it is ours (src/edges/lps_assistant.pl)
 * and includes the icon catalogue, so the model picks a real icon by
 * description rather than inventing a URL.
 */
import { iconCatalogueText } from './icons.js';

const PROVIDERS = [
  { id: 'anthropic', label: 'Anthropic', env: 'ANTHROPIC_API_KEY' },
  { id: 'openai', label: 'OpenAI', env: 'OPENAI_API_KEY' },
  { id: 'gemini', label: 'Google Gemini', env: 'GEMINI_API_KEY' },
  { id: 'groq', label: 'Groq', env: 'GROQ_API_KEY' },
  { id: 'together', label: 'Together', env: 'TOGETHER_API_KEY' },
];

export function mountAssistant({ state, api, setStatus, openDialog, closeDialog, el }) {
  const panel = document.getElementById('assistant');
  const log = document.getElementById('assistant-log');
  const input = document.getElementById('assistant-input');
  const send = document.getElementById('assistant-send');
  const stop = document.getElementById('assistant-stop');
  const modelSel = document.getElementById('assistant-model');
  let job = null, polling = null;

  const keys = () => { try { return JSON.parse(localStorage.getItem('lps.keys') || '{}'); } catch { return {}; } };
  const saveKeys = (k) => localStorage.setItem('lps.keys', JSON.stringify(k));

  const say = (who, text, cls) => {
    const d = el('div', { class: 'msg ' + (cls || who) },
      el('span', { class: 'who', text: who }), el('div', { class: 'body', text }));
    log.appendChild(d);
    log.scrollTop = log.scrollHeight;
    return d;
  };

  let MODELS = [];

  /*  The list is the server's, and it is the *live* one: `assistant_models`
   *  asks each provider whose key is present what it actually offers, so a
   *  model that has been retired stops being offered and a new one appears
   *  without a release here. The reply is cached on the server (it is a
   *  network call per provider), so asking twice is cheap. */
  async function loadModels() {
    try {
      const r = await api.api({ operation: 'assistant_models', api_keys: keys() });
      MODELS = r.models || [];
      fillModelSelect(modelSel);
      showKeyState();
    } catch {
      MODELS = [];
      showKeyState();
    }
  }

  /*  With no key there is nothing this panel can do, and the honest way to say
   *  so is one sentence and the button that fixes it. It used to say it with a
   *  dropdown reading "no models" beside two buttons that could not work and
   *  the words "no API key" — four controls to convey one fact — and it also
   *  wrote the same complaint into the top bar's status, where it displaced
   *  the result of the run and had nothing to do with the program. */
  function showKeyState() {
    panel.classList.toggle('unconfigured', !MODELS.length);
    const provs = [...new Set(MODELS.map((m) => m.provider))];
    const head = document.querySelector('#assistant .dock-head');
    let tag = document.getElementById('assistant-provider');
    if (!tag && head) {
      tag = el('span', { id: 'assistant-provider', class: 'muted' });
      head.insertBefore(tag, head.querySelector('.spacer'));
    }
    if (tag) {
      //  Which provider is actually answering. "No models" and "a key that is
      //  not working" look identical from here otherwise.
      tag.textContent = provs.length ? `key: ${provs.join(', ')}` : '';
      tag.title = 'the providers whose key the server or this browser has';
    }
    let no = document.getElementById('assistant-nokey');
    if (!no && head) {
      no = el('span', { id: 'assistant-nokey' },
        el('span', { text: 'This needs a key from an LLM provider.' }),
        el('button', {
          text: 'Set one',
          onclick: () => window.dispatchEvent(new Event('lps-open-settings')),
        }));
      head.insertBefore(no, head.querySelector('.spacer'));
    }
  }

  function fillModelSelect(sel) {
    if (!MODELS.length) { sel.replaceChildren(el('option', { text: 'no models' })); return; }
    /*  Known-good first, under their own heading.
     *
     *  The list is in name order, which put `allam-2-7b` at the top — a real
     *  model with a 4096-token limit that this assistant's own prompt exceeds.
     *  Alphabetical is the right order *within* a group and the wrong one for
     *  the whole list: the first thing offered should be something that works.  */
    const curated = MODELS.filter((m) => m.curated);
    const rest = MODELS.filter((m) => !m.curated);
    /*  A model that cannot hold the assistant's own prompt should say so in
     *  the list, not after being chosen. Most of what Groq hosts is an
     *  8,192-token model, and the only way to discover that used to be to
     *  pick one and read the provider's arithmetic back. `window` is 0 for a
     *  provider that does not report it, which is not a claim of any kind. */
    const SMALL = 16384;
    const group = (label, ms, title) => {
      if (!ms.length) return null;
      const g = el('optgroup');
      g.label = label;
      for (const m of ms) {
        const tight = m.window > 0 && m.window < SMALL;
        g.appendChild(el('option', {
          value: m.name,
          text: `${m.name}  (${m.provider})${tight ? `  · ${Math.round(m.window / 1024)}k — may be too small` : ''}`,
          title: tight
            ? `${m.name} can be told about ${m.window} tokens at once. A program of any size plus the icon catalogue may not fit.`
            : title,
        }));
      }
      return g;
    };
    const byProvider = new Map();
    for (const m of rest) {
      if (!byProvider.has(m.provider)) byProvider.set(m.provider, []);
      byProvider.get(m.provider).push(m);
    }
    sel.replaceChildren(...[
      group('known to work with this assistant', curated, 'named in lps_llm.pl’s table'),
      ...[...byProvider.entries()].map(([prov, ms]) => group(prov + ' — everything else', ms,
        'from the provider’s own catalogue, offered because it is there')),
    ].filter(Boolean));
    const saved = localStorage.getItem('lps.model');
    if (saved && MODELS.some((m) => m.name === saved)) sel.value = saved;
    else {
      const first = MODELS.find((m) => m.curated) || MODELS[0];
      if (first) sel.value = first.name;
    }
  }

  modelSel.addEventListener('change', () => localStorage.setItem('lps.model', modelSel.value));

  const expand = () => {
    if (!panel.classList.contains('collapsed')) return;
    panel.classList.remove('collapsed');
    window.dispatchEvent(new Event('lps-dock'));
  };

  /*  Who asked. A request started from a scene pane reports back to it, so the
   *  progress appears where the click was rather than only down here — see
   *  panes/shared.js. `null` for a typed question, which has nowhere else to
   *  go. */
  let asker = null;
  const announce = (kind, detail) => {
    if (!asker) return;
    if (kind === 'busy') window.LPS_ASSISTANT_BUSY = asker;
    else window.LPS_ASSISTANT_BUSY = null;
    window.dispatchEvent(new CustomEvent('lps-assistant-' + kind,
      { detail: { what: asker, ...detail } }));
    if (kind === 'done') asker = null;
  };

  async function submit(command, hidden) {
    if (job) return;
    if (!hidden) say('you', command);
    const thinking = say('assistant', '…', 'thinking');
    send.disabled = true; stop.style.display = '';
    announce('busy', { text: 'Asking the assistant to plan a scene for this program…' });
    try {
      const r = await api.api({
        operation: 'assistant_command',
        command,
        content: state.editor.getValue(),
        model: modelSel.value || null,
        api_keys: keys(),
        icons: iconCatalogueText(),
      });
      job = r.job;
      polling = setInterval(() => poll(thinking), 900);
    } catch (e) {
      thinking.remove();
      say('assistant', e.message, 'error');
      send.disabled = false; stop.style.display = 'none';
      announce('done', { error: e.message });
    }
  }

  async function poll(thinking) {
    if (!job) return;
    try {
      const r = await api.api({ operation: 'assistant_status', job });
      thinking.querySelector('.body').textContent =
        (r.output || []).slice(-6).join('\n') || '…';
      if (r.status === 'running') {
        const step = (r.output || []).slice(-1)[0];
        if (step && step !== '…') announce('busy', { text: `The assistant is working — ${step}` });
        return;
      }
      clearInterval(polling); polling = null; job = null;
      send.disabled = false; stop.style.display = 'none';
      thinking.classList.remove('thinking');
      thinking.querySelector('.body').textContent = r.explanation || r.error || '(no answer)';
      if (r.error) announce('done', { error: r.error });
      else if (!r.new_content) announce('done', {});
      if (r.new_content && r.new_content !== state.editor.getValue()) {
        const apply = el('button', { class: 'apply primary', text: 'Apply to editor' });
        apply.addEventListener('click', () => {
          state.editor.executeEdits('assistant', [{
            range: state.editor.getModel().getFullModelRange(),
            text: r.new_content,
          }]);
          apply.remove();
          preview.remove();
          setStatus('assistant edit applied — undo with Ctrl/Cmd+Z');
          /*  And run it, if the request came from a pane that is waiting for a
           *  picture. The buffer now genuinely contains `display/2`, and the 2D
           *  pane went on saying "this program declares no display/2 clauses"
           *  until the user found Run for themselves — a pane contradicting the
           *  file for as long as it took to notice. */
          if (asker) {
            const who = asker;
            announce('busy', { text: 'Running the program to draw the new scene…' });
            window.dispatchEvent(new CustomEvent('lps-assistant-applied', { detail: { what: who } }));
          } else {
            announce('done', {});
          }
        });
        /*  What the edit *is*, before it happens. For an animation request that
         *  is the display clauses themselves, which are the whole answer and
         *  are otherwise invisible until the buffer has already changed. */
        //  Its own class, not `apply`: `button.apply` is what the screenshot
        //  script and anything else scripting the panel presses to accept an
        //  edit, and a second button answering to that name opens a dialog
        //  where an edit was expected.
        const preview = el('button', { class: 'preview', text: 'Show the change' });
        preview.addEventListener('click', () => {
          const before = state.editor.getValue().split('\n');
          const after = r.new_content.split('\n');
          const added = after.filter((l) => l.trim() && !before.includes(l));
          const gone = before.filter((l) => l.trim() && !after.includes(l));
          openDialog('What the assistant would change',
            el('div', { class: 'rundiff' },
              el('p', { class: 'muted', text: `${added.length} line(s) added, ${gone.length} removed` }),
              el('pre', { class: 'internal', text: added.join('\n') || '(nothing added)' }),
              ...(gone.length ? [el('p', { class: 'muted', text: 'removed:' }),
                el('pre', { class: 'internal', text: gone.join('\n') })] : [])),
            [el('button', { text: 'Close', onclick: closeDialog }),
              el('button', {
                class: 'primary', text: 'Apply', onclick: () => { closeDialog(); apply.click(); },
              })]);
        });
        thinking.appendChild(preview);
        thinking.appendChild(apply);
        //  Applied by hand, always. An assistant that rewrites the buffer
        //  under the author is one they stop trusting on the first bad edit.
        //
        //  But the buttons have to be *visible*: the dock is about 120 px tall
        //  and a scene explanation is about 280 px of text, and the log did not
        //  scroll after they were appended — so the whole flow depended on two
        //  controls sitting below the fold with nothing to say they were there.
        log.scrollTop = log.scrollHeight;
        apply.scrollIntoView({ block: 'nearest' });
      }
    } catch (e) {
      clearInterval(polling); polling = null; job = null;
      send.disabled = false; stop.style.display = 'none';
      say('assistant', e.message, 'error');
    }
  }

  send.addEventListener('click', () => {
    const t = input.value.trim();
    if (!t) return;
    input.value = '';
    submit(t, false);
  });
  input.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) send.click();
  });
  stop.addEventListener('click', async () => {
    if (!job) return;
    await api.api({ operation: 'assistant_interrupt', job }).catch(() => {});
  });

  //  Pressing one of these while the panel is collapsed used to start a job
  //  whose entire output landed in a box nobody could see.
  document.getElementById('animate-2d').addEventListener('click', () => {
    expand();
    if (!job) asker = 'animate-2d';
    say('you', 'Animate in 2D');
    submit('__animate_2d__', true);
  });
  document.getElementById('animate-3d').addEventListener('click', () => {
    expand();
    if (!job) asker = 'animate-3d';
    say('you', 'Animate in 3D');
    submit('__animate_3d__', true);
  });

  //  main.js re-runs the program after an applied scene edit and tells us how
  //  it went, so the pane's own notice ends where the picture begins.
  window.addEventListener('lps-assistant-ran', (e) => {
    asker = e.detail?.what || asker;
    announce('done', e.detail?.error ? { error: e.detail.error } : {});
  });

  window.addEventListener('lps-open-settings', () => {
    const k = keys();
    const rows = PROVIDERS.map((p) => {
      const inp = el('input', {
        type: 'password', value: k[p.id] || '', placeholder: `${p.env} (or set it on the server)`,
      });
      inp.dataset.provider = p.id;
      const state2 = el('span', { class: 'key-state muted' });
      const have = MODELS.some((m) => m.provider === p.id);
      state2.textContent = have ? `${MODELS.filter((m) => m.provider === p.id).length} models` : 'no key';
      state2.classList.toggle('ok', have);
      return el('div', { class: 'key-row' }, el('label', { text: p.label }), inp, state2);
    });

    /*  The model picker belongs here as well as in the panel header: the
     *  header's is a per-question override, and this is the default the whole
     *  IDE uses — including the live panel's English-to-event translator,
     *  which has no header of its own. */
    const dlgSel = el('select', { class: 'model-pick' });
    fillModelSelect(dlgSel);
    const refresh = el('button', { text: 'Re-read from providers' });
    refresh.addEventListener('click', async () => {
      refresh.disabled = true; refresh.textContent = 'asking…';
      await api.api({ operation: 'assistant_models', api_keys: keys(), refresh: true })
        .then((r) => { MODELS = r.models || []; })
        .catch(() => {});
      fillModelSelect(dlgSel); fillModelSelect(modelSel);
      refresh.disabled = false; refresh.textContent = 'Re-read from providers';
    });

    openDialog('API keys, models & Assistant settings',
      el('div', { class: 'keys' },
        el('p', {
          class: 'muted',
          text: 'A key set in the server’s environment wins; these are used only when it is not. '
            + 'They stay in this browser’s local storage and are sent with each request.',
        }),
        ...rows,
        el('hr'),
        el('div', { class: 'key-row' },
          el('label', { text: 'Default model' }), dlgSel, refresh),
        el('p', {
          class: 'muted',
          text: 'The list is what the providers themselves report, read once when the server '
            + 'starts and again whenever you ask. The picker in the assistant’s header '
            + 'overrides this for one question.',
        })),
      [
        el('button', { text: 'Cancel', onclick: closeDialog }),
        el('button', {
          class: 'primary', text: 'Save', onclick: () => {
            const out = {};
            for (const r of rows) {
              const i = r.querySelector('input');
              if (i.value.trim()) out[i.dataset.provider] = i.value.trim();
            }
            saveKeys(out);
            if (dlgSel.value) { localStorage.setItem('lps.model', dlgSel.value); }
            closeDialog(); loadModels();
          },
        }),
      ]);
  });

  document.getElementById('assistant-toggle').addEventListener('click', () => {
    panel.classList.toggle('collapsed');
    window.dispatchEvent(new Event('lps-dock'));
  });

  /*  The panel used to open itself the first time a browser saw the IDE, on the
   *  grounds that a collapsed panel gives no sign it exists. It has a named
   *  button in the top bar now, which is a better sign and a quieter one, so
   *  it starts closed and stays closed until it is asked for. The greeting is
   *  written into the log rather than shown, and is there when it is opened. */
  say('assistant', 'I can explain this program, change it, or write the display/2 clauses '
    + 'that make it draw itself.', 'muted');

  loadModels();
}
