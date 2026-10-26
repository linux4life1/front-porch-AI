// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Scene sound on the Appearance card (docs/design/ambient-stage.md §5, PR
// 3): the switch and the volume read the desktop's settings, the volume
// only moves with the switch on, a change is written back (the volume once
// a drag settles), a change made elsewhere (`settings_changed`) shows, and
// the card says a tap may be needed before a browser plays sound.

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
  vi.useRealTimers();
  vi.restoreAllMocks();
});

const toggle = () => host.querySelector<HTMLInputElement>('input[aria-label="Scene sound"]')!;
const slider = () => host.querySelector<HTMLInputElement>('input[aria-label="Scene sound volume"]')!;

it('reads Scene sound off at half volume, with the slider held until it is on', async () => {
  vi.spyOn(api, 'get').mockResolvedValue({ sceneSound: false, sceneSoundVolume: 0.5 });
  const post = vi.spyOn(api, 'post').mockResolvedValue({});
  await act(async () => {
    root.render(createElement(AppearanceSettings));
  });
  expect(host.textContent).toContain('Scene sound');
  expect(host.textContent).toContain('Scene sound volume');
  expect(host.textContent).toContain('a tap in the chat may be needed');
  expect(toggle().checked).toBe(false);
  expect(slider().value).toBe('50');
  expect(slider().disabled).toBe(true);

  await act(async () => {
    toggle().click();
  });
  expect(post).toHaveBeenCalledWith('/api/settings', { sceneSound: true });
  expect(toggle().checked).toBe(true);
  expect(slider().disabled).toBe(false);
});

it('writes the volume once a drag settles', async () => {
  vi.spyOn(api, 'get').mockResolvedValue({ sceneSound: true, sceneSoundVolume: 0.3 });
  const post = vi.spyOn(api, 'post').mockResolvedValue({});
  await act(async () => {
    root.render(createElement(AppearanceSettings));
  });
  vi.useFakeTimers();
  const setValue = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!;
  for (const v of ['40', '55', '70']) {
    await act(async () => {
      setValue.call(slider(), v);
      slider().dispatchEvent(new Event('input', { bubbles: true }));
    });
  }
  expect(post).not.toHaveBeenCalled();
  await act(async () => {
    vi.advanceTimersByTime(300);
  });
  expect(post).toHaveBeenCalledTimes(1);
  expect(post).toHaveBeenCalledWith('/api/settings', { sceneSoundVolume: 0.7 });
  expect(slider().value).toBe('70');
});

it('follows a change made on the desktop, and puts a failed switch back', async () => {
  const get = vi.spyOn(api, 'get').mockResolvedValue({ sceneSound: false, sceneSoundVolume: 0.5 });
  vi.spyOn(api, 'post').mockRejectedValue(new Error('offline'));
  await act(async () => {
    root.render(createElement(AppearanceSettings));
  });
  await act(async () => {
    toggle().click();
  });
  expect(toggle().checked).toBe(false);
  expect(host.textContent).toContain('Could not change the scene sound');

  get.mockResolvedValue({ sceneSound: true, sceneSoundVolume: 0.9 });
  await act(async () => {
    listener?.({ event: 'settings_changed' });
  });
  expect(toggle().checked).toBe(true);
  expect(slider().value).toBe('90');
});

it('posts a volume still waiting when the card closes', async () => {
  vi.spyOn(api, 'get').mockResolvedValue({ sceneSound: true, sceneSoundVolume: 0.3 });
  const post = vi.spyOn(api, 'post').mockResolvedValue({});
  const own = document.createElement('div');
  document.body.appendChild(own);
  const ownRoot = createRoot(own);
  await act(async () => {
    ownRoot.render(createElement(AppearanceSettings));
  });
  vi.useFakeTimers();
  const input = own.querySelector<HTMLInputElement>('input[aria-label="Scene sound volume"]')!;
  const setValue = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!;
  await act(async () => {
    setValue.call(input, '65');
    input.dispatchEvent(new Event('input', { bubbles: true }));
  });
  expect(post).not.toHaveBeenCalled();
  act(() => ownRoot.unmount());
  expect(post).toHaveBeenCalledTimes(1);
  expect(post).toHaveBeenCalledWith('/api/settings', { sceneSoundVolume: 0.65 });
  await act(async () => {
    vi.advanceTimersByTime(1000);
  });
  expect(post).toHaveBeenCalledTimes(1);
  own.remove();
});
