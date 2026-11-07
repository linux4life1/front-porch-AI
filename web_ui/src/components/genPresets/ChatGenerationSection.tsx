// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "Generation for this chat" in the chat settings drawer: the desktop's Chat
// Settings Generation section (ChatGenerationSettings). A preset can be
// loaded into the chat, and each value set here is this chat's own and sits
// on top of the global one (which follows the model); ↺ hands a value back
// to the global one. 1:1 and group chats work the same way. Only the
// sliders this backend's requests carry show, as in Settings.

import { useCallback, useEffect, useRef, useState } from 'react';
import { api, ApiError } from '../../api/client';
import { SliderField, samplerKnobShown, type SamplerKnob } from '../GenerationSettingsFields';
import {
  fmt,
  matchedBy,
  type ChatGeneration,
  type SamplerKey,
  type SamplerValues,
} from './genPresets';
import { useGenPresets } from './useGenPresets';

type Slider = [SamplerKey, string, number, number, number, SamplerKnob | null, boolean?];

// key, label, min, max, step, the knob that hides it, whole numbers.
const SLIDERS: Slider[] = [
  ['temperature', 'Temperature', 0, 2, 0.05, null],
  ['minP', 'Min-P', 0, 1, 0.01, 'minP'],
  ['topP', 'Top-P', 0.1, 1, 0.01, null],
  ['topK', 'Top-K', 0, 200, 1, 'topK', true],
  ['repeatPenalty', 'Repeat penalty', 1, 3, 0.01, 'repeatPenalty'],
  ['repeatPenaltyTokens', 'Rep pen tokens', 0, 2048, 8, 'repeatPenaltyTokens', true],
  ['xtcThreshold', 'XTC threshold', 0, 0.5, 0.01, 'xtc'],
  ['xtcProbability', 'XTC probability', 0, 1, 0.05, 'xtc'],
  ['dryMultiplier', 'DRY strength', 0, 3, 0.05, 'dry'],
  ['maxLength', 'Max output tokens', 16, 16384, 16, null, true],
];

const message = (e: unknown) =>
  e instanceof ApiError || e instanceof Error ? e.message : String(e);

