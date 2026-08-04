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

  async function loadModels() {
    try {
      const r = await api.api({ operation: 'assistant_models' });
      modelSel.replaceChildren(...r.models.map((m) =>
        el('option', { value: m.name, text: `${m.name} (${m.provider})` })));
      const saved = localStorage.getItem('lps.model');
      if (saved && r.models.some((m) => m.name === saved)) modelSel.value = saved;
      panel.classList.toggle('unconfigured', !r.models.length);
    } catch (e) {
      modelSel.replaceChildren(el('option', { text: 'no models' }));
    }
  }
  modelSel.addEventListener('change', () => localStorage.setItem('lps.model', modelSel.value));

  async function submit(command, hidden) {
    if (job) return;
    if (!hidden) say('you', command);
    const thinking = say('assistant', '…', 'thinking');
    send.disabled = true; stop.style.display = '';
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
    }
  }

  async function poll(thinking) {
    if (!job) return;
    try {
      const r = await api.api({ operation: 'assistant_status', job });
      thinking.querySelector('.body').textContent =
        (r.output || []).slice(-6).join('\n') || '…';
      if (r.status === 'running') return;
      clearInterval(polling); polling = null; job = null;
      send.disabled = false; stop.style.display = 'none';
      thinking.classList.remove('thinking');
      thinking.querySelector('.body').textContent = r.explanation || r.error || '(no answer)';
      if (r.new_content && r.new_content !== state.editor.getValue()) {
        const apply = el('button', { class: 'apply', text: 'Apply to editor' });
        apply.addEventListener('click', () => {
          state.editor.executeEdits('assistant', [{
            range: state.editor.getModel().getFullModelRange(),
            text: r.new_content,
          }]);
          apply.remove();
          setStatus('assistant edit applied — undo with Ctrl/Cmd+Z');
        });
        thinking.appendChild(apply);
        //  Applied by hand, always. An assistant that rewrites the buffer
        //  under the author is one they stop trusting on the first bad edit.
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

  document.getElementById('animate-2d').addEventListener('click', () => {
    say('you', 'Animate in 2D');
    submit('__animate_2d__', true);
  });
  document.getElementById('animate-3d').addEventListener('click', () => {
    say('you', 'Animate in 3D');
    submit('__animate_3d__', true);
  });

  window.addEventListener('lps-open-settings', () => {
    const k = keys();
    const rows = PROVIDERS.map((p) => {
      const inp = el('input', {
        type: 'password', value: k[p.id] || '', placeholder: `${p.env} (or set it on the server)`,
      });
      inp.dataset.provider = p.id;
      return el('div', { class: 'key-row' }, el('label', { text: p.label }), inp);
    });
    openDialog('API keys & Assistant settings',
      el('div', { class: 'keys' },
        el('p', {
          class: 'muted',
          text: 'A key set in the server’s environment wins; these are used only when it is not. '
            + 'They stay in this browser’s local storage and are sent with each request.',
        }),
        ...rows),
      [
        el('button', { text: 'Cancel', onclick: closeDialog }),
        el('button', {
          class: 'primary', text: 'Save', onclick: () => {
            const out = {};
            for (const r of rows) {
              const i = r.querySelector('input');
              if (i.value.trim()) out[i.dataset.provider] = i.value.trim();
            }
            saveKeys(out); closeDialog(); loadModels();
          },
        }),
      ]);
  });

  document.getElementById('assistant-toggle').addEventListener('click', () => {
    panel.classList.toggle('collapsed');
  });

  loadModels();
}
