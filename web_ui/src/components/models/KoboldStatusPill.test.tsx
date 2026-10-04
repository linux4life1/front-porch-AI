// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The phone's Local model pill while KoboldCpp frees the graphics memory
// when idle: Unloaded while the model is unloaded, Loading while it loads
// back, Ready only once it is. The answers are the ones the desktop's
// facade gives at each step, as pinned by kobold_idle_unload_test.dart.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const { get, post } = vi.hoisted(() => ({ get: vi.fn(), post: vi.fn() }));
vi.mock('../../api/client', () => ({ api: { get, post }, ApiError: class extends Error {} }));

import { KoboldStatusCard, type LocalModel } from './KoboldStatusCard';

const RUNNING: LocalModel = {
  model: '/m/chat-model.gguf',
  modelName: 'chat model',
  running: true,
  ready: true,
  unloaded: false,
  starting: false,
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

const pill = () => container.querySelector('.kc-pill')!;

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

describe('the Local model pill when the model is unloaded for being idle', () => {
  it('says Unloaded while the model is unloaded', async () => {
    await show({ ...RUNNING, ready: false, unloaded: true });
    expect(pill().textContent).toBe('Unloaded');
    expect(pill().classList.contains('unloaded')).toBe(true);
    expect(container.textContent).toContain('chat model · running');
  });

  it('says Loading while it loads back', async () => {
    await show({ ...RUNNING, ready: false, unloaded: false });
    expect(pill().textContent).toBe('Loading…');
  });

  it('says Ready once it is back', async () => {
    await show(RUNNING);
    expect(pill().textContent).toBe('Ready');
  });
});
