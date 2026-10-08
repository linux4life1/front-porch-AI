// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// An Intel Mac cannot run KoboldCpp. The desktop hides its KoboldCpp section
// there and says so; the phone showed the Local backend, Local model and
// preset cards anyway, with an engine to download and restart that could
// never work. With `localUnsupported` on the status, the phone hides the
// three cards (and the cards' poll), says the desktop's sentence instead,
// and offers no "Use" on an installed model, which would only try to start
// the engine.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const { get, post, localModels } = vi.hoisted(() => ({
  get: vi.fn(),
  post: vi.fn(),
  localModels: vi.fn(),
}));
vi.mock('../api/client', () => ({ api: { get, post }, ApiError: class extends Error {} }));
// The rest of the page has its own tests; here it is only in the way.
vi.mock('../components/models/HardwarePanel', () => ({ HardwarePanel: () => null }));
vi.mock('../components/models/LocalModels', () => ({
  LocalModels: (props: { isLocal: boolean }) => {
    localModels(props.isLocal);
    return null;
  },
}));
vi.mock('../components/models/ModelDownloads', () => ({ ModelDownloads: () => null }));
vi.mock('../components/models/ImageGen', () => ({ ImageGen: () => null }));

import { ModelsPage } from './ModelsPage';
import { INTEL_MAC_LOCAL_UNSUPPORTED } from '../backendOptions';

const status = (localUnsupported: boolean | undefined, isLocal = true) => ({
  isLocal,
  running: false,
  starting: false,
  phase: 'stopped',
  statusMessage: '',
  loadedModel: 'No model selected',
  engineInstalled: false,
  ...(localUnsupported === undefined ? {} : { localUnsupported }),
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

async function open(s: ReturnType<typeof status>) {
  get.mockImplementation((path: string) =>
    Promise.resolve(path === '/api/backend/status' ? s : card),
  );
  await act(async () => {
    root.render(createElement(ModelsPage));
  });
}

const asked = () => get.mock.calls.map((c) => c[0]);
const sentence = () => container.querySelector('[data-testid="local-unsupported"]');

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  get.mockReset();
  post.mockReset();
  localModels.mockReset();
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

describe('the Models page on an Intel Mac', () => {
  it('hides the three KoboldCpp cards and says why, in the desktop\'s words', async () => {
    await open(status(true));

    expect(container.querySelector('[data-testid="local-model-card"]')).toBeNull();
    expect(container.querySelector('[data-testid="kobold-preset-card"]')).toBeNull();
    expect(container.textContent).not.toContain('Download engine');
    expect(container.textContent).not.toContain('Restart');
    expect(sentence()?.textContent).toContain(INTEL_MAC_LOCAL_UNSUPPORTED);
    expect(asked()).not.toContain('/api/backend/local-model');
    expect(localModels).toHaveBeenLastCalledWith(false);
  });

  it('says it on a remote backend too, as the desktop always does there', async () => {
    await open(status(true, false));

    expect(sentence()?.textContent).toContain(INTEL_MAC_LOCAL_UNSUPPORTED);
  });

  it('elsewhere, and from an app too old to say, the cards are as before', async () => {
    for (const s of [status(false), status(undefined)]) {
      get.mockReset();
      await open(s);

      expect(container.querySelector('[data-testid="local-model-card"]')).not.toBeNull();
      expect(container.querySelector('[data-testid="kobold-preset-card"]')).not.toBeNull();
      expect(container.textContent).toContain('Download engine');
      expect(sentence()).toBeNull();
      expect(localModels).toHaveBeenLastCalledWith(true);
    }
  });
});
