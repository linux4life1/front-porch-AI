// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Generation card for web Settings: sampler sliders, thinking, AFK replies,
// sanitiser, stop sequences, and banned phrases. The prompt family lives in
// PromptSettingsCard under General (prompt-picker SOW Phase 2).
// Desktop Generation parity (audit P2.12).

import { useState } from 'react';
import {
  reasoningEffortBlurb,
  reasoningEffortChipsFor,
  reasoningEffortDisplayedSelection,
  reasoningEffortMappingCaption,
  reasoningEffortTitle,
} from '../utils/reasoningEffort';
import { spellCheckLabel, sortedByLabel } from '../spellCheckLabels';
import { resetFor, type Recommended, type SamplerKey } from './genPresets/genPresets';

export interface SanitizerRule {
  id: number;
  find: string;
  replace: string;
  stop_after_match?: boolean;
}

export interface GenSettings {
  temperature: number;
  minP: number;
  topP?: number;
  topK?: number;
  dryMultiplier?: number;
  repeatPenalty: number;
  repeatPenaltyTokens: number;
  xtcThreshold: number;
  xtcProbability: number;
  maxLength: number;
  minLength: number;
  dynamicTempEnabled: boolean;
  dynamicTempRange?: number;
  dynamicResponses: boolean;
  dynamicResponseInterval: number;
  dynamicResponsePacePeriods?: number;
  outputSanitizerEnabled?: boolean;
  sanitiseExistingHistory?: boolean;
  outputSanitizerRules?: SanitizerRule[];
  stopSequences?: string[];
}

/** Said where a preset in use sets the context: the desktop's own words. */
export const CONTEXT_LOCKED =
  'Context size is controlled by the active .kcpps preset and cannot be edited here.';

/** The host's floor when it does not send one (an older host). */
export const CONTEXT_FLOOR = 16384;

/** Said under a context set below the floor: the desktop's own words. */
export const CONTEXT_FLOOR_WORDS =
  '16,384 or more. Below that is not recommended or supported: ' +
  'characters remember very little of the chat.';

const tokens = (n: number) => n.toLocaleString('en-US');

/** A generation setting not every backend receives (the host's SamplerKnob
 *  names). Temperature, Top-P, max output and context reach every backend. */
export type SamplerKnob =
  | 'minP'
  | 'topK'
  | 'repeatPenalty'
  | 'repeatPenaltyTokens'
  | 'xtc'
  | 'dry'
  | 'dynamicTemp'
  | 'bannedPhrases';

/** Whether to show [knob]: the host's list of what this backend's requests
 *  carry (samplerKnobs). An older host sends no list, and the rule this
 *  page had before stands: XTC, DRY and banned phrases on KoboldCpp only. */
export function samplerKnobShown(knob: SamplerKnob, backend: string, knobs?: string[]): boolean {
  if (knobs) return knobs.includes(knob);
  if (knob === 'xtc' || knob === 'dry' || knob === 'bannedPhrases') return backend === 'kobold';
  return true;
}

/** Said when the longest reply allowed takes up the whole context (the
 *  desktop's koboldReplyFillsContextWarning); null while it leaves room. */
export function replyFillsContextWarning(context: number, maxOutput: number): string | null {
  if (context <= 0 || maxOutput < context) return null;
  return (
    `Max output tokens (${tokens(maxOutput)}) takes up the whole context ` +
    `(${tokens(context)} tokens), leaving no room for the character or the ` +
    'chat. Lower it, or raise the context.'
  );
}

