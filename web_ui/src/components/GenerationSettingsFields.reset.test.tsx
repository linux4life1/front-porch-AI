// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Per-value reset on Settings → Generation (issue 686): a ↺ beside a
// preset-held slider only while its value differs from the chat model's
// recommended one (else the app default), titled with where that value
// comes from, and a tap puts it back. No recommended values, no ↺.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { GenerationSettingsFields, type GenSettings } from './GenerationSettingsFields';
import type { Recommended } from './genPresets/genPresets';

const GEN: GenSettings = {
  temperature: 0.6, minP: 0.3, topP: 0.9, topK: 0, dryMultiplier: 0, repeatPenalty: 1.1,
  repeatPenaltyTokens: 1024, xtcThreshold: 0.1, xtcProbability: 0, maxLength: 2048,
  minLength: 0, dynamicTempEnabled: false, dynamicTempRange: 0.7, dynamicResponses: false,
  dynamicResponseInterval: 60,
};

const REC: Recommended = {
  values: { temperature: 0.6 },
  resetValues: { temperature: 0.6, minP: 0.1, topP: 0.9, maxLength: 2048 },
  source: 'modelFile',
  sourceWords: 'recommended by the model file',
};

let container: HTMLDivElement;
let root: Root;
let patches: Partial<GenSettings>[];

async function show(generation: GenSettings, recommended?: Recommended) {
  await act(async () => {
    root.render(
      createElement(GenerationSettingsFields, {
        backend: 'kobold', isLocal: true, contextSize: 16384, generation,
        reasoningEnabled: false, reasoningEffort: 'medium', recommended,
        patch: () => {}, patchGen: (p: Partial<GenSettings>) => patches.push(p),
      }),
    );
  });
}
const resetOf = (label: string) =>
  container.querySelector<HTMLButtonElement>(`button[aria-label^="${label}:"]`);

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

describe('per-value reset on the Generation card', () => {
  it('shows only where the value differs, naming its source', async () => {
    await show(GEN, REC);
    expect(resetOf('Temperature'), 'at the recommended value').toBeNull();
    expect(resetOf('Top-P')).toBeNull();
    const minP = resetOf('Min-P')!;
    expect(minP.title).toBe('Reset to 0.1, app default');

    await show({ ...GEN, temperature: 1.2 }, REC);
    const temp = resetOf('Temperature')!;
    expect(temp.title).toBe('Reset to 0.6, recommended by the model file');
    await act(async () => {
      temp.click();
    });
    expect(patches).toEqual([{ temperature: 0.6 }]);
  });

  it('has no ↺ without the recommended values (an older host)', async () => {
    await show({ ...GEN, temperature: 1.2 });
    expect(container.querySelector('.slider-reset')).toBeNull();
  });
});
