// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The phone's "Local model" card and its KoboldCpp preset picker. Renders
// the real component; the server's answers are the ones the desktop's
// facade gives for the original author's machine (a 6 GB GTX 1060 with the
// Qwen3.6 35B MoE model), as pinned by local_model_facade_test.dart.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const { get, post } = vi.hoisted(() => ({ get: vi.fn(), post: vi.fn() }));
vi.mock('../../api/client', () => ({ api: { get, post }, ApiError: class extends Error {} }));

import { KoboldStatusCard, type LocalModel } from './KoboldStatusCard';

const verdict = (outcome: string, title: string, text: string) => ({ outcome, title, text });

const AUTO: LocalModel = {
  model: '/m/Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf',
  modelName: 'Qwen3.6 35B A3B',
  running: true,
  ready: true,
  starting: false,
  preset: null,
  auto: {
    lines: [
      'Set up for this computer automatically. The model is bigger than your graphics card, so replies come at about reading pace.',
      'Replies on long chats start fast.',
      'Going back to another chat takes a moment to catch up.',
    ],
    context: 16384,
    choices: [8192, 16384, 32768, 65536, 131072],
    largestGood: 65536,
    verdicts: {
      '8192': verdict('tooSmall', 'Not recommended or supported.', 'Below 16,384 tokens the character remembers very little of the chat. It is no faster here either.'),
      '16384': verdict('likeNow', 'Works like now.', 'Nothing else changes.'),
      '32768': verdict('likeNow', 'Works like now.', 'Replies come as fast as now.'),
      '65536': verdict('slower', 'Works, slower.', 'Replies take noticeably longer than now.'),
      '131072': verdict('tooBig', 'Too big for this computer.', 'Replies would be very slow. The most that works well here is 65,536.'),
    },
  },
  presets: [{ path: '/k/Long chats.kcpps', name: 'Long chats', line: '32k chat · fitted to the card · smart cache off' }],
};

let container: HTMLDivElement;
let root: Root;

async function show(card: LocalModel) {
  get.mockResolvedValue(card);
  await act(async () => {
    root.render(createElement(KoboldStatusCard, { onError: () => {} }));
  });
}

const text = () => container.textContent ?? '';
const button = (label: string) =>
  Array.from(container.querySelectorAll('button')).find((b) => b.textContent === label)!;
const click = async (label: string) => {
  await act(async () => {
    button(label).click();
  });
};

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

describe('KoboldStatusCard', () => {
  it('says how the model runs in plain words, with no machinery', async () => {
    await show(AUTO);
    expect(text()).toContain('Qwen3.6 35B A3B · running');
    expect(text()).toContain('Ready');
    expect(text()).toContain('replies come at about reading pace');
    expect(text()).toContain('Works like now.');
    const card = container.querySelector('[data-testid="local-model-card"]')!.textContent!;
    for (const word of ['batch', 'layer', 'expert', '8-bit', 'MMQ']) {
      expect(card.toLowerCase()).not.toContain(word.toLowerCase());
    }
  });

  it('too big: nothing is set until the user picks the one-tap fix', async () => {
    await show(AUTO);
    await click('131,072');
    expect(post).not.toHaveBeenCalled();
    expect(text()).toContain('Too big for this computer.');

    post.mockResolvedValue({ ...AUTO, auto: { ...AUTO.auto!, context: 65536 } });
    await click('Use 65,536 tokens');
    expect(post).toHaveBeenCalledWith('/api/backend/local-model/context', { context: 65536 });
    expect(text()).not.toContain('Too big');
  });

  it('keeping a size that is too big asks first', async () => {
    await show(AUTO);
    await click('131,072');
    await click('Keep 131,072 anyway…');
    expect(text()).toContain('Keep 131,072 tokens?');
    expect(post).not.toHaveBeenCalled();
    post.mockResolvedValue({ ...AUTO, auto: { ...AUTO.auto!, context: 131072 } });
    await click('Keep it');
    expect(post).toHaveBeenCalledWith('/api/backend/local-model/context', { context: 131072 });
  });

  it('below 16,384 is set, and warned about', async () => {
    await show(AUTO);
    post.mockResolvedValue({ ...AUTO, auto: { ...AUTO.auto!, context: 8192 } });
    await click('8,192');
    expect(post).toHaveBeenCalledWith('/api/backend/local-model/context', { context: 8192 });
    expect(text()).toContain('Not recommended or supported.');
  });

  it('the preset chat uses is picked from the host’s presets, and says what it does', async () => {
    await show(AUTO);
    const chosen: LocalModel = {
      ...AUTO,
      auto: null,
      preset: { path: '/k/Long chats.kcpps', name: 'Long chats', words: 'Loads Qwen3.6 35B A3B and lets KoboldCpp fit it to your card.' },
    };
    post.mockResolvedValue(chosen);
    const select = container.querySelector<HTMLSelectElement>('#kc-preset')!;
    expect(select.textContent).toContain('Long chats — 32k chat · fitted to the card · smart cache off');
    await act(async () => {
      select.value = '/k/Long chats.kcpps';
      select.dispatchEvent(new Event('change', { bubbles: true }));
    });
    expect(post).toHaveBeenCalledWith('/api/backend/local-model/preset', { path: '/k/Long chats.kcpps' });
    expect(text()).toContain('Uses your preset “Long chats”.');
    expect(text()).toContain('lets KoboldCpp fit it to your card');
  });
});