export function SliderField({
  label,
  value,
  step,
  min,
  max,
  onChange,
  disabled,
  reset,
  defaultVal,
  dangerMin,
  dangerMax,
}: {
  label: string;
  value: number;
  step: number;
  min: number;
  max: number;
  onChange: (v: number) => void;
  disabled?: boolean;
  /** A ↺ beside the value (generation presets); its title says to what. */
  reset?: { title: string; onReset: () => void };
  defaultVal?: number;
  dangerMin?: number;
  dangerMax?: number;
}) {
  const valPct = Math.max(0, Math.min(100, ((value - min) / (max - min)) * 100));
  const dMaxPct =
    dangerMax !== undefined
      ? Math.max(0, Math.min(100, ((dangerMax - min) / (max - min)) * 100))
      : undefined;
  const dMinPct =
    dangerMin !== undefined
      ? Math.max(0, Math.min(100, ((dangerMin - min) / (max - min)) * 100))
      : undefined;

  let trackGradient: string;
  const dangerInactive = 'color-mix(in srgb, var(--danger) 35%, transparent)';
  const dangerActive = 'var(--danger)';

  if (dMaxPct !== undefined) {
    if (valPct <= dMaxPct) {
      // Thumb is in safe range: solid accent to thumb, neutral to danger boundary, danger inactive to end
      trackGradient = `linear-gradient(to right, var(--accent) 0%, var(--accent) ${valPct}%, var(--border) ${valPct}%, var(--border) ${dMaxPct}%, ${dangerInactive} ${dMaxPct}%, ${dangerInactive} 100%)`;
    } else {
      // Thumb is in upper danger zone: accent up to dMaxPct, danger active to thumb, danger inactive to end
      trackGradient = `linear-gradient(to right, var(--accent) 0%, var(--accent) ${dMaxPct}%, ${dangerActive} ${dMaxPct}%, ${dangerActive} ${valPct}%, ${dangerInactive} ${valPct}%, ${dangerInactive} 100%)`;
    }
  } else if (dMinPct !== undefined) {
    if (valPct >= dMinPct) {
      // Thumb is in safe range (above dangerMin): danger inactive to dMinPct, accent to thumb, neutral to end
      trackGradient = `linear-gradient(to right, ${dangerInactive} 0%, ${dangerInactive} ${dMinPct}%, var(--accent) ${dMinPct}%, var(--accent) ${valPct}%, var(--border) ${valPct}%, var(--border) 100%)`;
    } else {
      // Thumb is in lower danger zone: danger active to thumb, danger inactive to dMinPct, neutral to end
      trackGradient = `linear-gradient(to right, ${dangerActive} 0%, ${dangerActive} ${valPct}%, ${dangerInactive} ${valPct}%, ${dangerInactive} ${dMinPct}%, var(--border) ${dMinPct}%, var(--border) 100%)`;
    }
  } else {
    // Normal slider without danger zones: solid accent to thumb, neutral to end
    trackGradient = `linear-gradient(to right, var(--accent) 0%, var(--accent) ${valPct}%, var(--border) ${valPct}%, var(--border) 100%)`;
  }

  const defaultPct =
    defaultVal !== undefined
      ? Math.max(0, Math.min(100, ((defaultVal - min) / (max - min)) * 100))
      : undefined;

  return (
    <div className="slider-field">
      <div className="slider-head">
        <span>{label}</span>
        <span className="slider-head-right">
        {reset && (
          <button type="button" className="slider-reset" title={reset.title}
            aria-label={`${label}: ${reset.title}`} onClick={reset.onReset}>
            ↺
          </button>
        )}
        <input
          type="number"
          className="slider-val"
          value={value}
          step={step}
          min={0}
          disabled={disabled}
          onChange={(e) => {
            const n = Number(e.target.value);
            if (Number.isFinite(n)) onChange(n);
          }}
        />
        </span>
      </div>
      <div className="slider-track-wrap">
        <input
          type="range"
          value={Math.max(min, Math.min(max, value))}
          step={step}
          min={min}
          max={max}
          disabled={disabled}
          style={trackGradient ? { background: trackGradient } : undefined}
          onChange={(e) => onChange(Number(e.target.value))}
        />
        {defaultPct !== undefined && (
          <span
            className="slider-default-pip"
            style={{ left: `${defaultPct}%` }}
            aria-hidden="true"
          />
        )}
      </div>
    </div>
  );
}

