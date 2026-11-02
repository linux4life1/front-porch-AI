// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Generation presets (issue 686) on the phone: the relay's wire shapes
// (lib/services/web/routes/gen_preset_routes.dart) and the small rules the
// bar, the model pickers, the toast and the chat drawer share. The host
// decides everything that writes; these only read.

import { api } from '../../api/client';
import { remoteModelSlot } from '../../remoteApiKeys';

/** A preset's values, keyed as the host's SamplerValues.toJson(). */
export interface SamplerValues {
  temperature?: number;
  minP?: number;
  topP?: number;
  topK?: number;
  repeatPenalty?: number;
  repeatPenaltyTokens?: number;
  xtcThreshold?: number;
  xtcProbability?: number;
  dryMultiplier?: number;
  dynamicTempEnabled?: boolean;
  dynamicTempRange?: number;
  maxLength?: number;
  reasoningEnabled?: boolean;
  reasoningEffort?: string;
  stopSequences?: string[];
}
export type SamplerKey = keyof SamplerValues;

/** Every key a preset holds, in the desktop's order. */
export const SAMPLER_KEYS: SamplerKey[] = [
  'temperature', 'minP', 'topP', 'topK', 'repeatPenalty', 'repeatPenaltyTokens',
  'xtcThreshold', 'xtcProbability', 'dryMultiplier', 'dynamicTempEnabled',
  'dynamicTempRange', 'maxLength', 'reasoningEnabled', 'reasoningEffort', 'stopSequences',
];

export interface Recommended {
  values: SamplerValues;
  resetValues: SamplerValues;
  source: 'modelFile' | 'provider' | 'family' | 'none';
  sourceWords: string;
  familyLabel?: string;
}

export interface GenPresets {
  presets: { name: string; values: SamplerValues }[];
  slot: string | null;
  state: 'notSaved' | 'saved' | 'edited';
  model: { key: string; label: string; local?: boolean } | null;
  linked: string | null;
  links: Record<string, string>;
  recommended: Recommended;
  appDefaults: SamplerValues;
  live: SamplerValues;
  notice: { id: number; message: string } | null;
  undone?: boolean;
}

/** The open chat's own values (null/absent = follows the global one). */
export interface ChatGeneration {
  open: boolean;
  isGroup?: boolean;
  values?: SamplerValues;
  overrides?: number;
  genPresetName?: string | null;
  global?: SamplerValues;
  backend?: string;
  samplerKnobs?: string[];
}

const EMPTY_REC: Recommended = {
  values: {},
  resetValues: {},
  source: 'none',
  sourceWords: 'app default',
};

/** Reads whatever an older or odd host sent without throwing. */
export function normalizeGenPresets(raw: unknown): GenPresets {
  const r = (raw && typeof raw === 'object' ? raw : {}) as Partial<GenPresets>;
  return {
    presets: Array.isArray(r.presets) ? r.presets : [],
    slot: typeof r.slot === 'string' ? r.slot : null,
    state: r.state === 'saved' || r.state === 'edited' ? r.state : 'notSaved',
    model: r.model && typeof r.model.key === 'string' ? r.model : null,
    linked: typeof r.linked === 'string' ? r.linked : null,
    links: r.links && typeof r.links === 'object' ? r.links : {},
    recommended: r.recommended && typeof r.recommended === 'object'
      ? { ...EMPTY_REC, ...r.recommended }
      : EMPTY_REC,
    appDefaults: r.appDefaults ?? {},
    live: r.live ?? {},
    notice: r.notice && typeof r.notice.id === 'number' ? r.notice : null,
    undone: r.undone,
  };
}

export const genPresetsApi = {
  read: () => api.get<unknown>('/api/gen-presets').then(normalizeGenPresets),
  post: (action: string, body: Record<string, unknown> = {}) =>
    api.post<unknown>(`/api/gen-presets/${action}`, body).then(normalizeGenPresets),
};

/** The host's ChatModelId.local key. */
export function localModelKey(path: string): string {
  const base = path.trim().split(/[\\/]/).pop() ?? '';
  return `local:${base.toLowerCase()}`;
}

/** The host's ChatModelId key for a backend + model, or null with none. */
export function chatModelKey(
  backend: string,
  remoteApiUrl: string,
  remoteModelName: string,
  localPath?: string | null,
): string | null {
  if (backend === 'kobold' || backend === '') {
    return localPath && localPath.trim() ? localModelKey(localPath) : null;
  }
  const model = remoteModelName.trim();
  if (!model) return null;
  return `remote:${remoteModelSlot(backend, remoteApiUrl)}|${model}`;
}

