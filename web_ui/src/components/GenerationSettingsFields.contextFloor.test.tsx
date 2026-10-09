// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The phone's Context size slider took 2,048 with nothing said, and a max
// output as big as the whole context with nothing said either. Like the
// desktop, the number stays the user's, but below the host's floor (16,384)
// it is warned about in the desktop's words, and so is a reply that would
// take up the whole context.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { CONTEXT_FLOOR_WORDS, GenerationSettingsFields, type GenSettings } from './GenerationSettingsFields';

const GENERATION: GenSettings = {
  temperature: 0.8,
  minP: 0.05,
  repeatPenalty: 1.1,
  repeatPenaltyTokens: 64,
  xtcThreshold: 0.1,
  xtcProbability: 0,
  maxLength: 512,
  minLength: 0,
  dynamicTempEnabled: false,
  dynamicResponses: false,
  dynamicResponseInterval: 5,
};

let container: HTMLDivElement;
let root: Root;

async function show(contextSize: number, maxLength = 512, contextFloor?: number) {
  await act(async () => {
    root.render(
      createElement(GenerationSettingsFields, {
        backend: 'kobold',
        isLocal: true,
        contextSize,
        contextFloor,
        generation: { ...GENERATION, maxLength },
        reasoningEnabled: false,
        reasoningEffort: 'medium',
        patch: vi.fn(),
        patchGen: vi.fn(),
      }),
    );
  });
}

const floorWarning = () => container.querySelector('[data-testid="context-floor-warning"]');
const replyWarning = () => container.querySelector('[data-testid="context-reply-warning"]');

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

describe('the Context size slider below 16,384', () => {
  it('warns about 2,048 in the desktop’s words', async () => {
    await show(2048);
    expect(floorWarning()?.textContent).toBe(CONTEXT_FLOOR_WORDS);
    expect(CONTEXT_FLOOR_WORDS).toBe(
      '16,384 or more. Below that is not recommended or supported: ' +
        'characters remember very little of the chat.',
    );
  });

  it('says nothing from 16,384 up', async () => {
    await show(16384);
    expect(floorWarning()).toBeNull();
  });

  it('follows the floor the host sends', async () => {
    await show(16384, 512, 32768);
    expect(floorWarning()).not.toBeNull();
  });
});

describe('a max output as big as the context', () => {
  it('is warned about in plain words', async () => {
    await show(16384, 16384);
    expect(replyWarning()?.textContent).toBe(
      'Max output tokens (16,384) takes up the whole context (16,384 tokens), ' +
        'leaving no room for the character or the chat. Lower it, or raise the context.',
    );
  });

  it('says nothing while the reply leaves room', async () => {
    await show(16384, 2048);
    expect(replyWarning()).toBeNull();
  });
});
