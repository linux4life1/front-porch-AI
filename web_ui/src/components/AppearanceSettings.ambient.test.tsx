// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Ambient scene control on the Appearance card (docs/design/ambient-stage.md):
// it reads the desktop's choice from the settings snapshot, writes a change
// back through the same endpoint like the Dark mode switch beside it, and
// follows a change made elsewhere (`settings_changed`) while it is open.

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

it('reads the ambient scene from the desktop and writes a change back', async () => {
  const get = vi.spyOn(api, 'get').mockResolvedValue({ ambientScene: 'tint' });
  const post = vi.spyOn(api, 'post').mockResolvedValue({});
  await act(async () => {
    root.render(createElement(AppearanceSettings));
  });
  const select = host.querySelector<HTMLSelectElement>('select[aria-label="Ambient scene"]')!;
  expect(get).toHaveBeenCalledWith('/api/settings');
  expect(select.disabled).toBe(false);
  expect(select.value).toBe('tint');

  await act(async () => {
    select.value = 'off';
    select.dispatchEvent(new Event('change', { bubbles: true }));
  });
  expect(post).toHaveBeenCalledWith('/api/settings', { ambientScene: 'off' });
  expect(select.value).toBe('off');
});

it('follows a change made on the desktop while the card is open', async () => {
  let desktop = 'off';
  vi.spyOn(api, 'get').mockImplementation(async () => ({ ambientScene: desktop }));
  await act(async () => {
    root.render(createElement(AppearanceSettings));
  });
  const select = host.querySelector<HTMLSelectElement>('select[aria-label="Ambient scene"]')!;
  expect(select.value).toBe('off');

  desktop = 'tint';
  await act(async () => {
    listener?.({ event: 'settings_changed' });
  });
  expect(select.value).toBe('tint');

  // Unmounting closes the socket; nothing re-reads after that.
  act(() => root.unmount());
  expect(listener).toBeNull();
  root = createRoot(host);
});

it('stays disabled and harmless when the desktop cannot be read', async () => {
  vi.spyOn(api, 'get').mockRejectedValue(new Error('offline'));
  const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
  await act(async () => {
    root.render(createElement(AppearanceSettings));
  });
  const select = host.querySelector<HTMLSelectElement>('select[aria-label="Ambient scene"]')!;
  expect(select.disabled).toBe(true);
  expect(select.value).toBe('off');
  expect(warn).toHaveBeenCalled();
});
