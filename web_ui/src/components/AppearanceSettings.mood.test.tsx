// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Appearance → Mood on the character on the web: the row reads the desktop's
// level and Drama and writes a change back; the Drama only moves while the
// row is on; the row is not shown while Porch Life's Realism Engine is off,
// and the Background weather group is not shown while Story Weather is off.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { AppearanceSettings } from './AppearanceSettings';
import { api } from '../api/client';

vi.mock('../api/ws', () => ({
  ChatSocket: class {
    connect() {}
    close() {}
  },
}));

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

const render = async (settings: Record<string, unknown>) => {
  vi.spyOn(api, 'get').mockResolvedValue(settings);
  const post = vi.spyOn(api, 'post').mockResolvedValue({});
  await act(async () => {
    root.render(createElement(AppearanceSettings));
  });
  await act(async () => {});
  return post;
};

const moodSelect = () => host.querySelector<HTMLSelectElement>('select[aria-label="Mood on the character"]');
const drama = () => host.querySelector<HTMLInputElement>('input[aria-label="Drama"]');

it('reads the level and the Drama from the desktop and writes a change back', async () => {
  const post = await render({ moodOnCharacter: 'portrait', moodDrama: 1.2, realism: { weatherEnabled: true, realismAllowed: true } });
  expect(moodSelect()!.value).toBe('portrait');
  expect(drama()!.disabled).toBe(false);
  expect(drama()!.value).toBe('120');
  await act(async () => {
    moodSelect()!.value = 'all';
    moodSelect()!.dispatchEvent(new Event('change', { bubbles: true }));
  });
  expect(post).toHaveBeenCalledWith('/api/settings', { moodOnCharacter: 'all' });
  expect(moodSelect()!.value).toBe('all');
});

it('the Drama only moves while the row is on', async () => {
  await render({ moodOnCharacter: 'off', moodDrama: 1 });
  expect(moodSelect()!.value).toBe('off');
  expect(drama()!.disabled).toBe(true);
  expect(host.textContent).toContain('Mood on the character');
  expect(host.textContent).toContain('Drama');
});

it('is not shown while Porch Life runs no Realism, and the weather group goes with Story Weather', async () => {
  await render({ moodOnCharacter: 'all', realism: { realismAllowed: false, weatherEnabled: false } });
  expect(host.querySelector('[data-testid="mood-on-character"]')).toBeNull();
  expect(moodSelect()).toBeNull();
  expect(host.querySelector('[data-testid="background-weather"]')).toBeNull();
  expect(host.querySelector('select[aria-label="Ambient scene"]')).toBeNull();
  // Dark mode and the device theme stay.
  expect(host.querySelector('input[aria-label="Dark mode"]')).not.toBeNull();
});

it('shows both groups when the desktop sends no Porch Life flags (an older desktop)', async () => {
  await render({ ambientScene: 'tint' });
  expect(host.querySelector('[data-testid="background-weather"]')).not.toBeNull();
  expect(host.querySelector('[data-testid="mood-on-character"]')).not.toBeNull();
  expect(host.textContent).toContain('Only in chats with a world that has climate on');
});
