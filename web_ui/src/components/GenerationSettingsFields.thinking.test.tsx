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

  it('commits typed values beyond slider max without clamping', async () => {
    const genPatches: Partial<GenSettings>[] = [];
    await show({ patchGen: (p: Partial<GenSettings>) => genPatches.push(p) });
    const numInput = container.querySelector<HTMLInputElement>('.slider-val')!;
    await act(async () => {
      const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!;
      setter.call(numInput, '2.5');
      numInput.dispatchEvent(new Event('input', { bubbles: true }));
    });
    expect(genPatches).toEqual([{ temperature: 2.5 }]);
  });
});

describe('Output pipeline editors', () => {
  it('supports adding, duplicate warning, inline editing, and reordering sanitizer rules', async () => {
    const genPatches: Partial<GenSettings>[] = [];
    const rules = [
      { id: 1, find: '—', replace: ' - ', stop_after_match: false },
      { id: 2, find: '…', replace: '...', stop_after_match: false },
    ];
    await show({
      generation: { ...GEN, outputSanitizerEnabled: true, outputSanitizerRules: rules },
      patchGen: (p: Partial<GenSettings>) => genPatches.push(p),
    });

    const findBox = container.querySelector<HTMLInputElement>('.sanitizer-find-input')!;
    const replaceBox = container.querySelector<HTMLInputElement>('.sanitizer-replace-input')!;
    const addBtn = container.querySelector<HTMLButtonElement>('.sanitizer-add-btn')!;
    const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!;

    await act(async () => {
      setter.call(findBox, '—');
      findBox.dispatchEvent(new Event('input', { bubbles: true }));
      setter.call(replaceBox, ' - ');
      replaceBox.dispatchEvent(new Event('input', { bubbles: true }));
    });
    await act(async () => addBtn.click());
    expect(container.querySelector('.sanitizer-warn-text')?.textContent).toBe('Rule already exists');

    const moveDownFirst = container.querySelectorAll<HTMLButtonElement>('button[aria-label="Move rule down"]')[0]!;
    await act(async () => moveDownFirst.click());
    expect(genPatches.at(-1)?.outputSanitizerRules?.map((r) => r.id)).toEqual([2, 1]);

    const inlineFind = container.querySelectorAll<HTMLInputElement>('.sanitizer-inline-input')[0]!;
    await act(async () => {
      setter.call(inlineFind, '***');
      inlineFind.dispatchEvent(new Event('input', { bubbles: true }));
    });
    expect(genPatches.at(-1)?.outputSanitizerRules?.[0].find).toBe('***');
  });
});