export function GenerationSettingsFields({
  backend,
  isLocal,
  remoteModelName,
  contextSize,
  contextLocked,
  contextFloor = CONTEXT_FLOOR,
  generation,
  bannedPhrases,
  spellCheckLanguage,
  spellCheckLanguages,
  reasoningEnabled,
  reasoningEffort,
  reasoningMandatory,
  reasoningEfforts,
  reasoningLocalSupport,
  samplerKnobs,
  recommended,
  patch,
  patchGen,
}: {
  backend: string;
  isLocal: boolean;
  remoteModelName?: string;
  contextSize: number;
  /** A preset in use sets the context (KoboldCpp only): the slider is locked. */
  contextLocked?: boolean;
  /** Below this the context is warned about (the host's kKoboldContextFloor). */
  contextFloor?: number;
  generation: GenSettings;
  bannedPhrases?: string[];
  spellCheckLanguage?: string;
  spellCheckLanguages?: string[];
  reasoningEnabled: boolean;
  reasoningEffort: string;
  reasoningMandatory?: boolean;
  reasoningEfforts?: string[];
  reasoningLocalSupport?: string;
  /** What this backend's requests carry; absent on an older host. */
  samplerKnobs?: string[];
  /** The chat model's recommended values, for each slider's ↺. */
  recommended?: Recommended;
  patch: (p: Record<string, unknown>) => void;
  patchGen: (p: Partial<GenSettings>) => void;
}) {
  const g = generation;
  const replyFills = replyFillsContextWarning(contextSize, g.maxLength);
  // Only what this backend's requests carry; a hidden value is kept.
  const shown = (knob: SamplerKnob) => samplerKnobShown(knob, backend, samplerKnobs);
  // ↺ only while the value differs from the model's recommended one.
  const rs = (key: SamplerKey & keyof GenSettings) => {
    const r = resetFor(recommended, key, g[key]);
    return r && { title: r.title, onReset: () => patchGen({ [key]: r.value }) };
  };
  return (
    <section className="card" data-testid="generation-fields">
      <h3>Generation</h3>

      {/* ── Category 1: Thinking / Model Reasoning ── */}
      <label className="row-label">
        <span>Request thinking</span>
        <input
          type="checkbox"
          checked={Boolean(reasoningEnabled) || Boolean(reasoningMandatory)}
          disabled={Boolean(reasoningMandatory) || reasoningLocalSupport === 'none'}
          onChange={(e) => {
            if (!reasoningMandatory && reasoningLocalSupport !== 'none') {
              patch({ reasoningEnabled: e.target.checked });
            }
          }}
        />
      </label>
      {Boolean(reasoningMandatory) && (
        <p className="muted small">This model always thinks — Off is not available.</p>
      )}
      {reasoningLocalSupport === 'none' && (
        <p className="muted small">
          This model has no thinking mode — its chat template never produces
          think-steps, so this switch would do nothing.
        </p>
      )}
      {reasoningLocalSupport === 'toggle' && (
        <p className="muted small">
          This model thinks on or off only — it has no strength levels, so
          there are no chips to pick.
        </p>
      )}
      {(reasoningEnabled || Boolean(reasoningMandatory)) &&
        reasoningLocalSupport !== 'none' &&
        ((reasoningEfforts?.length ?? 0) > 0 || !reasoningLocalSupport) && (
        <div className="thinking-strength">
          <div className="thinking-strength-label">Thinking strength</div>
          <div className="thinking-strength-chips" role="group" aria-label="Thinking strength">
            {(reasoningEfforts?.length
              ? reasoningEfforts
              : reasoningLocalSupport
                ? []
                : reasoningEffortChipsFor(isLocal ? '' : (remoteModelName ?? ''))
            ).map((id) => {
              const model = isLocal ? '' : (remoteModelName ?? '');
              const on = reasoningEffortDisplayedSelection(
                model,
                reasoningEffort || 'medium',
                reasoningEfforts?.length ? reasoningEfforts : undefined,
              ) === id;
              return (
                <button
                  key={id}
                  type="button"
                  className={`thinking-strength-chip${on ? ' on' : ''}`}
                  onClick={() => patch({ reasoningEffort: id })}
                >
                  <span className="thinking-strength-chip-title">
                    {reasoningEffortTitle(id)}
                  </span>
                  <span className="thinking-strength-chip-sub">
                    {reasoningEffortBlurb(id)}
                  </span>
                </button>
              );
            })}
          </div>
          <p className="muted small thinking-strength-caption">
            {reasoningEffortMappingCaption(
              isLocal ? '' : (remoteModelName ?? ''),
              reasoningEffort || 'medium',
              reasoningEfforts,
              reasoningMandatory,
            )}
          </p>
        </div>
      )}
      {!reasoningEnabled && !reasoningMandatory && (
        <p className="muted small">
          Turn on for reasoning models so their think-steps are captured under each reply.
          The chips then show this model&apos;s real levels.
        </p>
      )}

      {/* ── Category 2: Generation Parameters (Studio Console) ── */}
      <h4 style={{ marginTop: 24, marginBottom: 8 }}>Generation Parameters</h4>
      <div className="studio-sampler-grid">
        <div className="studio-col">
          <div className="studio-column-heading">Creativity & Probability</div>
          <div className="studio-slider-card">
            <SliderField
              label="Temperature"
              value={g.temperature}
              min={0}
              max={2.0}
              step={0.05}
              defaultVal={0.70}
              dangerMax={1.60}
              reset={rs('temperature')}
              onChange={(v) => patchGen({ temperature: v })}
            />
          </div>
          {shown('minP') && (
            <div className="studio-slider-card">
              <SliderField
                label="Min-P"
                value={g.minP}
                min={0}
                max={0.25}
                step={0.01}
                defaultVal={0.10}
                dangerMax={0.15}
                reset={rs('minP')}
                onChange={(v) => patchGen({ minP: v })}
              />
            </div>
          )}
          {g.topP !== undefined && (
            <div className="studio-slider-card">
              <SliderField
                label="Top-P"
                value={g.topP}
                min={0.50}
                max={1.0}
                step={0.01}
                defaultVal={0.90}
                dangerMin={0.65}
                reset={rs('topP')}
                onChange={(v) => patchGen({ topP: v })}
              />
            </div>
          )}
          {g.topK !== undefined && shown('topK') && (
            <div className="studio-slider-card">
              <SliderField
                label="Top-K"
                value={g.topK}
                min={0}
                max={100}
                step={1}
                defaultVal={0}
                dangerMax={80}
                reset={rs('topK')}
                onChange={(v) => patchGen({ topK: Math.round(v) })}
              />
            </div>
          )}
          {shown('dynamicTemp') && (
            <div className="studio-slider-card">
              <label className="row-label" style={{ margin: 0 }}>
                <span>Dynamic temperature</span>
                <input
                  type="checkbox"
                  checked={g.dynamicTempEnabled}
                  onChange={(e) => patchGen({ dynamicTempEnabled: e.target.checked })}
                />
              </label>
              {g.dynamicTempEnabled && g.dynamicTempRange !== undefined && (
                <div style={{ marginTop: 8 }}>
                  <SliderField
                    label="Dynatemp range"
                    value={g.dynamicTempRange}
                    min={0}
                    max={2.0}
                    step={0.05}
                    defaultVal={0.70}
                    dangerMax={1.60}
                    reset={rs('dynamicTempRange')}
                    onChange={(v) => patchGen({ dynamicTempRange: v })}
                  />
                </div>
              )}
            </div>
          )}
        </div>

        <div className="studio-col">
          <div className="studio-column-heading">Flow & Anti-Repetition</div>
          {g.dryMultiplier !== undefined && shown('dry') && (
            <div className="studio-slider-card">
              <SliderField
                label="DRY strength"
                value={g.dryMultiplier}
                min={0}
                max={1.6}
                step={0.05}
                defaultVal={0}
                dangerMax={1.20}
                reset={rs('dryMultiplier')}
                onChange={(v) => patchGen({ dryMultiplier: v })}
              />
            </div>
          )}
          {shown('repeatPenalty') && (
            <div className="studio-slider-card">
              <SliderField
                label="Repeat penalty"
                value={g.repeatPenalty}
                min={1.0}
                max={1.35}
                step={0.01}
                defaultVal={1.10}
                dangerMax={1.20}
                reset={rs('repeatPenalty')}
                onChange={(v) => patchGen({ repeatPenalty: v })}
              />
            </div>
          )}
          {shown('repeatPenaltyTokens') && (
            <div className="studio-slider-card">
              <SliderField
                label="Rep pen tokens"
                value={g.repeatPenaltyTokens}
                min={0}
                max={2048}
                step={8}
                defaultVal={1024}
                dangerMin={128}
                reset={rs('repeatPenaltyTokens')}
                onChange={(v) => patchGen({ repeatPenaltyTokens: Math.round(v) })}
              />
            </div>
          )}
          {shown('xtc') && (
            <>
              <div className="studio-slider-card">
                <SliderField
                  label="XTC threshold"
                  value={g.xtcThreshold}
                  min={0}
                  max={1.00}
                  step={0.01}
                  defaultVal={0.10}
                  dangerMax={0.80}
                  reset={rs('xtcThreshold')}
                  onChange={(v) => patchGen({ xtcThreshold: v })}
                />
              </div>
              <div className="studio-slider-card">
                <SliderField
                  label="XTC probability"
                  value={g.xtcProbability}
                  min={0}
                  max={1.0}
                  step={0.05}
                  defaultVal={0}
                  dangerMax={0.60}
                  reset={rs('xtcProbability')}
                  onChange={(v) => patchGen({ xtcProbability: v })}
                />
              </div>
            </>
          )}
        </div>
      </div>

      {/* ── Category 3: Output Limits & Context Budgets ── */}
      <h4 style={{ marginTop: 24, marginBottom: 8 }}>Output Limits</h4>
      <div className="studio-slider-card">
        <SliderField
          label="Max output tokens"
          value={g.maxLength}
          min={64}
          max={65536}
          step={64}
          defaultVal={2048}
          dangerMin={128}
          reset={rs('maxLength')}
          onChange={(v) => patchGen({ maxLength: Math.round(v) })}
        />
      </div>
      <div className="studio-slider-card">
        <SliderField
          label="Context size"
          value={contextSize}
          min={512}
          max={500000}
          step={512}
          disabled={contextLocked}
          onChange={(v) => patch({ contextSize: Math.round(v) })}
        />
      </div>
      {contextLocked && <p className="muted small">{CONTEXT_LOCKED}</p>}
      {contextSize > 0 && contextSize < contextFloor && (
        <div className="cpu-warn" data-testid="context-floor-warning">{CONTEXT_FLOOR_WORDS}</div>
      )}
      {replyFills && (
        <div className="cpu-warn" data-testid="context-reply-warning">{replyFills}</div>
      )}

      {/* ── Category 4: Output Pipeline & Controls ── */}
      {spellCheckLanguage !== undefined && (
        <div style={{ marginTop: 16 }}>
          <label>
            Spell check language
            <select
              value={spellCheckLanguage}
              onChange={(e) => patch({ spellCheckLanguage: e.target.value })}
            >
              <option value="off">Off</option>
              {sortedByLabel([
                ...(spellCheckLanguages ?? []),
                ...(spellCheckLanguage !== 'off' ? [spellCheckLanguage] : []),
              ]).map((tag) => (
                <option key={tag} value={tag}>{spellCheckLabel(tag)}</option>
              ))}
            </select>
            <p className="muted small">
              The language you write in — not your device&apos;s language. If your phone or
              computer is set to one language but you chat with characters in another,
              set this to the one you chat in.
            </p>
          </label>
        </div>
      )}

      <div style={{ marginTop: 16 }}>
        <label className="row-label">
          <span>Provide periodic responses when user is AFK?</span>
          <input
            type="checkbox"
            checked={g.dynamicResponses}
            onChange={(e) => patchGen({ dynamicResponses: e.target.checked })}
          />
        </label>
        {g.dynamicResponses && (
          <>
            <SliderField label="Idle timeout (s)" value={g.dynamicResponseInterval} min={30} max={300} step={10}
              onChange={(v) => patchGen({ dynamicResponseInterval: Math.round(v) })} />
            <label className="field">
              <span>Story time per away scene</span>
              <select
                value={g.dynamicResponsePacePeriods ?? 1}
                onChange={(e) =>
                  patchGen({ dynamicResponsePacePeriods: Number(e.target.value) })
                }
              >
                <option value={1}>a few hours</option>
                <option value={3}>half the day</option>
                <option value={6}>a full day</option>
              </select>
            </label>
          </>
        )}
      </div>

      {g.stopSequences && (
        <StringListEditor
          title="Stop sequences"
          hint="The model stops if it writes one of these strings."
          values={g.stopSequences}
          onChange={(stopSequences) => patchGen({ stopSequences })}
          placeholder="e.g. \nUser:"
        />
      )}

      {shown('bannedPhrases') && bannedPhrases !== undefined && (
        <div style={{ marginTop: 16 }}>
          <label>
            Banned phrases
            <textarea
              rows={4}
              value={bannedPhrases.join('\n')}
              onChange={(e) =>
                patch({
                  bannedPhrases: e.target.value.split('\n').map((s) => s.trim()).filter(Boolean),
                })
              }
              placeholder="One phrase per line"
            />
            <p className="muted small">KoboldCpp only — the model will not emit these strings.</p>
          </label>
        </div>
      )}

      {g.outputSanitizerEnabled !== undefined && (
        <>
          <h4 style={{ marginTop: 20, marginBottom: 4 }}>Output Sanitizer</h4>
          <p className="muted small">
            Replace specific character sequences in model output before saving
            to chat history (e.g. em dash → &quot; - &quot;).
          </p>
          <label className="row-label">
            <span>Enable Output Sanitizer</span>
            <input
              type="checkbox"
              checked={!!g.outputSanitizerEnabled}
              onChange={(e) =>
                patchGen({
                  outputSanitizerEnabled: e.target.checked,
                  ...(e.target.checked
                    ? {}
                    : { sanitiseExistingHistory: false }),
                })
              }
            />
          </label>
          {g.outputSanitizerEnabled && (
            <>
              <label className="row-label">
                <span>Sanitise existing history</span>
                <input
                  type="checkbox"
                  checked={!!g.sanitiseExistingHistory}
                  onChange={(e) => {
                    if (e.target.checked) {
                      const ok = window.confirm(
                        'Every chat you open while this is on will have the rules applied to its saved AI messages — permanently, on that chat’s next save. Your own messages are never touched. This cannot be undone.',
                      );
                      if (!ok) return;
                    }
                    patchGen({ sanitiseExistingHistory: e.target.checked });
                  }}
                />
              </label>
              <p className="muted small">
                When on, opening a chat permanently applies the rules below to
                saved AI messages. Your own messages are never touched.
              </p>
              <SanitizerRulesEditor
                rules={g.outputSanitizerRules ?? []}
                onChange={(rules) => patchGen({ outputSanitizerRules: rules })}
              />
            </>
          )}
        </>
      )}
    </section>
  );
}