function same(a: unknown, b: unknown): boolean {
  if (Array.isArray(a)) {
    return Array.isArray(b) && a.length === b.length && a.every((x, i) => x === b[i]);
  }
  if (typeof a === 'number' && typeof b === 'number') return Math.abs(a - b) <= 1e-6;
  return a === b;
}

/** The host's SamplerValues.matchedBy: every key [preset] sets matches. */
export function matchedBy(preset: SamplerValues, values: SamplerValues): boolean {
  return SAMPLER_KEYS.every((k) => preset[k] === undefined || same(preset[k], values[k]));
}

/** The bar's badge for what the page shows now (it may be unsaved). */
export function presetState(data: GenPresets, shown: SamplerValues): GenPresets['state'] {
  const slot = data.slot && data.presets.find((p) => p.name === data.slot);
  if (!slot) return 'notSaved';
  return matchedBy(slot.values, shown) ? 'saved' : 'edited';
}

export const fmt = (v: unknown): string =>
  typeof v === 'number' ? String(Math.round(v * 1000) / 1000) : String(v);

/** The ↺ beside a slider: back to the model's recommended value (else the
 *  app's), only while the value differs. The title names the source. */
export function resetFor(
  rec: Recommended | undefined,
  key: SamplerKey,
  value: unknown,
): { value: number; title: string } | undefined {
  const target = rec?.resetValues[key];
  if (typeof target !== 'number' || same(target, value)) return undefined;
  const words = rec && rec.values[key] !== undefined ? rec.sourceWords : 'app default';
  return { value: target, title: `Reset to ${fmt(target)}, ${words}` };
}

/** The recommended line under the bar. */
export function recommendedLine(data: GenPresets): string {
  const label = data.model?.label;
  const rec = data.recommended;
  if (!label) return 'Choose a chat model to see its recommended values.';
  const parts = SAMPLER_KEYS.filter((k) => typeof rec.values[k] === 'number').map(
    (k) => `${SHORT[k]} ${fmt(rec.values[k])}`,
  );
  if (rec.source === 'none' || parts.length === 0) {
    return `No recommended values are known for ${label}. Resets use the app defaults.`;
  }
  return `${label}: ${parts.join(', ')}, ${rec.sourceWords}.`;
}

const SHORT: Partial<Record<SamplerKey, string>> = {
  temperature: 'temp', minP: 'min-P', topP: 'top-P', topK: 'top-K',
  repeatPenalty: 'rep pen', repeatPenaltyTokens: 'rep pen tokens',
  xtcThreshold: 'XTC threshold', xtcProbability: 'XTC probability',
  dryMultiplier: 'DRY', dynamicTempRange: 'dynatemp range', maxLength: 'max output',
};

/** The settings snapshot pieces a preset reads: the generation block and
 *  the two thinking fields beside it. */
export interface PresetHost {
  generation: object;
  reasoningEnabled: boolean;
  reasoningEffort: string;
}

/** What the Settings page shows, as a preset's values. */
export function valuesShown(s: PresetHost): SamplerValues {
  const g = s.generation as Record<string, unknown>;
  const out: Record<string, unknown> = {};
  for (const k of SAMPLER_KEYS) if (g[k] !== undefined) out[k] = g[k];
  out.reasoningEnabled = s.reasoningEnabled;
  out.reasoningEffort = s.reasoningEffort;
  return out as SamplerValues;
}

/** [s] showing [v]: what the host now holds after a preset write. */
export function withValues<T extends PresetHost>(s: T, v: SamplerValues): T {
  const generation: Record<string, unknown> = { ...s.generation };
  for (const k of SAMPLER_KEYS) {
    if (k === 'reasoningEnabled' || k === 'reasoningEffort') continue;
    if (v[k] !== undefined) generation[k] = v[k];
  }
  return {
    ...s,
    generation,
    reasoningEnabled: v.reasoningEnabled ?? s.reasoningEnabled,
    reasoningEffort: v.reasoningEffort ?? s.reasoningEffort,
  };
}

/** Said on the page when its own model chip switched the chat model, so
 *  the chat's toast reads the switch's notice without a socket of its own. */
export const MODEL_SWITCHED_EVENT = 'fp:chat-model-switched';

export function announceModelSwitch(): void {
  window.dispatchEvent(new Event(MODEL_SWITCHED_EVENT));
}

/** Said by the chat page's own socket on `settings_changed`, so the toast
 *  hears a switch made elsewhere without opening another socket. */
export const SETTINGS_CHANGED_EVENT = 'fp:settings-changed';

export function announceSettingsChanged(): void {
  window.dispatchEvent(new Event(SETTINGS_CHANGED_EVENT));
}
