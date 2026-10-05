// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Generation card for web Settings: sampler sliders, thinking, AFK replies,
// sanitiser, stop sequences, banned phrases, and the global system prompt.
// Desktop Generation + General parity (audit P2.12).

import {
  reasoningEffortBlurb,
  reasoningEffortChipsFor,
  reasoningEffortDisplayedSelection,
  reasoningEffortMappingCaption,
  reasoningEffortTitle,
} from '../utils/reasoningEffort';
import { spellCheckLabel, sortedByLabel } from '../spellCheckLabels';

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

export function SliderField({
  label,
  value,
  step,
  min,
  max,
  onChange,
  disabled,
}: {
  label: string;
  value: number;
  step: number;
  min: number;
  max: number;
  onChange: (v: number) => void;
  disabled?: boolean;
}) {
  return (
    <div className="slider-field">
      <div className="slider-head">
        <span>{label}</span>
        <input
          type="number"
          className="slider-val"
          value={value}
          step={step}
          min={min}
          max={max}
          disabled={disabled}
          onChange={(e) => {
            const n = Number(e.target.value);
            if (Number.isFinite(n)) onChange(n);
          }}
        />
      </div>
      <input
        type="range"
        value={value}
        step={step}
        min={min}
        max={max}
        disabled={disabled}
        onChange={(e) => onChange(Number(e.target.value))}
      />
    </div>
  );
}

