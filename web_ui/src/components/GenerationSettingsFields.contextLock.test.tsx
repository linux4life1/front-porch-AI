// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The phone's Context size slider while KoboldCpp runs a preset: the preset
// sets the context, so the slider is locked and says why in the desktop's
// words (a finger has no tooltip to read them from). The host refuses the
// save as well (settings_context_lock_test.dart).

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { CONTEXT_LOCKED, GenerationSettingsFields, type GenSettings } from './GenerationSettingsFields';

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
const patch = vi.fn();

async function show(contextLocked: boolean) {
  await act(async () => {
    root.render(
      createElement(GenerationSettingsFields, {
        backend: 'kobold',
        isLocal: true,
        contextSize: 32768,
        contextLocked,
        generation: GENERATION,
        reasoningEnabled: false,
        reasoningEffort: 'medium',
        patch,
        patchGen: vi.fn(),
      }),
    );
  });
}

const contextInputs = () => {
  const field = Array.from(container.querySelectorAll('.slider-field')).find((f) =>
    f.textContent?.includes('Context size'),
  )!;
  return Array.from(field.querySelectorAll('input'));
};

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  patch.mockReset();
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

describe('the Context size slider under a preset', () => {
  it('is locked, and says why in the desktop’s words', async () => {
    await show(true);
    const inputs = contextInputs();
    expect(inputs).toHaveLength(2);
    expect(inputs.every((i) => i.disabled)).toBe(true);
    expect(container.textContent).toContain(
      'Context size is controlled by the active .kcpps preset and cannot be edited here.',
    );
    expect(CONTEXT_LOCKED).toBe(
      'Context size is controlled by the active .kcpps preset and cannot be edited here.',
    );
  });

  it('is free without one, with nothing said', async () => {
    await show(false);
    expect(contextInputs().every((i) => !i.disabled)).toBe(true);
    expect(container.textContent).not.toContain('controlled by the active .kcpps preset');
  });

  it('other sliders are not locked with it', async () => {
    await show(true);
    const temperature = Array.from(container.querySelectorAll('.slider-field')).find((f) =>
      f.textContent?.includes('Temperature'),
    )!;
    expect(Array.from(temperature.querySelectorAll('input')).every((i) => !i.disabled)).toBe(true);
  });
});
