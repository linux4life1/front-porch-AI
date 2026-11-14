// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Settings → Generation: Off and the strength levels are ONE control (no
// separate on/off switch), and every slider names its range and explains
// itself behind an info button.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { GenerationSettingsFields, type GenSettings } from './GenerationSettingsFields';

const GEN: GenSettings = {
  temperature: 0.7, minP: 0.1, topP: 0.9, topK: 0, dryMultiplier: 0, repeatPenalty: 1.1,
  repeatPenaltyTokens: 1024, xtcThreshold: 0.1, xtcProbability: 0, maxLength: 2048,
  minLength: 0, dynamicTempEnabled: false, dynamicTempRange: 0.7, dynamicResponses: false,
  dynamicResponseInterval: 60,
};

let container: HTMLDivElement;
let root: Root;
let patches: Record<string, unknown>[];

async function show(extra: Record<string, unknown> = {}) {
  await act(async () => {
    root.render(
      createElement(GenerationSettingsFields, {
        backend: 'kobold', isLocal: true, contextSize: 16384, generation: GEN,
        reasoningEnabled: false, reasoningEffort: 'medium',
        patch: (p: Record<string, unknown>) => patches.push(p), patchGen: () => {},
        ...extra,
      }),
    );
  });
}
const chip = (title: string) =>
  [...container.querySelectorAll<HTMLButtonElement>('.thinking-strength-chip')].find(
    (b) => b.querySelector('.thinking-strength-chip-title')?.textContent === title,
  );

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  patches = [];
});
afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

describe('Thinking: Off is a level', () => {
  it('has no separate on/off checkbox and leads with Off', async () => {
    await show();
    expect(container.textContent).not.toContain('Request thinking');
    expect(chip('Off')!.classList.contains('on')).toBe(true);
  });

  it('picking a level while off turns thinking on with that level', async () => {
    await show({ reasoningEfforts: ['low', 'high'] });
    await act(async () => chip('High')!.click());
    expect(patches).toEqual([{ reasoningEnabled: true, reasoningEffort: 'high' }]);
  });

  it('Off turns thinking off', async () => {
    await show({ reasoningEnabled: true, reasoningEfforts: ['low', 'high'] });
    await act(async () => chip('Off')!.click());
    expect(patches).toEqual([{ reasoningEnabled: false }]);
  });

  it('a model with no levels still gets Off and On', async () => {
    await show({ reasoningLocalSupport: 'toggle' });
    await act(async () => chip('On')!.click());
    expect(patches).toEqual([{ reasoningEnabled: true }]);
  });

  it('a model that always thinks cannot pick Off', async () => {
    await show({ reasoningMandatory: true, reasoningEfforts: ['low', 'high'] });
    expect(chip('Off')!.disabled).toBe(true);
  });
});

describe('slider range and info', () => {
  it('shows both ends of each track at slider precision', async () => {
    await show();
    const ends = container.querySelector('.slider-ends')!.textContent;
    expect(ends).toBe('0.002.00');
  });

  it('opens the explanation behind the info button', async () => {
    await show();
    const btn = container.querySelector<HTMLButtonElement>('button[aria-label="About Temperature"]')!;
    expect(container.textContent).not.toContain('Controls randomness');
    await act(async () => btn.click());
    expect(container.textContent).toContain('Controls randomness');
  });
});
