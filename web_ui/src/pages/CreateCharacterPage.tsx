// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Manual character creation wizard — the web mirror of the Flutter
// create_character_page.dart (Identity → Personality → Dialogue → Lorebook →
// Realism → Review). Posts to /api/characters/create, which reuses the desktop
// save path (writes a V2 PNG embedding the Realism seeds). Full multi-step on
// desktop/tablet; the same steps stack compactly on phone.

import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { api, ApiError } from '../api/client';
import { StepIndicator } from '../components/StepIndicator';
import { LoreEntriesEditor, type LoreEntry } from '../components/LoreEntriesEditor';

interface Draft {
  name: string;
  tags: string;
  description: string;
  personality: string;
  scenario: string;
  firstMessage: string;
  alternateGreetings: string[];
  mesExample: string;
  systemPrompt: string;
  postHistoryInstructions: string;
  lorebook: LoreEntry[];
  realismEnabled: boolean;
  shortTermBond: number;
  longTermBond: number;
  trustLevel: number;
  characterEmotion: string;
  emotionIntensity: string;
  needsSimEnabled: boolean;
  chaosModeEnabled: boolean;
  nsfwCooldownEnabled: boolean;
  currentTask: string;
}

const STEPS = ['Identity', 'Personality', 'Dialogue', 'Lorebook', 'Realism', 'Review'];

const EMPTY: Draft = {
  name: '',
  tags: '',
  description: '',
  personality: '',
  scenario: '',
  firstMessage: '',
  alternateGreetings: [],
  mesExample: '',
  systemPrompt: '',
  postHistoryInstructions: '',
  lorebook: [],
  realismEnabled: false,
  shortTermBond: 0,
  longTermBond: 0,
  trustLevel: 0,
  characterEmotion: '',
  emotionIntensity: 'mild',
  needsSimEnabled: false,
  chaosModeEnabled: false,
  nsfwCooldownEnabled: false,
  currentTask: '',
};