export function GenerationSettingsFields({
  backend,
  isLocal,
  remoteModelName,
  contextSize,
  contextLocked,
  generation,
  systemPrompt,
  bannedPhrases,
  spellCheckLanguage,
  spellCheckLanguages,
  reasoningEnabled,
  reasoningEffort,
  reasoningMandatory,
  reasoningEfforts,
  reasoningLocalSupport,
  patch,
  patchGen,
}: {
  backend: string;
  isLocal: boolean;
  remoteModelName?: string;
  contextSize: number;
  /** A preset in use sets the context (KoboldCpp only): the slider is locked. */
  contextLocked?: boolean;
  generation: GenSettings;
  systemPrompt?: string;
  bannedPhrases?: string[];
  spellCheckLanguage?: string;
  spellCheckLanguages?: string[];
  reasoningEnabled: boolean;
  reasoningEffort: string;
  reasoningMandatory?: boolean;
  reasoningEfforts?: string[];
  reasoningLocalSupport?: string;
  patch: (p: Record<string, unknown>) => void;
  patchGen: (p: Partial<GenSettings>) => void;
}) {
  const g = generation;
  return (
    <section className="card">
      <h3>Generation</h3>
      {systemPrompt !== undefined && (
        <label>
          System prompt
          <textarea
            rows={6}
            value={systemPrompt}
            onChange={(e) => patch({ systemPrompt: e.target.value })}
          />
        </label>
      )}
      <SliderField label="Temperature" value={g.temperature} min={0} max={2} step={0.05}
        onChange={(v) => patchGen({ temperature: v })} />
      <SliderField label="Min-P" value={g.minP} min={0} max={1} step={0.01}
        onChange={(v) => patchGen({ minP: v })} />
      {g.topP !== undefined && (
        <SliderField label="Top-P" value={g.topP} min={0.1} max={1} step={0.01}
          onChange={(v) => patchGen({ topP: v })} />
      )}
      {g.topK !== undefined && (
        <SliderField label="Top-K" value={g.topK} min={0} max={200} step={1}
          onChange={(v) => patchGen({ topK: Math.round(v) })} />
      )}
      <SliderField label="Repeat penalty" value={g.repeatPenalty} min={1} max={3} step={0.01}
        onChange={(v) => patchGen({ repeatPenalty: v })} />
      <SliderField label="Rep pen tokens" value={g.repeatPenaltyTokens} min={0} max={2048} step={8}
        onChange={(v) => patchGen({ repeatPenaltyTokens: Math.round(v) })} />
      {backend === 'kobold' && (
        <>
          <SliderField label="XTC threshold" value={g.xtcThreshold} min={0} max={0.5} step={0.01}
            onChange={(v) => patchGen({ xtcThreshold: v })} />
          <SliderField label="XTC probability" value={g.xtcProbability} min={0} max={1} step={0.05}
            onChange={(v) => patchGen({ xtcProbability: v })} />
          {g.dryMultiplier !== undefined && (
            <SliderField label="DRY strength" value={g.dryMultiplier} min={0} max={3} step={0.05}
              onChange={(v) => patchGen({ dryMultiplier: v })} />
          )}
        </>
      )}
      <SliderField label="Max output tokens" value={g.maxLength} min={16} max={16384} step={16}
        onChange={(v) => patchGen({ maxLength: Math.round(v) })} />
      <SliderField label="Min output tokens" value={g.minLength} min={0} max={512} step={1}
        onChange={(v) => patchGen({ minLength: Math.round(v) })} />
      <SliderField label="Context size" value={contextSize} min={512} max={500000} step={512}
        disabled={contextLocked}
        onChange={(v) => patch({ contextSize: Math.round(v) })} />
      {contextLocked && <p className="muted small">{CONTEXT_LOCKED}</p>}
      <label className="row-label">
        <span>Dynamic temperature</span>
        <input
          type="checkbox"
          checked={g.dynamicTempEnabled}
          onChange={(e) => patchGen({ dynamicTempEnabled: e.target.checked })}
        />
      </label>
      {g.dynamicTempEnabled && g.dynamicTempRange !== undefined && (
        <SliderField label="Dynatemp range" value={g.dynamicTempRange} min={0} max={2} step={0.1}
          onChange={(v) => patchGen({ dynamicTempRange: v })} />
      )}
      {spellCheckLanguage !== undefined && (
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
      )}
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
      {g.stopSequences && (
        <StringListEditor
          title="Stop sequences"
          hint="The model stops if it writes one of these strings."
          values={g.stopSequences}
          onChange={(stopSequences) => patchGen({ stopSequences })}
          placeholder="e.g. \nUser:"
        />
      )}
      {backend === 'kobold' && bannedPhrases !== undefined && (
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
      )}
      {g.outputSanitizerEnabled !== undefined && (
        <>
          <h4 style={{ marginTop: 16, marginBottom: 4 }}>Output Sanitizer</h4>
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
  return (
    <div style={{ marginTop: 12 }}>
      <h4 style={{ margin: '0 0 4px' }}>{title}</h4>
      <p className="muted small">{hint}</p>
      {values.map((s, i) => (
        <div key={i} className="tool-row" style={{ gap: 6, marginBottom: 6 }}>
          <input
            style={{ flex: 1 }}
            value={s}
            placeholder={placeholder}
            onChange={(e) => {
              const next = [...values];
              next[i] = e.target.value;
              onChange(next);
            }}
          />
          <button
            className="icon-btn"
            title="Remove"
            onClick={() => onChange(values.filter((_, idx) => idx !== i))}
          >
            🗑
          </button>
        </div>
      ))}
      <button
        className="small"
        type="button"
        onClick={() => onChange([...values, ''])}
      >
        Add
      </button>
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
  const nextId = () => rules.reduce((m, r) => Math.max(m, r.id), -1) + 1;
  const patch = (i: number, p: Partial<SanitizerRule>) => {
    onChange(rules.map((r, idx) => (idx === i ? { ...r, ...p } : r)));
  };
  return (
    <div className="sanitizer-rules" style={{ marginTop: 8 }}>
      {rules.map((r, i) => (
        <div key={r.id} className="tool-row" style={{ gap: 6, marginBottom: 6, flexWrap: 'wrap' }}>
          <input
            style={{ flex: 1, minWidth: 80 }}
            placeholder="Find"
            value={r.find}
            onChange={(e) => patch(i, { find: e.target.value })}
          />
          <span className="muted small">→</span>
          <input
            style={{ flex: 1, minWidth: 80 }}
            placeholder="Replace"
            value={r.replace}
            onChange={(e) => patch(i, { replace: e.target.value })}
          />
          <label className="muted small" title="Stop applying later rules after this one changes the text">
            <input
              type="checkbox"
              checked={!!r.stop_after_match}
              onChange={(e) => patch(i, { stop_after_match: e.target.checked })}
            />{' '}
            stop
          </label>
          <button
            className="icon-btn"
            title="Remove rule"
            onClick={() => onChange(rules.filter((_, idx) => idx !== i))}
          >
            🗑
          </button>
        </div>
      ))}
      <button
        className="small"
        type="button"
        onClick={() =>
          onChange([...rules, { id: nextId(), find: '', replace: '', stop_after_match: false }])
        }
      >
        Add rule
      </button>
    </div>
  );
}
