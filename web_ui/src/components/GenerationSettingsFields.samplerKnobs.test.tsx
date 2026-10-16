// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// No dead sliders on the phone either: the host sends samplerKnobs (its
// samplerKnobsFor table, which test/services/sampler_payload_test.dart pins
// to the real requests) and the Generation card shows a setting only when
// the list names it. An older host sends no list, and the rule this card
// had before stands: XTC, DRY and banned phrases on KoboldCpp only.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { GenerationSettingsFields, type GenSettings } from './GenerationSettingsFields';

const GENERATION: GenSettings = {
  temperature: 0.8,
  minP: 0.05,
  topP: 0.95,
  topK: 40,
  dryMultiplier: 0.8,
  repeatPenalty: 1.1,
  repeatPenaltyTokens: 64,
  xtcThreshold: 0.1,
  xtcProbability: 0,
  maxLength: 512,
  minLength: 0,
  dynamicTempEnabled: true,
  dynamicTempRange: 0.5,
  dynamicResponses: false,
  dynamicResponseInterval: 5,
};

const LABELS = [
  'Min-P',
  'Top-K',
  'Repeat penalty',
  'Rep pen tokens',
  'XTC threshold',
  'XTC probability',
  'DRY strength',
  'Dynamic temperature',
  'Dynatemp range',
  'Banned phrases',
] as const;

let container: HTMLDivElement;
let root: Root;

async function show(backend: string, samplerKnobs?: string[]) {
  await act(async () => {
    root.render(
      createElement(GenerationSettingsFields, {
        backend,
        isLocal: backend === 'kobold',
        contextSize: 32768,
        generation: GENERATION,
        bannedPhrases: ['shivers down'],
        reasoningEnabled: false,
        reasoningEffort: 'medium',
        samplerKnobs,
        patch: vi.fn(),
        patchGen: vi.fn(),
      }),
    );
  });
}

/** Which of [LABELS] the card shows. */
const shown = () => {
  const text = container.textContent ?? '';
  return LABELS.filter((label) => text.includes(label));
};

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

describe('Generation card follows the host\'s sampler list', () => {
  it('KoboldCpp: every setting', async () => {
    await show('kobold', [
      'minP', 'topK', 'repeatPenalty', 'repeatPenaltyTokens',
      'xtc', 'dry', 'dynamicTemp', 'bannedPhrases',
    ]);
    expect(shown()).toEqual([...LABELS]);
  });

  it('oMLX: the repetition settings and XTC, no dynamic temperature or banned phrases', async () => {
    await show('omlx', ['minP', 'topK', 'repeatPenalty', 'repeatPenaltyTokens', 'xtc', 'dry']);
    expect(shown()).toEqual([
      'Min-P', 'Top-K', 'Repeat penalty', 'Rep pen tokens',
      'XTC threshold', 'XTC probability', 'DRY strength',
    ]);
  });

  it('xAI: none of them, and the basics stay', async () => {
    await show('openRouter', []);
    expect(shown()).toEqual([]);
    for (const basic of ['Temperature', 'Top-P', 'Max output tokens', 'Context size']) {
      expect(container.textContent).toContain(basic);
    }
  });

  it('an older host with no list keeps the old rule', async () => {
    await show('openRouter');
    expect(shown()).toEqual([
      'Min-P', 'Top-K', 'Repeat penalty', 'Rep pen tokens',
      'Dynamic temperature', 'Dynatemp range',
    ]);
  });
});
