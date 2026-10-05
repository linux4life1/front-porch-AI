// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Why KoboldCpp stopped, on the phone's Local backend card. When the engine
// stops on its own (out of graphics memory, a model it cannot read), the
// host puts the reason on the status line it already sends as
// `statusMessage` (stop_reason_phone_test.dart). The card printed that line
// only while the engine ran or started, so a stopped engine said "Stopped"
// and nothing else. Now the reason is a line of its own under "Stopped".

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

const WHY =
  'KoboldCpp ran out of graphics memory while loading the model. Try a smaller context size or a stronger cache compression.';

const status = (phase: 'stopped' | 'loading' | 'ready', statusMessage: string) => ({
  isLocal: true,
  running: phase !== 'stopped',
  starting: false,
  phase,
  statusMessage,
  loadedModel: 'model.gguf',
  engineInstalled: true,
});

let container: HTMLDivElement;
let root: Root;

async function show(s: ReturnType<typeof status>) {
  get.mockResolvedValue(s);
  await act(async () => {
    root.render(createElement(ModelsPage));
  });
}

const reason = () => container.querySelector('[data-testid="backend-stopped-why"]');

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

describe('why KoboldCpp stopped, on the Local backend card', () => {
  it('stopped with a reason: says Stopped, and why under it', async () => {
    await show(status('stopped', WHY));
    expect(container.textContent).toContain('Stopped');
    expect(reason()?.textContent).toBe(WHY);
  });

  it('stopped with nothing to say: no line', async () => {
    await show(status('stopped', ''));
    expect(container.textContent).toContain('Stopped');
    expect(reason()).toBeNull();
  });

  it('running: the status line stays where it was, with no reason line', async () => {
    await show(status('loading', 'Loading model file...'));
    expect(container.textContent).toContain('Running · Loading model file...');
    expect(reason()).toBeNull();
  });
});