function StringListEditor({
  title,
  hint,
  values,
  onChange,
  placeholder,
}: {
  title: string;
  hint: string;
  values: string[];
  onChange: (next: string[]) => void;
  placeholder: string;
}) {
  const [newVal, setNewVal] = useState('');

  const handleAdd = () => {
    if (newVal.length > 0 && !values.includes(newVal)) {
      onChange([...values, newVal]);
      setNewVal('');
    }
  };

  const handleItemChange = (idx: number, text: string) => {
    const next = [...values];
    next[idx] = text;
    onChange(next);
  };

  return (
    <div className="stop-sequence-editor" style={{ marginTop: 16 }}>
      <h4 style={{ margin: '0 0 4px' }}>{title}</h4>
      <p className="muted small" style={{ marginBottom: 8 }}>{hint}</p>

      <div className="stop-sequence-box">
        {/* Add Input Row shifted ABOVE listed stop sequences */}
        <div className="stop-sequence-input-row">
          <input
            className="stop-sequence-input"
            value={newVal}
            placeholder={placeholder}
            onChange={(e) => setNewVal(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter') {
                e.preventDefault();
                handleAdd();
              }
            }}
          />
          <button
            type="button"
            className="icon-btn stop-sequence-add-btn"
            title="Add sequence"
            onClick={handleAdd}
          >
            <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor">
              <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm5 11h-4v4h-2v-4H7v-2h4V7h2v4h4v2z" />
            </svg>
          </button>
        </div>

        {/* Listed Sequences below the input with inline editable inputs and red circle remove button */}
        {values.length > 0 && (
          <div className="stop-sequence-list">
            {values.map((s, i) => (
              <div key={i} className="stop-sequence-item">
                <input
                  className="stop-sequence-inline-input"
                  value={s}
                  placeholder={placeholder}
                  onChange={(e) => handleItemChange(i, e.target.value)}
                />
                <button
                  type="button"
                  className="icon-btn circle-remove-btn"
                  title="Remove stop sequence"
                  onClick={() => onChange(values.filter((_, idx) => idx !== i))}
                >
                  <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                    <circle cx="12" cy="12" r="10" />
                    <line x1="15" y1="9" x2="9" y2="15" />
                    <line x1="9" y1="9" x2="15" y2="15" />
                  </svg>
                </button>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

function SanitizerRulesEditor({
  rules,
  onChange,
}: {
  rules: SanitizerRule[];
  onChange: (rules: SanitizerRule[]) => void;
}) {
  const [findInput, setFindInput] = useState('');
  const [replaceInput, setReplaceInput] = useState('');
  const [duplicateWarning, setDuplicateWarning] = useState(false);
  const [draggedIdx, setDraggedIdx] = useState<number | null>(null);
  const [dragOverIdx, setDragOverIdx] = useState<number | null>(null);

  const nextId = () => rules.reduce((m, r) => Math.max(m, r.id), -1) + 1;

  const handleAdd = () => {
    if (!findInput) return;
    if (rules.some((r) => r.find === findInput && r.replace === replaceInput)) {
      setDuplicateWarning(true);
      return;
    }
    setDuplicateWarning(false);
    onChange([
      ...rules,
      {
        id: nextId(),
        find: findInput,
        replace: replaceInput,
        stop_after_match: false,
      },
    ]);
    setFindInput('');
    setReplaceInput('');
  };

  const handleToggleStop = (idx: number) => {
    onChange(
      rules.map((r, i) =>
        i === idx ? { ...r, stop_after_match: !r.stop_after_match } : r,
      ),
    );
  };

  const handleRuleChange = (idx: number, patch: Partial<SanitizerRule>) => {
    onChange(rules.map((r, i) => (i === idx ? { ...r, ...patch } : r)));
  };

  const handleMove = (idx: number, delta: number) => {
    const targetIdx = idx + delta;
    if (targetIdx < 0 || targetIdx >= rules.length) return;
    const next = [...rules];
    const [moved] = next.splice(idx, 1);
    next.splice(targetIdx, 0, moved);
    onChange(next);
  };

  const handleRemove = (idx: number) => {
    onChange(rules.filter((_, i) => i !== idx));
  };

  const handleDragStart = (e: React.DragEvent, idx: number) => {
    setDraggedIdx(idx);
    e.dataTransfer.effectAllowed = 'move';
    e.dataTransfer.setData('text/plain', String(idx));
  };

  const handleDragOver = (e: React.DragEvent, idx: number) => {
    e.preventDefault();
    e.dataTransfer.dropEffect = 'move';
    if (dragOverIdx !== idx) {
      setDragOverIdx(idx);
    }
  };

  const handleDrop = (e: React.DragEvent, targetIdx: number) => {
    e.preventDefault();
    if (draggedIdx === null || draggedIdx === targetIdx) {
      setDraggedIdx(null);
      setDragOverIdx(null);
      return;
    }
    const next = [...rules];
    const [moved] = next.splice(draggedIdx, 1);
    next.splice(targetIdx, 0, moved);
    onChange(next);
    setDraggedIdx(null);
    setDragOverIdx(null);
  };

  const handleDragEnd = () => {
    setDraggedIdx(null);
    setDragOverIdx(null);
  };

  return (
    <div className="sanitizer-rule-editor" style={{ marginTop: 12 }}>
      <div className="sanitizer-box">
        {/* 1. Find / Replace input row matching original desktop */}
        <div className="sanitizer-input-row">
          <input
            className="sanitizer-find-input"
            placeholder="Find..."
            value={findInput}
            onChange={(e) => {
              if (duplicateWarning) setDuplicateWarning(false);
              setFindInput(e.target.value);
            }}
            onKeyDown={(e) => {
              if (e.key === 'Enter') handleAdd();
            }}
          />
          <div className="sanitizer-input-divider" />
          <input
            className="sanitizer-replace-input"
            placeholder="Replace..."
            value={replaceInput}
            onChange={(e) => {
              if (duplicateWarning) setDuplicateWarning(false);
              setReplaceInput(e.target.value);
            }}
            onKeyDown={(e) => {
              if (e.key === 'Enter') handleAdd();
            }}
          />
          <button
            type="button"
            className="icon-btn sanitizer-add-btn"
            title="Add replacement rule"
            onClick={handleAdd}
          >
            <svg width="22" height="22" viewBox="0 0 24 24" fill="currentColor">
              <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm5 11h-4v4h-2v-4H7v-2h4V7h2v4h4v2z" />
            </svg>
          </button>
        </div>
        {duplicateWarning && (
          <p className="sanitizer-warn-text">Rule already exists</p>
        )}

        {/* 2. Reorderable Rules List with full HTML5 Drag & Drop and touch reorder buttons */}
        <div className="sanitizer-rules-list">
          {rules.length === 0 ? (
            <div className="sanitizer-empty">No rules configured</div>
          ) : (
            rules.map((rule, idx) => {
              const isDragging = draggedIdx === idx;
              const isDragOver = dragOverIdx === idx;
              return (
                <div
                  key={rule.id}
                  className={`sanitizer-rule-row${isDragging ? ' dragging' : ''}${isDragOver ? ' drag-over' : ''}`}
                  draggable
                  onDragStart={(e) => handleDragStart(e, idx)}
                  onDragOver={(e) => handleDragOver(e, idx)}
                  onDragLeave={() => {
                    if (dragOverIdx === idx) setDragOverIdx(null);
                  }}
                  onDrop={(e) => handleDrop(e, idx)}
                  onDragEnd={handleDragEnd}
                >
                  {/* Drag Handle (desktop) */}
                  <span className="sanitizer-drag-handle" title="Drag to reorder">
                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                      <line x1="4" y1="9" x2="20" y2="9" />
                      <line x1="4" y1="15" x2="20" y2="15" />
                    </svg>
                  </span>

                  {/* Touch Up/Down buttons (mobile Safari/Chrome fallback) */}
                  <button
                    type="button"
                    className="reorder-btn"
                    title="Move up"
                    disabled={idx === 0}
                    onClick={() => handleMove(idx, -1)}
                    aria-label="Move rule up"
                  >
                    ▲
                  </button>
                  <button
                    type="button"
                    className="reorder-btn"
                    title="Move down"
                    disabled={idx === rules.length - 1}
                    onClick={() => handleMove(idx, 1)}
                    aria-label="Move rule down"
                  >
                    ▼
                  </button>

                  {/* Stop After Match Toggle (stop_circle) */}
                  <button
                    type="button"
                    className={`icon-btn stop-circle-btn${rule.stop_after_match ? ' on' : ''}`}
                    title={rule.stop_after_match ? 'Stop after match (on)' : 'Stop after match (off)'}
                    onClick={() => handleToggleStop(idx)}
                  >
                    <svg width="18" height="18" viewBox="0 0 24 24" fill={rule.stop_after_match ? 'currentColor' : 'none'} stroke="currentColor" strokeWidth="2">
                      <circle cx="12" cy="12" r="10" />
                      <rect x="9" y="9" width="6" height="6" fill={rule.stop_after_match ? 'var(--card)' : 'currentColor'} />
                    </svg>
                  </button>

                  {/* Inline Editable Inputs: Find → Replace */}
                  <div className="sanitizer-rule-inputs">
                    <input
                      className="sanitizer-inline-input"
                      value={rule.find}
                      placeholder="Find"
                      onChange={(e) => handleRuleChange(idx, { find: e.target.value })}
                    />
                    <span className="muted" style={{ margin: '0 4px' }}>→</span>
                    <input
                      className="sanitizer-inline-input"
                      value={rule.replace}
                      placeholder="Replace"
                      onChange={(e) => handleRuleChange(idx, { replace: e.target.value })}
                    />
                  </div>

                  {/* Remove Rule (remove_circle_outline) */}
                  <button
                    type="button"
                    className="icon-btn circle-remove-btn"
                    title="Remove rule"
                    onClick={() => handleRemove(idx)}
                  >
                    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                      <circle cx="12" cy="12" r="10" />
                      <line x1="15" y1="9" x2="9" y2="15" />
                      <line x1="9" y1="9" x2="15" y2="15" />
                    </svg>
                  </button>
                </div>
              );
            })
          )}
        </div>

        {/* 3. Rules Count Summary */}
        <div className="sanitizer-summary">
          <span>{rules.length === 0 ? 'No rules configured' : `${rules.length} rule${rules.length === 1 ? '' : 's'}`}</span>
          {rules.length > 0 && <span className="muted">Rules execute in top-to-bottom order</span>}
        </div>
      </div>
    </div>
  );
}