export function ChatGenerationSection() {
  const { data: presets } = useGenPresets(false);
  const [chat, setChat] = useState<ChatGeneration | null>(null);
  const [error, setError] = useState('');
  // The stop list as typed, blank lines and all, while the box has focus.
  const [stopDraft, setStopDraft] = useState<string | null>(null);
  const pending = useRef<Record<string, unknown>>({});
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    let alive = true;
    api
      .get<ChatGeneration>('/api/chat/generation')
      .then((c) => alive && setChat(c))
      .catch((e) => alive && setError(message(e)));
    return () => {
      alive = false;
    };
  }, []);

  const flush = useCallback(async () => {
    timer.current = null;
    const values = pending.current;
    pending.current = {};
    try {
      setChat(await api.put<ChatGeneration>('/api/chat/generation', { values }));
    } catch (e) {
      setError(message(e));
    }
  }, []);

  useEffect(
    () => () => {
      if (timer.current) {
        clearTimeout(timer.current);
        void flush();
      }
    },
    [flush],
  );

  // Shows the change at once; a slider's drag is sent once it settles.
  const set = (patch: Record<string, unknown>) => {
    setError('');
    setChat((c) => {
      if (!c) return c;
      const values: Record<string, unknown> = { ...c.values };
      for (const [k, v] of Object.entries(patch)) {
        if (v === null) delete values[k];
        else values[k] = v;
      }
      return { ...c, values: values as SamplerValues };
    });
    Object.assign(pending.current, patch);
    if (timer.current) clearTimeout(timer.current);
    timer.current = setTimeout(() => void flush(), 300);
  };

  const pickPreset = async (name: string | null) => {
    setError('');
    try {
      setChat(await api.post<ChatGeneration>('/api/chat/generation/preset', { name }));
    } catch (e) {
      setError(message(e));
    }
  };

  if (!chat?.open) return null;
  const own = chat.values ?? {};
  const global = chat.global ?? {};
  const shown = (k: SamplerKey) => own[k] ?? global[k];
  const knob = (k: SamplerKnob) => samplerKnobShown(k, chat.backend ?? '', chat.samplerKnobs);
  const clear = (k: SamplerKey) =>
    own[k] === undefined
      ? undefined
      : {
          title: `Use the global value (${fmt(global[k] ?? '')})`,
          onReset: () => set({ [k]: null }),
        };
  const name = chat.genPresetName ?? null;
  const list = presets?.presets ?? [];
  const named = name ? list.find((p) => p.name === name) : undefined;
  const badge = name
    ? named && matchedBy(named.values, own)
      ? `Using “${name}”`
      : `“${name}” (edited)`
    : chat.overrides
      ? `Following the model · ${chat.overrides} own`
      : 'Following the model';

  return (
    <section className="chat-gen" data-testid="chat-generation">
      <h4>Generation for this chat</h4>
      <div className="gp-head">
        <span className="muted small">Preset for this chat</span>
        <span className="gp-badge quiet">{badge}</span>
      </div>
      <select
        aria-label="Preset for this chat"
        value={name ?? ''}
        onChange={(e) => void pickPreset(e.target.value || null)}
      >
        <option value="">
          Follow the model{presets?.linked ? `: “${presets.linked}”` : ''}
        </option>
        {name && !named && <option value={name}>{name}</option>}
        {list.map((p) => (
          <option key={p.name} value={p.name}>{p.name}</option>
        ))}
      </select>
      <p className="muted small">
        Pick a preset here to keep it in this chat whatever the model. Changes
        below are this chat&apos;s own and sit on top.
      </p>
      {SLIDERS.filter(([, , , , , k]) => !k || knob(k)).map(([k, label, min, max, step, , whole]) => {
        const v = shown(k);
        if (typeof v !== 'number') return null;
        return (
          <SliderField key={k} label={label} value={v} min={min} max={max} step={step}
            reset={clear(k)}
            onChange={(n) => set({ [k]: whole ? Math.round(n) : n })} />
        );
      })}
      {knob('dynamicTemp') && (
        <>
          <Toggle label="Dynamic temperature" k="dynamicTempEnabled" own={own} shown={shown}
            set={set} clear={clear} />
          {shown('dynamicTempEnabled') === true && typeof shown('dynamicTempRange') === 'number' && (
            <SliderField label="Dynatemp range" value={shown('dynamicTempRange') as number}
              min={0} max={2} step={0.1} reset={clear('dynamicTempRange')}
              onChange={(n) => set({ dynamicTempRange: n })} />
          )}
        </>
      )}
      <Toggle label="Request thinking" k="reasoningEnabled" own={own} shown={shown}
        set={set} clear={clear} />
      <label>
        <span className="slider-head">
          <span>Stop sequences (one per line)</span>
          {clear('stopSequences') && (
            <button type="button" className="slider-reset" title={clear('stopSequences')!.title}
              aria-label={`Stop sequences: ${clear('stopSequences')!.title}`}
              onClick={clear('stopSequences')!.onReset}>↺</button>
          )}
        </span>
        <textarea
          rows={3}
          value={stopDraft ?? ((shown('stopSequences') as string[] | undefined) ?? []).join('\n')}
          onChange={(e) => {
            setStopDraft(e.target.value);
            set({ stopSequences: e.target.value.split('\n').filter((s) => s.length > 0) });
          }}
          onBlur={() => setStopDraft(null)}
        />
      </label>
      {error && <p className="error" role="alert">{error}</p>}
    </section>
  );
}

function Toggle({
  label,
  k,
  own,
  shown,
  set,
  clear,
}: {
  label: string;
  k: 'dynamicTempEnabled' | 'reasoningEnabled';
  own: SamplerValues;
  shown: (k: SamplerKey) => unknown;
  set: (p: Record<string, unknown>) => void;
  clear: (k: SamplerKey) => { title: string; onReset: () => void } | undefined;
}) {
  const reset = own[k] === undefined ? undefined : clear(k);
  return (
    <div className="row-label">
      <span>{label}</span>
      <span className="slider-head-right">
        {reset && (
          <button type="button" className="slider-reset" title={reset.title}
            aria-label={`${label}: ${reset.title}`} onClick={reset.onReset}>↺</button>
        )}
        <input
          type="checkbox"
          aria-label={label}
          checked={shown(k) === true}
          onChange={(e) => set({ [k]: e.target.checked })}
        />
      </span>
    </div>
  );
}
