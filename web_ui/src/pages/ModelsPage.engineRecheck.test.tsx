// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Models page opened after the KoboldCpp engine file was removed. The
// host's status is its last look, so the page went on calling the engine
// installed. On opening it now asks the host to look again
// (POST /api/backend/engine/check, pinned on the Dart side by
// engine_recheck_phone_test.dart) and shows that answer.

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
vi.mock('../components/models/KoboldStatusCard', () => ({ KoboldStatusCard: () => null }));

import { ModelsPage } from './ModelsPage';

const status = (engineInstalled: boolean) => ({
  isLocal: true,
  running: false,
  starting: false,
  phase: 'stopped',
  statusMessage: '',
  loadedModel: 'a.gguf',
  engineInstalled,
});

let container: HTMLDivElement;
let root: Root;

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

const restart = () =>
  Array.from(container.querySelectorAll('button')).find((b) => b.textContent === 'Restart')!;

describe('Models page opened after the engine file was removed', () => {
  it('asks the host to look again and says the engine is missing', async () => {
    get.mockResolvedValue(status(true));
    post.mockImplementation((path: string) =>
      Promise.resolve(path === '/api/backend/engine/check' ? status(false) : undefined),
    );

    await act(async () => {
      root.render(createElement(ModelsPage));
    });

    expect(post).toHaveBeenCalledWith('/api/backend/engine/check');
    expect(container.textContent).toContain('The AI engine isn’t installed yet');
    expect(restart().disabled).toBe(true);
  });
});
