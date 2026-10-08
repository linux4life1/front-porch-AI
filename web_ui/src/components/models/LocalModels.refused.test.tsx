// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Switching model from the phone while KoboldCpp runs. When it could not load
// the new model, the old one keeps running, and the answer carries why in
// `refused` (the desktop says the same in a snackbar). It is shown in the row
// of the model that was switched to, where the switch is made. The real
// component runs; the answer is the one the host's route gives
// (reload_refusal_phone_test.dart pins it on the Dart side).

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const { get, post } = vi.hoisted(() => ({ get: vi.fn(), post: vi.fn() }));
vi.mock('../../api/client', () => ({ api: { get, post }, ApiError: class extends Error {} }));

import { LocalModels } from './LocalModels';

const MODELS = [
  { name: 'old.gguf', path: '/m/old.gguf', sizeBytes: 4e9, quant: 'Q4_K_M', paramCountB: 8, loaded: true },
  { name: 'broken.gguf', path: '/m/broken.gguf', sizeBytes: 2e9, quant: 'Q4_K_M', paramCountB: 8, loaded: false },
  { name: 'fine.gguf', path: '/m/fine.gguf', sizeBytes: 3e9, quant: 'Q4_K_M', paramCountB: 8, loaded: false },
];

const WORDS =
  'The new model was not loaded. The previous one is still running. Not a valid GGUF model file:\n/m/broken.gguf\nThe file is probably a partial or corrupted download.';

const status = (refused: string | null) => ({
  isLocal: true,
  running: true,
  starting: false,
  phase: 'ready',
  statusMessage: '',
  loadedModel: 'old.gguf',
  refused,
});

let container: HTMLDivElement;
let root: Root;
const onError = vi.fn();
const reloadStatus = vi.fn(async () => {});

async function show() {
  get.mockImplementation((path: string) =>
    Promise.resolve(path === '/api/backend/models' ? { models: MODELS } : { path: '/m' }),
  );
  await act(async () => {
    root.render(createElement(LocalModels, { isLocal: true, reloadStatus, onError }));
  });
}

const row = (name: string) =>
  Array.from(container.querySelectorAll('li')).find((li) => li.textContent?.includes(name))!;

const use = async (name: string) => {
  await act(async () => {
    Array.from(row(name).querySelectorAll('button')).find((b) => b.textContent === 'Use')!.click();
  });
};

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  get.mockReset();
  post.mockReset();
  onError.mockReset();
  reloadStatus.mockClear();
  vi.spyOn(window, 'confirm').mockReturnValue(true);
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
  vi.restoreAllMocks();
});

describe('switching model while KoboldCpp runs', () => {
  it('shows why the new model was not loaded, in its own row', async () => {
    await show();
    post.mockResolvedValue(status(WORDS));

    await use('broken.gguf');

    expect(post).toHaveBeenCalledWith('/api/backend/models/switch', { path: '/m/broken.gguf' });
    const shown = container.querySelector('[data-testid="switch-refused"]')!;
    expect(shown.textContent).toBe(WORDS);
    expect(row('broken.gguf').contains(shown)).toBe(true);
    expect(row('fine.gguf').querySelector('[data-testid="switch-refused"]')).toBeNull();
    expect(onError).not.toHaveBeenCalled();
    expect(reloadStatus).toHaveBeenCalled();
  });

  it('says nothing when the model loaded, or the host does not send the field', async () => {
    await show();
    post.mockResolvedValue(status(null));
    await use('fine.gguf');
    expect(container.querySelector('[data-testid="switch-refused"]')).toBeNull();

    // An older app answers with the status alone.
    const { refused: _unused, ...older } = status(null);
    void _unused;
    post.mockResolvedValue(older);
    await use('fine.gguf');
    expect(container.querySelector('[data-testid="switch-refused"]')).toBeNull();
  });

  it('forgets the last refusal when the next switch is made', async () => {
    await show();
    post.mockResolvedValue(status(WORDS));
    await use('broken.gguf');
    expect(container.querySelector('[data-testid="switch-refused"]')).not.toBeNull();

    post.mockResolvedValue(status(null));
    await use('fine.gguf');
    expect(container.querySelector('[data-testid="switch-refused"]')).toBeNull();
  });
});
