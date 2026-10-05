// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Stop on the Models page while KoboldCpp is still getting ready (the host
// has claimed the start but not spawned the engine yet). Stop calls that
// start off on the desktop, and the host's stop route does the same
// (phone_stop_cancels_preparing_start_test.dart), so the phone's Stop must
// be pressable then, and the line above it must not say "Stopped".

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

const status = (running: boolean, starting: boolean) => ({
  isLocal: true,
  running,
  starting,
  phase: starting ? 'starting' : running ? 'ready' : 'stopped',
  statusMessage: '',
  loadedModel: 'model.gguf',
  engineInstalled: true,
});

let container: HTMLDivElement;
let root: Root;

async function show(running: boolean, starting: boolean) {
  get.mockResolvedValue(status(running, starting));
  await act(async () => {
    root.render(createElement(ModelsPage));
  });
}

const button = (label: string) =>
  Array.from(container.querySelectorAll('button')).find((b) => b.textContent === label)!;

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

describe('Stop while KoboldCpp is getting ready', () => {
  it('can be pressed, and the page says it is starting', async () => {
    await show(false, true);
    expect(button('Stop').disabled).toBe(false);
    expect(container.textContent).toContain('Starting');
    expect(container.textContent).not.toContain('Stopped');

    post.mockResolvedValue(status(false, false));
    await act(async () => {
      button('Stop').click();
    });
    expect(post).toHaveBeenCalledWith('/api/backend/stop');
  });

  it('stays unpressable with nothing running or starting', async () => {
    await show(false, false);
    expect(button('Stop').disabled).toBe(true);
    expect(container.textContent).toContain('Stopped');
  });
});
