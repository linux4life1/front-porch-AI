// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The rules the phone's preset bar, ↺ buttons and model pickers share with
// the host (issue 686): link keys in the host's ChatModelId spelling, the
// saved / edited badge in SamplerValues.matchedBy's terms, and a reset that
// shows only while a value differs, naming where its value comes from.

import { describe, expect, it } from 'vitest';
import {
  chatModelKey,
  localModelKey,
  matchedBy,
  normalizeGenPresets,
  presetState,
  recommendedLine,
  resetFor,
  valuesShown,
  withValues,
  type Recommended,
} from './genPresets';

const REC: Recommended = {
  values: { temperature: 0.6 },
  resetValues: { temperature: 0.6, minP: 0.1 },
  source: 'modelFile',
  sourceWords: 'recommended by the model file',
};

describe('generation preset rules', () => {
  it('spells model keys as the host does', () => {
    expect(localModelKey('C:\\Models\\Qwen3-8B.GGUF')).toBe('local:qwen3-8b.gguf');
    expect(chatModelKey('kobold', '', '', '/m/Cydonia.gguf')).toBe('local:cydonia.gguf');
    expect(chatModelKey('kobold', '', '', '')).toBeNull();
    expect(chatModelKey('openRouter', 'https://NANO-gpt.com/api/v1/', 'zai/GLM-4.6')).toBe(
      'remote:https://nano-gpt.com/api/v1|zai/GLM-4.6',
    );
    expect(chatModelKey('openRouter', 'https://x/v1', '  ')).toBeNull();
  });

  it('matches only the keys a preset sets, floats within a hair', () => {
    expect(matchedBy({ temperature: 0.7 }, { temperature: 0.7000000001, minP: 0.3 })).toBe(true);
    expect(matchedBy({ temperature: 0.7 }, { temperature: 0.75 })).toBe(false);
    expect(matchedBy({ stopSequences: ['a'] }, { stopSequences: ['a', 'b'] })).toBe(false);
  });

  it('badges what the page shows, not what the host last saved', () => {
    const data = normalizeGenPresets({
      presets: [{ name: 'Warm', values: { temperature: 1.1 } }],
      slot: 'Warm',
      state: 'saved',
    });
    expect(presetState(data, { temperature: 1.1 })).toBe('saved');
    expect(presetState(data, { temperature: 0.9 })).toBe('edited');
    expect(presetState({ ...data, slot: null }, { temperature: 1.1 })).toBe('notSaved');
  });

  it('offers a reset only while the value differs, naming its source', () => {
    expect(resetFor(REC, 'temperature', 0.6)).toBeUndefined();
    expect(resetFor(REC, 'temperature', 0.9)).toEqual({
      value: 0.6,
      title: 'Reset to 0.6, recommended by the model file',
    });
    expect(resetFor(REC, 'minP', 0.3)?.title).toBe('Reset to 0.1, app default');
    expect(resetFor(undefined, 'temperature', 0.9)).toBeUndefined();
  });

  it('reads an empty or older host answer without throwing', () => {
    const d = normalizeGenPresets({});
    expect(d.presets).toEqual([]);
    expect(d.model).toBeNull();
    expect(recommendedLine(d)).toBe('Choose a chat model to see its recommended values.');
    expect(
      recommendedLine({ ...d, model: { key: 'local:q.gguf', label: 'Q' }, recommended: REC }),
    ).toBe('Q: temp 0.6, recommended by the model file.');
  });

  it('moves a preset in and out of the Settings snapshot shape', () => {
    const s = {
      generation: { temperature: 0.7, minLength: 3, stopSequences: ['x'] },
      reasoningEnabled: false,
      reasoningEffort: 'medium',
    };
    expect(valuesShown(s)).toEqual({
      temperature: 0.7,
      stopSequences: ['x'],
      reasoningEnabled: false,
      reasoningEffort: 'medium',
    });
    const next = withValues(s, { temperature: 1.2, reasoningEnabled: true });
    expect(next.generation).toEqual({ temperature: 1.2, minLength: 3, stopSequences: ['x'] });
    expect(next.reasoningEnabled).toBe(true);
    expect(next.reasoningEffort).toBe('medium');
  });
});
