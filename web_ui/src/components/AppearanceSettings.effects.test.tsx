// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Ambient Stage's effects controls on the Appearance card
// (docs/design/ambient-stage.md, PR 2): Tint and effects is a choice, and
// Pause effects while generating reads the desktop's setting and writes a
// change back through the same endpoint, and follows a change made
// elsewhere (`settings_changed`) like the scene choice beside it.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { AppearanceSettings } from './AppearanceSettings';
import { api } from '../api/client';

type Listener = (e: { event: string }) => void;
let listener: Listener | null = null;

vi.mock('../api/ws', () => ({
  ChatSocket: class {
    constructor(cb: Listener) {
      listener = cb;
    }
    connect() {}
    close() {
      listener = null;
    }
  },
}));

let host: HTMLDivElement;
let root: Root;

beforeEach(() => {
  localStorage.clear();
  listener = null;
  host = document.createElement('div');
  document.body.appendChild(host);
  root = createRoot(host);
});

afterEach(() => {
  act(() => root.unmount());
  host.remove();
  vi.restoreAllMocks();
});

it('offers Tint and effects and keeps the desktop choice', async () => {
  vi.spyOn(api, 'get').mockResolvedValue({ ambientScene: 'effects', pauseEffectsWhileGenerating: true });
  const post = vi.spyOn(api, 'post').mockResolvedValue({});
  await act(async () => {
    root.render(createElement(AppearanceSettings));
  });
  const select = host.querySelector<HTMLSelectElement>('select[aria-label="Ambient scene"]')!;
  expect([...select.options].map((o) => o.textContent)).toEqual(['Off', 'Tint only', 'Tint and effects']);
  expect(select.value).toBe('effects');
  await act(async () => {
    select.value = 'tint';
    select.dispatchEvent(new Event('change', { bubbles: true }));
  });
  expect(post).toHaveBeenCalledWith('/api/settings', { ambientScene: 'tint' });
});

it('reads the pause switch from the desktop and writes a change back', async () => {
  vi.spyOn(api, 'get').mockResolvedValue({ ambientScene: 'effects', pauseEffectsWhileGenerating: false });
  const post = vi.spyOn(api, 'post').mockResolvedValue({});
  await act(async () => {
    root.render(createElement(AppearanceSettings));
  });
  const box = host.querySelector<HTMLInputElement>('input[aria-label="Pause effects while generating"]')!;
  expect(box.disabled).toBe(false);
  expect(box.checked).toBe(false);
  await act(async () => {
    box.click();
  });
  expect(post).toHaveBeenCalledWith('/api/settings', { pauseEffectsWhileGenerating: true });
  expect(box.checked).toBe(true);
});

it('puts the switch back when the desktop refuses the change', async () => {
  vi.spyOn(api, 'get').mockResolvedValue({ ambientScene: 'effects' });
  vi.spyOn(api, 'post').mockRejectedValue(new Error('offline'));
  await act(async () => {
    root.render(createElement(AppearanceSettings));
  });
  const box = host.querySelector<HTMLInputElement>('input[aria-label="Pause effects while generating"]')!;
  expect(box.checked).toBe(true);
  await act(async () => {
    box.click();
  });
  expect(box.checked).toBe(true);
  expect(host.textContent).toContain('Could not change the effects pause');
});

it('follows the pause switch and Tint and effects changed on the desktop', async () => {
  let desktop: Record<string, unknown> = { ambientScene: 'tint', pauseEffectsWhileGenerating: true };
  vi.spyOn(api, 'get').mockImplementation(async () => desktop);
  await act(async () => {
    root.render(createElement(AppearanceSettings));
  });
  const select = host.querySelector<HTMLSelectElement>('select[aria-label="Ambient scene"]')!;
  const box = host.querySelector<HTMLInputElement>('input[aria-label="Pause effects while generating"]')!;
  expect(select.value).toBe('tint');
  expect(box.checked).toBe(true);

  desktop = { ambientScene: 'effects', pauseEffectsWhileGenerating: false };
  await act(async () => {
    listener?.({ event: 'settings_changed' });
  });
  expect(select.value).toBe('effects');
  expect(box.checked).toBe(false);
});