export function CreateCharacterPage() {
  const navigate = useNavigate();
  const [step, setStep] = useState(0);
  const [d, setD] = useState<Draft>(EMPTY);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const set = <K extends keyof Draft>(key: K, value: Draft[K]) => setD({ ...d, [key]: value });
  const canAdvance = step > 0 || d.name.trim().length > 0;

  const create = async () => {
    setSaving(true);
    setError('');
    try {
      const res = await api.post<{ id: string; name: string }>('/api/characters/create', {
        ...d,
        tags: d.tags.split(',').map((t) => t.trim()).filter(Boolean),
        alternateGreetings: d.alternateGreetings.filter((g) => g.trim()),
      });
      // Open the new character so creation is verifiable end-to-end.
      try {
        await api.post('/api/chat/select', { characterId: res.id });
        navigate('/chat');
      } catch {
        navigate('/');
      }
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Could not create character');
      setSaving(false);
    }
  };

  return (
    <div className="page wizard">
      <div className="page-head">
        <h2>Create character</h2>
        <button className="ghost" onClick={() => navigate(-1)}>Cancel</button>
      </div>
      <StepIndicator steps={STEPS} current={step} onJump={setStep} />

      <div className="wizard-body">
        {step === 0 && (
          <>
            <label>
              Name<span className="req"> *</span>
              <input value={d.name} onChange={(e) => set('name', e.target.value)} autoFocus />
            </label>
            <label>
              Tags (comma-separated)
              <input value={d.tags} onChange={(e) => set('tags', e.target.value)} />
            </label>
            <label>
              Description
              <textarea rows={6} value={d.description} onChange={(e) => set('description', e.target.value)} />
            </label>
          </>
        )}

        {step === 1 && (
          <>
            <label>
              Personality
              <textarea rows={6} value={d.personality} onChange={(e) => set('personality', e.target.value)} />
            </label>
            <label>
              Scenario
              <textarea rows={6} value={d.scenario} onChange={(e) => set('scenario', e.target.value)} />
            </label>
          </>
        )}

        {step === 2 && (
          <>
            <label>
              First message (greeting)
              <textarea rows={5} value={d.firstMessage} onChange={(e) => set('firstMessage', e.target.value)} />
            </label>
            <div className="row-label">
              <span>Alternate greetings</span>
              <button className="ghost" onClick={() => set('alternateGreetings', [...d.alternateGreetings, ''])}>
                + Add
              </button>
            </div>
            {d.alternateGreetings.map((g, i) => (
              <div className="tool-row" key={i}>
                <textarea
                  rows={3}
                  value={g}
                  onChange={(e) => {
                    const next = [...d.alternateGreetings];
                    next[i] = e.target.value;
                    set('alternateGreetings', next);
                  }}
                />
                <button className="icon-btn" title="Remove" onClick={() => set('alternateGreetings', d.alternateGreetings.filter((_, j) => j !== i))}>🗑</button>
              </div>
            ))}
            <label>
              Example dialogue
              <textarea rows={4} value={d.mesExample} onChange={(e) => set('mesExample', e.target.value)} />
            </label>
            <label>
              System prompt (optional)
              <textarea rows={3} value={d.systemPrompt} onChange={(e) => set('systemPrompt', e.target.value)} />
            </label>
            <label>
              Post-history instructions (optional)
              <textarea rows={3} value={d.postHistoryInstructions} onChange={(e) => set('postHistoryInstructions', e.target.value)} />
            </label>
          </>
        )}

        {step === 3 && (
          <LoreEntriesEditor entries={d.lorebook} onChange={(entries) => set('lorebook', entries)} />
        )}

        {step === 4 && (
          <>
            <label className="tool-toggle">
              <span>Enable Realism engine for this character</span>
              <input type="checkbox" checked={d.realismEnabled} onChange={(e) => set('realismEnabled', e.target.checked)} />
            </label>
            <p className="muted small">Seeds the starting relationship & state. You can change all of this later in the chat sidebar.</p>
            <RangeRow label="Starting bond" min={-300} max={300} value={d.shortTermBond} onChange={(v) => set('shortTermBond', v)} />
            <RangeRow label="Long-term bond" min={-300} max={300} value={d.longTermBond} onChange={(v) => set('longTermBond', v)} />
            <RangeRow label="Trust" min={-100} max={100} value={d.trustLevel} onChange={(v) => set('trustLevel', v)} />
            <label>
              Starting emotion (optional)
              <input value={d.characterEmotion} placeholder="e.g. curious" onChange={(e) => set('characterEmotion', e.target.value)} />
            </label>
            <label>
              Emotion intensity
              <select value={d.emotionIntensity} onChange={(e) => set('emotionIntensity', e.target.value)}>
                <option value="mild">Mild</option>
                <option value="moderate">Moderate</option>
                <option value="strong">Strong</option>
              </select>
            </label>
            <label>
              Initial task / quest (optional)
              <input value={d.currentTask} onChange={(e) => set('currentTask', e.target.value)} />
            </label>
            <label className="tool-toggle">
              <span>Needs simulation</span>
              <input type="checkbox" checked={d.needsSimEnabled} onChange={(e) => set('needsSimEnabled', e.target.checked)} />
            </label>
            <label className="tool-toggle">
              <span>Chaos mode</span>
              <input type="checkbox" checked={d.chaosModeEnabled} onChange={(e) => set('chaosModeEnabled', e.target.checked)} />
            </label>
            <label className="tool-toggle">
              <span>Post-climax NSFW cooldown</span>
              <input type="checkbox" checked={d.nsfwCooldownEnabled} onChange={(e) => set('nsfwCooldownEnabled', e.target.checked)} />
            </label>
          </>
        )}

        {step === 5 && (
          <div className="review">
            <p><strong>{d.name || '(unnamed)'}</strong>{d.tags && <span className="muted"> · {d.tags}</span>}</p>
            <ReviewRow label="Description" value={d.description} />
            <ReviewRow label="Personality" value={d.personality} />
            <ReviewRow label="Scenario" value={d.scenario} />
            <ReviewRow label="First message" value={d.firstMessage} />
            <ReviewRow label="Lorebook" value={d.lorebook.length ? `${d.lorebook.length} entr${d.lorebook.length === 1 ? 'y' : 'ies'}` : 'None'} />
            <ReviewRow label="Realism" value={d.realismEnabled ? `On · bond ${d.shortTermBond}, trust ${d.trustLevel}` : 'Off'} />
            {error && <p className="error">{error}</p>}
          </div>
        )}
      </div>

      <div className="wizard-nav">
        <button disabled={step === 0} onClick={() => setStep(step - 1)}>← Back</button>
        {step < STEPS.length - 1 ? (
          <button className="primary" disabled={!canAdvance} onClick={() => setStep(step + 1)}>Next →</button>
        ) : (
          <button className="primary" disabled={saving || !d.name.trim()} onClick={create}>
            {saving ? 'Creating…' : 'Create character'}
          </button>
        )}
      </div>
    </div>
  );
}

function RangeRow({ label, min, max, value, onChange }: { label: string; min: number; max: number; value: number; onChange: (v: number) => void }) {
  return (
    <label>
      <span>{label}: {value}</span>
      <input type="range" min={min} max={max} value={value} onChange={(e) => onChange(parseInt(e.target.value, 10))} />
    </label>
  );
}

function ReviewRow({ label, value }: { label: string; value: string }) {
  if (!value) return null;
  return (
    <div className="stat-line">
      <span className="muted">{label}</span>
      <span className="review-val">{value.length > 60 ? `${value.slice(0, 60)}…` : value}</span>
    </div>
  );
}
