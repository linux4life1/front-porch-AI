// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Rescan on the phone's Installed models list, the twin of the desktop
// Backend tab's Rescan. The host scans the models folder on every list request
// (local_models_rescan_test.dart pins that on the Dart side), so asking again
// shows a file copied in while the app runs. The real component runs.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const { get, post } = vi.hoisted(() => ({ get: vi.fn(), post: vi.fn() }));
vi.mock('../../api/client', () => ({ api: { get, post }, ApiError: class extends Error {} }));

import { LocalModels } from './LocalModels';

const COPIED = { name: 'copied-in.gguf', path: '/m/copied-in.gguf', sizeBytes: 4e9, quant: 'Q4_K_M', paramCountB: 8, loaded: false };

let container: HTMLDivElement;
let root: Root;
const onError = vi.fn();

const rescanButton = () =>
  Array.from(container.querySelectorAll('button')).find((b) => b.textContent === 'Rescan')!;

async function show(models: unknown[]) {
  get.mockImplementation((path: string) =>
    Promise.resolve(path === '/api/backend/models' ? { models } : { path: '/m' }),
  );
  await act(async () => {
    root.render(createElement(LocalModels, { isLocal: true, reloadStatus: async () => {}, onError }));
  });
}

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

describe('Rescan on the Installed models list', () => {
  it('shows a model copied in after the page opened', async () => {
    await show([]);
    expect(container.textContent).toContain('No local models found.');

    get.mockImplementation(() => Promise.resolve({ models: [COPIED] }));
    await act(async () => rescanButton().click());

    expect(container.textContent).toContain('copied-in.gguf');
    expect(get).toHaveBeenLastCalledWith('/api/backend/models');
    expect(onError).not.toHaveBeenCalled();
  });

  it('says in plain words when the computer did not answer', async () => {
    await show([]);

    get.mockImplementation(() => Promise.reject(new TypeError('Failed to fetch')));
    await act(async () => rescanButton().click());

    expect(onError).toHaveBeenCalledTimes(1);
    const words = onError.mock.calls[0][0] as string;
    expect(words).toContain("Couldn't look for new models.");
    expect(words).toContain("didn't answer");
    expect(words).not.toContain('Failed to fetch');
  });
});
