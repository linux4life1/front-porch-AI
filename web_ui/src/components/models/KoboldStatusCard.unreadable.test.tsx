// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The phone's "Local model" card for a model with nothing to say about it:
// the file could not be read (the host says so in `modelUnreadable`), or
// this computer is not known yet. It used to say "Reading the model file…"
// for ever in both.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const { get, post } = vi.hoisted(() => ({ get: vi.fn(), post: vi.fn() }));
vi.mock('../../api/client', () => ({ api: { get, post }, ApiError: class extends Error {} }));

import { KoboldStatusCard, type LocalModel } from './KoboldStatusCard';

const NO_FACTS: LocalModel = {
  model: '/m/Gone-7B-Q4_K_M.gguf',
  modelName: 'Gone 7B',
  running: false,
  phase: 'stopped',
  preset: null,
  auto: null,
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

const text = () => container.querySelector('[data-testid="local-model-card"]')!.textContent ?? '';

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

describe('the Local model card with nothing to say about the model', () => {
  it('says the file could not be read, not that it is being read', async () => {
    await show({ ...NO_FACTS, modelUnreadable: true });
    expect(text()).toContain('The model file could not be read.');
    expect(text()).not.toContain('Reading the model file');
  });

  it('a readable model on a computer not known yet says that instead', async () => {
    await show({ ...NO_FACTS, modelUnreadable: false });
    expect(text()).toContain('Still finding out what this computer can do…');
    expect(text()).not.toContain('could not be read');
  });

  it('no model chosen asks for one', async () => {
    await show({ ...NO_FACTS, model: '', modelName: null, modelUnreadable: false });
    expect(text()).toContain('Choose a model below to see how it runs here.');
  });
});
