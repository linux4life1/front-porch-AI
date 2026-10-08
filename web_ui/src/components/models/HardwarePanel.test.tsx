// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Hardware panel's "Graphics memory" line and the one-time note for
// people who had a GPU layer count before the app moved everyone to
// Automatic. Renders the real component; the server's answers are supplied.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const { get, post } = vi.hoisted(() => ({ get: vi.fn(), post: vi.fn() }));
vi.mock('../../api/client', () => ({ api: { get, post } }));

import { HardwarePanel } from './HardwarePanel';

const CARD = { gpuName: 'NVIDIA GeForce RTX 4070', vramMb: 12288, ramMb: 32768, hasCuda: true };

let container: HTMLDivElement;
let root: Root;

async function show(hardware: Record<string, unknown>) {
  get.mockImplementation(async (path: string) =>
    path === '/api/backend/hardware' ? { ...CARD, ...hardware } : { queries: [] },
  );
  await act(async () => {
    root.render(createElement(HardwarePanel, { onPickQuery: () => {} }));
  });
}

const cell = () => container.querySelector('[data-testid="hw-graphics-memory"]')?.textContent ?? '';
const note = () => container.querySelector('[data-testid="hw-layers-retired"]');

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

describe('HardwarePanel graphics memory', () => {
  it('says Automatic and shows no note when there is nothing to tell', async () => {
    await show({ gpuLayersManual: false, gpuLayers: 0, gpuLayersRetired: null });
    expect(cell()).toContain('Automatic (KoboldCpp fits the model)');
    expect(note()).toBeNull();
  });

  it('shows a layer count set on the computer', async () => {
    await show({ gpuLayersManual: true, gpuLayers: 20 });
    expect(cell()).toContain('20 layers, set on the computer');
    expect(note()).toBeNull();
  });

  it('tells someone moved to Automatic what their number was, and "Got it" saves that and clears the note', async () => {
    await show({ gpuLayersManual: false, gpuLayers: 40, gpuLayersRetired: 40 });
    expect(note()?.textContent).toContain('GPU layers was set to 40.');

    post.mockResolvedValue({});
    const gotIt = Array.from(note()!.querySelectorAll('button')).find((b) => b.textContent === 'Got it')!;
    await act(async () => {
      gotIt.click();
    });

    expect(post).toHaveBeenCalledWith('/api/settings', { gpuLayersNoteSeen: true });
    expect(note()).toBeNull();
  });

  it('keeps the note when saving fails, so it can be tried again', async () => {
    await show({ gpuLayersRetired: 12 });
    post.mockRejectedValue(new Error('offline'));
    await act(async () => {
      note()!.querySelector('button')!.click();
    });
    expect(note()).not.toBeNull();
  });
});
