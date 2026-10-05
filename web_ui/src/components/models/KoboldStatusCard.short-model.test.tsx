// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The phone's "Local model" card for a model made for less chat than the
// app needs (8,192 tokens, say): the card says, as the desktop does, that
// the model may not work well here. The words and the choices, which stop at
// the model's own length, come from the desktop's facade (KoboldStatusFacts,
// pinned by test/services/web/local_model_short_model_test.dart); this pins
// that the phone shows the words.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const { get, post } = vi.hoisted(() => ({ get: vi.fn(), post: vi.fn() }));
vi.mock('../../api/client', () => ({ api: { get, post }, ApiError: class extends Error {} }));

import { KoboldStatusCard, type LocalModel } from './KoboldStatusCard';

const WARNING =
  'This model was made for 8,192 tokens of chat. Front Porch needs at least 16,384, so it may not work well here. A model made for longer chats is recommended.';

const SHORT: LocalModel = {
  model: '/m/Old-RP-8k-Q4_K_M.gguf',
  modelName: 'Old RP 8k',
  running: false,
  phase: 'stopped',
  preset: null,
  auto: {
    lines: [
      'Set up for this computer automatically. The whole model fits on your graphics card, so replies come quickly.',
      'Replies on long chats start fast.',
      'Going back to another chat is quick.',
    ],
    context: 16384,
    choices: [8192, 16384],
    largestGood: 16384,
    verdicts: {
      '8192': {
        outcome: 'tooSmall',
        title: 'Not recommended or supported.',
        text: 'Below 16,384 tokens the character remembers very little of the chat. It is no faster here either.',
      },
      '16384': { outcome: 'likeNow', title: 'Works like now.', text: 'Nothing else changes.' },
    },
    warning: WARNING,
  },
  presets: [],
};

let container: HTMLDivElement;
let root: Root;

async function show(card: LocalModel) {
  get.mockResolvedValue(card);
  await act(async () => {
    root.render(createElement(KoboldStatusCard, { onError: () => {} }));
  });
}

const warningBox = () => container.querySelector('[data-testid="local-model-short-model"]');

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  get.mockReset();
  post.mockReset();
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

describe('KoboldStatusCard, a model made for too little chat', () => {
  it('says the model may not work well here, as a warning', async () => {
    await show(SHORT);
    const box = warningBox();
    expect(box).not.toBeNull();
    expect(box!.className).toContain('warn');
    expect(box!.textContent).toBe(WARNING);
  });

  it('says nothing more for a model made for long chats', async () => {
    await show({ ...SHORT, auto: { ...SHORT.auto!, warning: null } });
    expect(warningBox()).toBeNull();
    await show({ ...SHORT, auto: { ...SHORT.auto!, warning: undefined } });
    expect(warningBox()).toBeNull();
  });
});
