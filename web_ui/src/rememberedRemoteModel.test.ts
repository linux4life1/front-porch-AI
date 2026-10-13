// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { describe, expect, it } from 'vitest';
import { parkRemoteModel, rememberedRemoteModel, remoteModelSlot } from './remoteApiKeys';

const OR = 'https://openrouter.ai/api/v1';
const NANO = 'https://nano-gpt.com/api/v1';

describe('remembered model per backend', () => {
  const models = { [OR]: 'x-ai/grok-4.6', [NANO]: 'moonshotai/kimi' };

  it('finds each host its own model, whatever the URL spelling', () => {
    expect(rememberedRemoteModel('openRouter', OR, models)).toBe('x-ai/grok-4.6');
    expect(rememberedRemoteModel('openRouter', 'https://Nano-GPT.com/api/v1/', models)).toBe('moonshotai/kimi');
  });

  it('gives KoboldCpp and an unknown host nothing', () => {
    expect(remoteModelSlot('kobold', OR)).toBe('');
    expect(rememberedRemoteModel('kobold', OR, models)).toBe('');
    expect(rememberedRemoteModel('openRouter', 'https://api.x.ai/v1', models)).toBe('');
    expect(rememberedRemoteModel('openRouter', OR, undefined)).toBe('');
  });

  it('keeps oMLX on its own address, not the saved OpenRouter URL', () => {
    const withOmlx = { ...models, 'http://localhost:8000/v1': 'mlx/foo' };
    expect(rememberedRemoteModel('omlx', OR, withOmlx)).toBe('mlx/foo');
  });

  it('parks an unsaved pick, and a blank never wipes one', () => {
    const parked = parkRemoteModel('openRouter', `${OR}/`, 'openai/gpt-5', models);
    expect(rememberedRemoteModel('openRouter', OR, parked)).toBe('openai/gpt-5');
    expect(Object.keys(parked)).toHaveLength(2);
    expect(parkRemoteModel('openRouter', NANO, '  ', models)).toEqual(models);
    expect(parkRemoteModel('kobold', OR, 'x', models)).toEqual(models);
  });
});
