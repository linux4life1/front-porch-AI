// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Manual character creation wizard — the web mirror of the Flutter
// create_character_page.dart (Identity → Personality → Dialogue → Lorebook →
// Realism → Review). Posts to /api/characters/create, which reuses the desktop
// save path (writes a V2 PNG embedding the full Realism + Needs seeds via the
// shared realism_extensions_json helper). Full multi-step on desktop/tablet;
// the same steps stack compactly on phone.

import { useEffect, useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { api, ApiError } from '../api/client';
import { StepIndicator } from '../components/StepIndicator';
import { PersonaSeedNote, usePersonaSeed } from '../components/library/PersonaConvertDialogs';
import { LoreEntriesEditor, type LoreEntry } from '../components/LoreEntriesEditor';
import { AltGreetingsEditor } from '../components/AltGreetingsEditor';
import { RealismFormSection } from '../components/realism/RealismFormSection';
import { useAdultFlags } from '../components/realism/useAdultThemes';
import { usePassageOfTime } from '../components/realism/usePassageOfTime';
import { NeedsFormSection } from '../components/realism/NeedsFormSection';
import { type RealismValues, REALISM_DEFAULTS, compactGreetingPairs, inventoryToChips } from '../components/realism/realismTypes';
import { useUnsavedChanges } from '../hooks/useUnsavedChanges';

import { scenarioOpeningHelp, scenarioRulesHelp, scenarioSettingHelp, ScenarioCardTypeField, type CardType } from "../components/ScenarioCardTypeField";

interface Draft extends RealismValues {
  name: string;
  tags: string;
  description: string;
  personality: string;
  scenario: string;
  cardType: CardType;
  facilitationRules: string;
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
  cardType: 'character',
  facilitationRules: '',
  firstMessage: '',
  alternateGreetings: [],
  mesExample: '',
  systemPrompt: '',
  postHistoryInstructions: '',
  lorebook: [],
  ...REALISM_DEFAULTS,
};

export function CreateCharacterPage() {
  const { adult: adultThemes, afterglow, planner } = useAdultFlags();
  const clockOn = usePassageOfTime();
  const navigate = useNavigate();
  const [step, setStep] = useState(0);
  const [d, setD] = useState<Draft>(EMPTY);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  // "Make a Character" → Manual: start from a persona.
  const [params] = useSearchParams();
  const { seed: personaSeed, error: seedError } = usePersonaSeed(params);
  const withSeed = (base: Draft): Draft =>
    personaSeed
      ? {
          ...base,
          name: personaSeed.name,
          description: personaSeed.description,
          personality: personaSeed.personality ?? '',
          birthday: personaSeed.birthday,
        }
      : base;
  useEffect(() => {
    if (!personaSeed) return;
    setD(withSeed);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [personaSeed]);
  // A persona's seed is where the page starts, not an edit.
  const { prompt, leaveWithoutAsking } = useUnsavedChanges(
    JSON.stringify(d) !== JSON.stringify(withSeed(EMPTY)),
  );

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
        ...(personaSeed?.hasPortrait ? { portraitPersonaId: personaSeed.personaId } : {}),
      });
      leaveWithoutAsking();
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
      {prompt}
      <div className="page-head">
        <h2>Create character</h2>
        <button className="ghost" onClick={() => navigate(-1)}>Cancel</button>
      </div>
      <StepIndicator steps={STEPS} current={step} onJump={setStep} />
      {personaSeed && <PersonaSeedNote seed={personaSeed} />}
      {seedError && <p className="error">{seedError}</p>}

      <div className="wizard-body">
        {step === 0 && (
          <>
            <label>
              Name<span className="req"> *</span>
              <input value={d.name} onChange={(e) => set('name', e.target.value)} autoFocus />
            </label>
            <ScenarioCardTypeField value={d.cardType} onChange={(value) => set('cardType', value)} />
            <label>
              Tags (comma-separated)
              <input value={d.tags} onChange={(e) => set('tags', e.target.value)} />
            </label>
            {d.cardType !== 'scenario' && <label>
              Description
              <textarea rows={6} value={d.description} onChange={(e) => set('description', e.target.value)} />
            </label>}
          </>
        )}

        {step === 1 && (
          <>
            {d.cardType === 'scenario' && <label>
              Scene notes
              <textarea rows={6} value={d.description} onChange={(e) => set('description', e.target.value)} />
            </label>}
            <label>
              {d.cardType === 'scenario' ? 'Narration style' : 'Personality'}
              <textarea rows={6} value={d.personality} onChange={(e) => set('personality', e.target.value)} />
            </label>
            <label>
              {d.cardType === 'scenario' ? 'Setting' : 'Scenario'}
              <textarea rows={6} aria-describedby={d.cardType === 'scenario' ? 'create-scenario-setting-help' : undefined} value={d.scenario} onChange={(e) => set('scenario', e.target.value)} />
            </label>
            {d.cardType === 'scenario' && <p id="create-scenario-setting-help" className="muted small">{scenarioSettingHelp}</p>}
            {d.cardType === 'scenario' && <>
              <label>
              Facilitation rules
              <textarea rows={3} aria-describedby="create-scenario-rules-help" value={d.facilitationRules}
                placeholder="How to run the scene..."
                onChange={(e) => set('facilitationRules', e.target.value)} />
              </label>
              <p id="create-scenario-rules-help" className="muted small">{scenarioRulesHelp}</p>
            </>}
            {d.cardType === 'scenario' && <details>
              <summary>Advanced Prompts</summary>
              <label>
              System prompt (optional)
              <textarea rows={3} value={d.systemPrompt} onChange={(e) => set('systemPrompt', e.target.value)} />
            </label>
            <label>
              Post-history instructions (optional)
              <textarea rows={3} value={d.postHistoryInstructions} onChange={(e) => set('postHistoryInstructions', e.target.value)} />
            </label>
            </details>}
          </>
        )}

        {step === 2 && (
          <>
            <label>
              {d.cardType === 'scenario' ? 'Opening message' : 'First message (greeting)'}
              <textarea rows={5} aria-describedby={d.cardType === 'scenario' ? 'create-scenario-opening-help' : undefined} value={d.firstMessage} onChange={(e) => set('firstMessage', e.target.value)} />
            </label>
            {d.cardType === 'scenario' && <p id="create-scenario-opening-help" className="muted small">{scenarioOpeningHelp}</p>}
            <AltGreetingsEditor
              showOpeningState={d.cardType !== 'scenario'}
              greetings={d.alternateGreetings}
              onChange={(g) => set('alternateGreetings', g)}
              seeds={d.greetingSeeds}
              showNeeds
              clockOn={clockOn}
              onSeedsChange={(seeds) => set('greetingSeeds', seeds)}
            />
            <label>
              {d.cardType === 'scenario' ? 'Reply examples' : 'Example dialogue'}
              <textarea rows={4} value={d.mesExample} onChange={(e) => set('mesExample', e.target.value)} />
            </label>
            {d.cardType !== 'scenario' && <><label>
              System prompt (optional)
              <textarea rows={3} value={d.systemPrompt} onChange={(e) => set('systemPrompt', e.target.value)} />
            </label>
            <label>
              Post-history instructions (optional)
              <textarea rows={3} value={d.postHistoryInstructions} onChange={(e) => set('postHistoryInstructions', e.target.value)} />
            </label></>}
          </>
        )}

        {step === 3 && (
          <LoreEntriesEditor entries={d.lorebook} onChange={(entries) => set('lorebook', entries)} />
        )}

        {step === 4 && (
          <>
            <RealismFormSection
              v={d}
              set={patch}
              showIntimate={adultThemes}
              afterglowOn={afterglow}
              showChargenSuggestion
              planner={planner}
            />
            {d.realismEnabled && <NeedsFormSection v={d} set={patch} clockOn={clockOn} />}
          </>
        )}

        {step === 5 && (
          <div className="review">
            <p><strong>{d.name || '(unnamed)'}</strong>{d.tags && <span className="muted"> · {d.tags}</span>}</p>
            <ReviewRow label={d.cardType === 'scenario' ? 'Scene notes' : 'Description'} value={d.description} />
            <ReviewRow label={d.cardType === 'scenario' ? 'Narration style' : 'Personality'} value={d.personality} />
            <ReviewRow label="Card type" value={d.cardType === 'scenario' ? 'Scenario' : 'Character'} />
            <ReviewRow label={d.cardType === 'scenario' ? 'Setting' : 'Scenario'}
              value={d.cardType === 'scenario' && !d.scenario.trim() ? 'Chosen in chat' : d.scenario} />
            {d.cardType === 'scenario' && <ReviewRow label="Facilitation rules" value={d.facilitationRules} />}
            <ReviewRow label={d.cardType === 'scenario' ? 'Opening message' : 'First message'}
              value={d.cardType === 'scenario' && !d.firstMessage.trim() ? (d.alternateGreetings.some((g) => g.trim()) ? 'Uses the first alternate' : 'Player speaks first') : d.firstMessage} />
            <ReviewRow label="Lorebook" value={d.lorebook.length ? `${d.lorebook.length} entr${d.lorebook.length === 1 ? 'y' : 'ies'}` : 'None'} />
            <ReviewRow
              label="Porch Life"
              value={[
                d.realismEnabled ? `Engine on · bond ${d.shortTermBond}` : 'Engine off',
                d.chaosModeEnabled ? 'Chaos' : null,
                d.ambitions.length ? `ambitions ${d.ambitions.length}` : null,
                d.traitKit.length ? `kit ${d.traitKit.length}` : null,
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
            <ReviewRow label="Pockets & Wardrobe" value={d.pocketsEnabled ? 'On' : 'Off'} />
            {d.realismEnabled && (
              <ReviewRow label="Needs" value={d.needsSimEnabled ? `On · ${d.needsPace} pace` : 'Off'} />
            )}
            {error && <p className="error" role="alert">{error}</p>}
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
