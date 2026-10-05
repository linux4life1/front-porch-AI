// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Which cards the Models page shows for which backend. The Local model and
// KoboldCpp preset cards are the local backend's, as on the desktop (where
// they sit in the section only KoboldCpp has): a phone user on OpenRouter,
// oMLX or LM Studio must not get them, or the poll that feeds them.

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

const status = (isLocal: boolean) => ({
  isLocal,
  running: false,
  starting: false,
  phase: 'stopped',
  statusMessage: '',
  loadedModel: 'No model selected',
  engineInstalled: true,
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

async function open(isLocal: boolean) {
  get.mockImplementation((path: string) =>
    Promise.resolve(path === '/api/backend/status' ? status(isLocal) : card),
  );
  await act(async () => {
    root.render(createElement(ModelsPage));
  });
}

const asked = () => get.mock.calls.map((c) => c[0]);

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

describe('the Models page cards', () => {
  it('a local backend gets the Local model card and the preset picker', async () => {
    await open(true);
    expect(container.querySelector('[data-testid="local-model-card"]')).not.toBeNull();
    expect(container.querySelector('[data-testid="kobold-preset-card"]')).not.toBeNull();
    expect(container.textContent).toContain('Local backend');
  });

  it('a remote backend gets neither, nor the poll that feeds them', async () => {
    await open(false);
    expect(container.textContent).toContain('Models & backends');
    expect(container.querySelector('[data-testid="local-model-card"]')).toBeNull();
    expect(container.querySelector('[data-testid="kobold-preset-card"]')).toBeNull();
    expect(container.textContent).not.toContain('Local backend');
    expect(asked()).toContain('/api/backend/status');
    expect(asked()).not.toContain('/api/backend/local-model');
  });
});
