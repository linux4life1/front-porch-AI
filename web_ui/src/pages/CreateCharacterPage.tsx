// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Manual character creation wizard — the web mirror of the Flutter
// create_character_page.dart (Identity → Personality → Dialogue → Lorebook →
// Realism → Review). Posts to /api/characters/create, which reuses the desktop
// save path (writes a V2 PNG embedding the full Realism + Needs seeds via the
// shared realism_extensions_json helper). Full multi-step on desktop/tablet;
// the same steps stack compactly on phone.

import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { api, ApiError } from '../api/client';
import { StepIndicator } from '../components/StepIndicator';
import { LoreEntriesEditor, type LoreEntry } from '../components/LoreEntriesEditor';
import { AltGreetingsEditor } from '../components/AltGreetingsEditor';
import { RealismFormSection } from '../components/realism/RealismFormSection';
import { useAdultThemes } from '../components/realism/useAdultThemes';
import { NeedsFormSection } from '../components/realism/NeedsFormSection';
import { type RealismValues, REALISM_DEFAULTS, compactGreetingPairs, inventoryToChips } from '../components/realism/realismTypes';

interface Draft extends RealismValues {
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
}

const STEPS = ['Identity', 'Personality', 'Dialogue', 'Lorebook', 'Porch Life', 'Review'];

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
  ...REALISM_DEFAULTS,
};

export function CreateCharacterPage() {
  const adultThemes = useAdultThemes();
  const navigate = useNavigate();
  const [step, setStep] = useState(0);
  const [d, setD] = useState<Draft>(EMPTY);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const set = <K extends keyof Draft>(key: K, value: Draft[K]) => setD({ ...d, [key]: value });
  const patch = (p: Partial<RealismValues>) => setD({ ...d, ...p });
  const canAdvance = step > 0 || d.name.trim().length > 0;

  const create = async () => {
    setSaving(true);
    setError('');
    try {
      const paired = compactGreetingPairs(d.alternateGreetings, d.greetingSeeds);
      const res = await api.post<{ id: string; name: string }>('/api/characters/create', {
        ...d,
        tags: d.tags.split(',').map((t) => t.trim()).filter(Boolean),
        alternateGreetings: paired.greetings,
        greetingSeeds: paired.seeds,
      });
      // Open the new character so creation is verifiable end-to-end.
      try {
        navigate('/chat?opening=1');
        await api.post('/api/chat/select', { characterId: res.id });
        navigate('/chat', { replace: true });
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
            <AltGreetingsEditor
              greetings={d.alternateGreetings}
              onChange={(g) => set('alternateGreetings', g)}
              seeds={d.greetingSeeds}
              showNeeds={d.needsSimEnabled}
              onSeedsChange={(seeds) => set('greetingSeeds', seeds)}
            />
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
            <RealismFormSection v={d} set={patch} showIntimate={adultThemes} />
            {d.realismEnabled && <NeedsFormSection v={d} set={patch} />}
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
            <ReviewRow
              label="Porch Life"
              value={[
                d.realismEnabled ? `Engine on · bond ${d.shortTermBond}` : 'Engine off',
                d.chaosModeEnabled ? 'Chaos' : null,
                d.ambitions.length ? `ambitions ${d.ambitions.length}` : null,
                d.occupation.trim() ? d.occupation : null,
                d.likes.length ? `likes ${d.likes.length}` : null,
                inventoryToChips(d.inventory).worn.length
                  ? `wearing ${inventoryToChips(d.inventory).worn.length}`
                  : null,
                inventoryToChips(d.inventory).carrying.length
                  ? `carrying ${inventoryToChips(d.inventory).carrying.length}`
                  : null,
              ].filter(Boolean).join(' · ')}
            />
            {d.realismEnabled && (
              <ReviewRow label="Needs" value={d.needsSimEnabled ? `On · ${d.needsSimStrength}× strength` : 'Off'} />
            )}
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

function ReviewRow({ label, value }: { label: string; value: string }) {
  if (!value) return null;
  return (
    <div className="stat-line">
      <span className="muted">{label}</span>
      <span className="review-val">{value.length > 60 ? `${value.slice(0, 60)}…` : value}</span>
    </div>
  );
}
