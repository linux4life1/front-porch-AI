// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The host only knows it is an Intel Mac once it has read its processor, a
// moment after it starts. A Models page opened in that moment, on a Mac that
// can run KoboldCpp, could be told `localUnsupported` and kept that answer:
// the KoboldCpp cards stayed hidden behind the Intel sentence until the page
// was reloaded. Now the page keeps asking while the host says so, and
// follows the answer.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const { get, post } = vi.hoisted(() => ({ get: vi.fn(), post: vi.fn() }));
vi.mock('../api/client', () => ({ api: { get, post }, ApiError: class extends Error {} }));
// The rest of the page has its own tests; here it is only in the way.
vi.mock('../components/models/HardwarePanel', () => ({ HardwarePanel: () => null }));
vi.mock('../components/models/LocalModels', () => ({ LocalModels: () => null }));
vi.mock('../components/models/ModelDownloads', () => ({ ModelDownloads: () => null }));
vi.mock('../components/models/ImageGen', () => ({ ImageGen: () => null }));

import { ModelsPage } from './ModelsPage';

/// An Apple Silicon host with its engine installed: nothing else makes the
/// page ask again.
const status = (localUnsupported: boolean) => ({
  isLocal: true,
  running: false,
  starting: false,
  phase: 'stopped',
  statusMessage: '',
  loadedModel: 'No model selected',
  engineInstalled: true,
  engineDownloading: false,
  localUnsupported,
});

const card = {
  model: '/m/Llama-3.2-3B-Instruct-Q4_K_M.gguf',
  modelName: 'Llama 3.2 3B',
  running: false,
  phase: 'stopped',
  preset: null,
  auto: null,
  presets: [],
};

let container: HTMLDivElement;
let root: Root;

const sentence = () => container.querySelector('[data-testid="local-unsupported"]');
const modelCard = () => container.querySelector('[data-testid="local-model-card"]');

beforeEach(() => {
  vi.useFakeTimers();
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
  vi.useRealTimers();
});

describe('the Models page while the host reads its processor', () => {
  it('a first "unsupported" that the host takes back gives the cards back', async () => {
    let unsupported = true;
    get.mockImplementation((path: string) =>
      Promise.resolve(path === '/api/backend/status' ? status(unsupported) : card),
    );
    await act(async () => {
      root.render(createElement(ModelsPage));
    });
    expect(sentence()).not.toBeNull();
    expect(modelCard()).toBeNull();

    unsupported = false;
    await act(async () => {
      await vi.advanceTimersByTimeAsync(2500);
    });

    expect(sentence()).toBeNull();
    expect(modelCard()).not.toBeNull();
  });
});
