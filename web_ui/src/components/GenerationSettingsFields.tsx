// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Generation card for web Settings: thinking, sampler parameters, output
// limits, sanitiser, stop sequences, and banned phrases. The prompt family
// lives in PromptSettingsCard under General (prompt-picker SOW Phase 2).
// Desktop Generation parity (audit P2.12).

import { spellCheckLabel, sortedByLabel } from '../spellCheckLabels';
import { resetFor, type Recommended, type SamplerKey } from './genPresets/genPresets';
import { GenerationParametersCard } from './GenerationParametersCard';
import {
  SanitizerRulesEditor,
  StringListEditor,
  type SanitizerRule,
} from './OutputPipelineEditors';
import { SliderField } from './StudioSliderField';
import { ThinkingSettingsControl } from './ThinkingSettingsControl';

export { SliderField, type SanitizerRule };

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
  const model = isLocal ? '' : (remoteModelName ?? '');
  const replyFills = replyFillsContextWarning(contextSize, g.maxLength);
  const shown = (knob: SamplerKnob) => samplerKnobShown(knob, backend, samplerKnobs);
  const rs = (key: keyof GenSettings) => {
    const r = resetFor(recommended, key as SamplerKey, g[key]);
    return r && { title: r.title, onReset: () => patchGen({ [key]: r.value }) };
  };

  return (
    <section className="card" data-testid="generation-fields">
      <h3>Generation</h3>

      <ThinkingSettingsControl
        model={model}
        reasoningEnabled={reasoningEnabled}
        reasoningEffort={reasoningEffort}
        reasoningMandatory={reasoningMandatory}
        reasoningEfforts={reasoningEfforts}
        reasoningLocalSupport={reasoningLocalSupport}
        onPatch={patch}
      />

      <GenerationParametersCard
        generation={g}
        shown={shown}
        rs={rs}
        patchGen={patchGen}
      />

      <div className="gen-subcard">
        <h4 className="gen-subcard-title">Output Limits &amp; Context Budgets</h4>
        <SliderField
          card
          label="Max output tokens"
          info="Maximum tokens generated in a single reply. 2,048 is standard; higher values allow deep reasoning chains."
          value={g.maxLength}
          min={64}
          max={65536}
          step={64}
          defaultVal={2048}
          dangerMin={128}
          reset={rs('maxLength')}
          onChange={(v) => patchGen({ maxLength: Math.round(v) })}
        />
        <SliderField
          card
          label="Context size"
          value={contextSize}
          min={512}
          max={500000}
          step={512}
          disabled={contextLocked}
          onChange={(v) => patch({ contextSize: Math.round(v) })}
        />
        {contextLocked && <p className="muted small">{CONTEXT_LOCKED}</p>}
        {contextSize > 0 && contextSize < contextFloor && (
          <div className="cpu-warn" data-testid="context-floor-warning">{CONTEXT_FLOOR_WORDS}</div>
        )}
        {replyFills && (
          <div className="cpu-warn" data-testid="context-reply-warning">{replyFills}</div>
        )}
      </div>

      <div className="gen-subcard">
        <h4 className="gen-subcard-title">Output Pipeline &amp; Rules</h4>
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
              <SliderField
                label="Idle timeout (s)"
                value={g.dynamicResponseInterval}
                min={30}
                max={300}
                step={10}
                onChange={(v) => patchGen({ dynamicResponseInterval: Math.round(v) })}
              />
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
      </div>
    </section>
  );
}
