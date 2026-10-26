// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Ambient scene control on the Appearance card (docs/design/ambient-stage.md):
// it reads the desktop's choice from the settings snapshot and writes a
// change back through the same endpoint, like the Dark mode switch beside it.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { AppearanceSettings } from './AppearanceSettings';
import { api } from '../api/client';

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
