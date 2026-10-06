// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// AI character creator — a stepped wizard (Mode → Details → Output → Generate
// → Greetings) mirroring the desktop creator's three modes (Quick / Guided /
// Automated). All three feed the same headless generator via POST
// /api/chargen/create; the per-mode field assembly lives in chargenForm.ts so a
// web-created card matches a desktop one. Progress streams over the WebSocket
// hub; the saved character then opens on the Greetings step (?greetings=<id>,
// so a reload keeps it), and "Open in editor" goes on to the editor.

import { useEffect, useRef, useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { api, ApiError } from '../api/client';
import { ChatSocket } from '../api/ws';
import { StepIndicator } from '../components/StepIndicator';
import { DEFAULT_FORM, buildPayload, type ChargenForm, type ChargenMode } from '../components/aichargen/chargenForm';
import { QuickConfig } from '../components/aichargen/QuickConfig';
import { GuidedConfig } from '../components/aichargen/GuidedConfig';
import { AutomatedConfig } from '../components/aichargen/AutomatedConfig';
import { OutputSettings } from '../components/aichargen/OutputSettings';
import { LoreContext } from '../components/aichargen/LoreContext';
import { GreetingsStep, type GreetingsStepHandle } from '../components/aichargen/GreetingsStep';

const STEPS = ['Mode', 'Details', 'Output', 'Generate', 'Greetings'];
const GREETINGS = STEPS.indexOf('Greetings');

const MODES: { id: ChargenMode; title: string; blurb: string; cls: string }[] = [
  { id: 'quick', title: '⚡ Quick', blurb: 'A short concept — the LLM fills in the rest. Fastest.', cls: 'quick' },
  { id: 'guided', title: '🧭 Guided', blurb: 'Your vision plus optional prompts and suggestion chips.', cls: 'guided' },
  { id: 'automated', title: '🛠️ Automated', blurb: 'Archetype + a full appearance / backstory builder. Most control.', cls: 'automated' },
];

export function CreateAiCharacterPage() {
  const navigate = useNavigate();
  const [params, setParams] = useSearchParams();
  // The character this run saved; its greetings are the last step.
  const createdId = params.get('greetings');
  const [form, setForm] = useState<ChargenForm>(DEFAULT_FORM);
  const set = (p: Partial<ChargenForm>) => setForm((f) => ({ ...f, ...p }));
  const [step, setStep] = useState(() => (createdId ? GREETINGS : 0));
  const [writing, setWriting] = useState(false);
  const greetings = useRef<GreetingsStepHandle>(null);
  const [available, setAvailable] = useState<boolean | null>(null);
  const [busy, setBusy] = useState(false);
  const [steps, setSteps] = useState<string[]>([]);
  const [error, setError] = useState('');

  useEffect(() => {
    api.get<{ available: boolean }>('/api/chargen/status')
      .then((r) => setAvailable(r.available))
      .catch(() => setAvailable(false));
  }, []);

  useEffect(() => {
    const socket = new ChatSocket((e) => {
      if (e.event === 'chargen_status' && e.data) {
        setSteps((s) => [...s, e.data!]);
      } else if (e.event === 'chargen_done') {
        setBusy(false);
        setParams({ greetings: String(e.id) });
        setStep(GREETINGS);
      } else if (e.event === 'chargen_error') {
        setBusy(false);
        setError(e.error || 'Generation failed');
      }
    });
    socket.connect();
    return () => socket.close();
  }, [setParams]);

  const generate = async () => {
    if (!form.name.trim() || busy) return;
    setBusy(true);
    setSteps([]);
    setError('');
    try {
      await api.post('/api/chargen/create', buildPayload(form));
    } catch (e) {
      setBusy(false);
      setError(e instanceof ApiError ? e.message : 'Could not start generation');
    }
  };

  const canAdvance =
    (step !== 0 || form.name.trim().length > 0) && (step !== GREETINGS - 1 || !!createdId);
  const held = busy || writing;

  const openEditor = async () => {
    // Edits typed in the last moment go first, so the editor opens on them.
    await greetings.current?.flush();
    navigate(`/edit/${createdId}`);
  };

  return (
    <div className="page wizard">
      <header className="page-head">
        <button className="ghost" onClick={() => navigate('/')}>← Library</button>
        <h2>✨ AI Character Creator</h2>
      </header>

      <StepIndicator steps={STEPS} current={step} onJump={held ? undefined : setStep} variant="porch" />

      {available === false && (
        <p className="muted">No LLM backend is ready — start or connect a model on the Models page first.</p>
      )}

      <div className="wizard-body">
        {step === 0 && (
          <div className="cg-config">
            <label className="cg-field">
              <span className="cg-field-label">Name</span>
              <input value={form.name} onChange={(e) => set({ name: e.target.value })} placeholder="e.g. Aria Vale" />
            </label>
            <div className="cg-mode-cards">
              {MODES.map((m) => (
                <button
                  type="button"
                  key={m.id}
                  className={`cg-mode-card ${m.cls}${form.mode === m.id ? ' on' : ''}`}
                  onClick={() => set({ mode: m.id })}
                >
                  <span className="cg-mode-title">{m.title}</span>
                  <span className="cg-mode-blurb">{m.blurb}</span>
                </button>
              ))}
            </div>
            <label className="cg-field cg-toggle">
              <input type="checkbox" checked={form.nsfw} onChange={(e) => set({ nsfw: e.target.checked })} />
              <span>Allow mature content</span>
            </label>
          </div>
        )}

        {step === 1 && form.mode === 'quick' && <QuickConfig form={form} set={set} />}
        {step === 1 && form.mode === 'guided' && <GuidedConfig form={form} set={set} />}
        {step === 1 && form.mode === 'automated' && <AutomatedConfig form={form} set={set} />}
        {step === 1 && <LoreContext form={form} set={set} />}

        {step === 2 && <OutputSettings form={form} set={set} />}

        {step === 3 && (
          <div className="cg-config">
            <div className="card cg-review">
              <div><span className="muted small">Name</span><div>{form.name || '—'}</div></div>
              <div><span className="muted small">Mode</span><div style={{ textTransform: 'capitalize' }}>{form.mode}</div></div>
              <div><span className="muted small">Mature content</span><div>{form.nsfw ? 'On' : 'Off'}</div></div>
              <div><span className="muted small">Lorebook</span><div>{form.generateLorebook ? `${form.loreDepth}` : 'Off'}</div></div>
            </div>
            <button
              className="primary cg-generate"
              disabled={busy || !form.name.trim() || available === false}
              onClick={generate}
            >
              {busy ? 'Generating…' : '✨ Generate character'}
            </button>
            {error && <p className="error">{error}</p>}
            {steps.length > 0 && (
              <ol className="chargen-steps">
                {steps.map((s, i) => (
                  <li key={i} className={i === steps.length - 1 && busy ? 'active' : 'done'}>{s}</li>
                ))}
              </ol>
            )}
          </div>
        )}

        {step === GREETINGS && createdId && (
          <GreetingsStep ref={greetings} characterId={createdId} onWritingChange={setWriting} />
        )}
        {step === GREETINGS && !createdId && (
          <p className="muted">Generate a character first; its greetings open here.</p>
        )}
      </div>

      {step === GREETINGS ? (
        <nav className="wizard-nav cg-g-nav" aria-label="Wizard steps">
          <button type="button" className="cg-g-back" disabled={writing} onClick={() => setStep(step - 1)}>
            <ArrowLeft />
            Back
          </button>
          <button
            type="button"
            className="cg-g-open"
            disabled={writing || !createdId}
            onClick={() => void openEditor()}
          >
            Open in editor
            <ArrowRight />
          </button>
        </nav>
      ) : (
        <div className="wizard-nav">
          <button disabled={step === 0 || held} onClick={() => setStep(step - 1)}>← Back</button>
          {step < STEPS.length - 1 && (
            <button className="primary" disabled={!canAdvance || held} onClick={() => setStep(step + 1)}>
              Next →
            </button>
          )}
        </div>
      )}
    </div>
  );
}

const arrow = {
  width: 18,
  height: 18,
  viewBox: '0 0 24 24',
  fill: 'none',
  stroke: 'currentColor',
  strokeWidth: 2,
  strokeLinecap: 'round' as const,
  strokeLinejoin: 'round' as const,
  'aria-hidden': true,
};

const ArrowLeft = () => (
  <svg {...arrow}>
    <path d="M19 12H5M11 6l-6 6 6 6" />
  </svg>
);

const ArrowRight = () => (
  <svg {...arrow}>
    <path d="M5 12h14M13 6l6 6-6 6" />
  </svg>
);
