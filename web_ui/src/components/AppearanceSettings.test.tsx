// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Appearance card's Dark mode switch waits for the desktop to say which
// mode it is in, then unlocks. It must unlock even when the browser refuses
// to store the theme (Safari private tabs, full storage).

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { AppearanceSettings } from './AppearanceSettings';
import { api } from '../api/client';
import { receiveThemeWire } from '../theme/appTheme';

let host: HTMLDivElement;
let root: Root;

beforeEach(() => {
  localStorage.clear();
  host = document.createElement('div');
  document.body.appendChild(host);
  root = createRoot(host);
});

afterEach(() => {
  act(() => root.unmount());
  host.remove();
  vi.restoreAllMocks();
});

it('unlocks Dark mode once the desktop speaks, even with storage refused', () => {
  vi.spyOn(Storage.prototype, 'setItem').mockImplementation(() => {
    throw new Error('QuotaExceededError');
  });
  act(() => root.render(createElement(AppearanceSettings)));
  const dark = host.querySelector<HTMLInputElement>('input[aria-label="Dark mode"]')!;
  expect(dark.disabled).toBe(true);

  act(() => {
    receiveThemeWire({ mode: 'light', dark: { bg: '#1b1611' }, light: { bg: '#f8f4ed' } });
  });
  expect(dark.disabled).toBe(false);
  expect(dark.checked).toBe(false);
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
