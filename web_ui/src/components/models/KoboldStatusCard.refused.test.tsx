// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Two things the phone's Local model card says about a model change that was
// not made, as the desktop does:
//
// - a preset the host will not start KoboldCpp from (one that asks it to run a
//   program or open itself to the internet) is refused at the pick with a
//   reason, shown beside the picker where it was picked. It does not become
//   chat's preset, so the picker stays where it was;
// - the status line the desktop shows (a load in progress, or why a model
//   change was not made while the old model keeps running) rides on the card,
//   which refreshes on its own.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const { get, post } = vi.hoisted(() => ({ get: vi.fn(), post: vi.fn() }));
vi.mock('../../api/client', () => ({ api: { get, post }, ApiError: class extends Error {} }));

import { KoboldStatusCard, type LocalModel } from './KoboldStatusCard';

const CARD: LocalModel = {
  model: '/m/Llama-3.2-3B-Instruct-Q4_K_M.gguf',
  modelName: 'Llama 3.2 3B',
  running: true,
  phase: 'ready',
  preset: null,
  auto: null,
  presets: [
    { path: '/k/Risky.kcpps', name: 'Risky', line: '8k chat' },
    { path: '/k/Fine.kcpps', name: 'Fine', line: '8k chat' },
  ],
};

const REFUSAL =
  'This preset asks KoboldCpp to run a program or open itself to the internet (mcpfile, remotetunnel). The app does not start presets like that: remove those settings from the file, or pick another preset.';

let container: HTMLDivElement;
let root: Root;
const onError = vi.fn();

async function show(card: LocalModel) {
  get.mockResolvedValue(card);
  await act(async () => {
    root.render(createElement(KoboldStatusCard, { onError }));
  });
}

const pick = async (path: string) => {
  const select = container.querySelector<HTMLSelectElement>('#kc-preset')!;
  await act(async () => {
    select.value = path;
    select.dispatchEvent(new Event('change', { bubbles: true }));
  });
  return select;
};

const shown = (id: string) => container.querySelector(`[data-testid="${id}"]`);

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  get.mockReset();
  post.mockReset();
  onError.mockReset();
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

describe('a preset the host refuses', () => {
  it('is explained beside the picker, which stays where it was', async () => {
    await show(CARD);
    post.mockRejectedValue(new Error(REFUSAL));

    const select = await pick('/k/Risky.kcpps');

    expect(post).toHaveBeenCalledWith('/api/backend/local-model/preset', { path: '/k/Risky.kcpps' });
    expect(shown('preset-refused')!.textContent).toBe(REFUSAL);
    expect(container.querySelector('[data-testid="kobold-preset-card"]')!.contains(shown('preset-refused'))).toBe(true);
    expect(select.value).toBe('');
    expect(container.textContent).not.toContain('Uses your preset');
    expect(onError).not.toHaveBeenCalled();
  });

  it('is forgotten when another preset is picked', async () => {
    await show(CARD);
    post.mockRejectedValue(new Error(REFUSAL));
    await pick('/k/Risky.kcpps');
    expect(shown('preset-refused')).not.toBeNull();

    post.mockResolvedValue({
      ...CARD,
      preset: { path: '/k/Fine.kcpps', name: 'Fine', words: 'Loads Llama 3.2 3B.' },
    });
    await pick('/k/Fine.kcpps');

    expect(shown('preset-refused')).toBeNull();
    expect(container.textContent).toContain('Uses your preset “Fine”.');
  });
});

describe('the status line on the card', () => {
  it('says why a model change was not made while the old model keeps running', async () => {
    await show({
      ...CARD,
      statusMessage: 'KoboldCpp could not load broken.gguf; it went back to koboldcpp/old.',
    });

    expect(shown('local-model-status')!.textContent).toBe(
      'KoboldCpp could not load broken.gguf; it went back to koboldcpp/old.',
    );
    expect(container.textContent).toContain('Llama 3.2 3B · running');
    expect(container.textContent).toContain('Ready');
  });

  it('has no line when there is nothing to say, or the host does not send one', async () => {
    await show({ ...CARD, statusMessage: '' });
    expect(shown('local-model-status')).toBeNull();

    await show(CARD);
    expect(shown('local-model-status')).toBeNull();
  });
});
