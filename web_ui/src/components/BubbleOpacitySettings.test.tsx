// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Bubble opacity slider (Settings → Chat appearance, and the in-chat
// theme drawer): it shows the opacity the desktop paints — 0.25 with the
// Ambient scene on and nothing stored — fades this page's bubbles at once
// while dragging, posts the settled value to the desktop's setting, and
// follows a change made elsewhere (an Ambient scene switch moves the
// default) while it is open.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { BubbleOpacitySettings } from './BubbleOpacitySettings';
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
const alpha = () => document.documentElement.style.getPropertyValue('--chat-bubble-alpha');
const slider = () => host.querySelector<HTMLInputElement>('input[aria-label="Bubble opacity"]')!;

/** Moves the range input the way a drag does (React listens for `input`). */
function drag(value: string) {
  const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!;
  setter.call(slider(), value);
  slider().dispatchEvent(new Event('input', { bubbles: true }));
}

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  document.documentElement.style.removeProperty('--chat-bubble-alpha');
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

it('shows the desktop opacity and posts a drag once it settles', async () => {
  vi.useFakeTimers();
  const get = vi.spyOn(api, 'get').mockResolvedValue({ ambientScene: 'effects', bubbleOpacity: 0.25 });
  const post = vi.spyOn(api, 'post').mockResolvedValue({});
  await act(async () => {
    root.render(createElement(BubbleOpacitySettings));
  });
  expect(get).toHaveBeenCalledWith('/api/settings');
  expect(slider().disabled).toBe(false);
  expect(slider().value).toBe('0.25');
  expect(host.textContent).toContain('25%');
  expect(alpha()).toBe('0.25');

  await act(async () => {
    drag('0.6');
  });
  expect(alpha(), 'the page fades at once').toBe('0.6');
  expect(post).not.toHaveBeenCalled();
  await act(async () => {
    vi.advanceTimersByTime(300);
  });
  expect(post).toHaveBeenCalledTimes(1);
  expect(post).toHaveBeenCalledWith('/api/settings', { bubbleOpacity: 0.6 });
  expect(host.textContent).toContain('60%');
});

it('follows the Ambient scene default when it changes elsewhere', async () => {
  let desktop = 1;
  const get = vi.spyOn(api, 'get').mockImplementation(async () => ({ bubbleOpacity: desktop }));
  await act(async () => {
    root.render(createElement(BubbleOpacitySettings));
  });
  expect(slider().value).toBe('1');
  expect(get).toHaveBeenCalledTimes(1);

  // The desktop sends the value with the event: no second fetch.
  desktop = 0.25;
  await act(async () => {
    listener?.({ event: 'settings_changed', bubbleOpacity: 0.25 });
  });
  expect(slider().value).toBe('0.25');
  expect(alpha()).toBe('0.25');
  expect(get).toHaveBeenCalledTimes(1);

  // An older desktop sends the event bare: one re-read.
  desktop = 0.6;
  await act(async () => {
    listener?.({ event: 'settings_changed' });
  });
  expect(slider().value).toBe('0.6');
  expect(get).toHaveBeenCalledTimes(2);
});

it('stays disabled and leaves the bubbles alone when the desktop cannot be read', async () => {
  vi.spyOn(api, 'get').mockRejectedValue(new Error('offline'));
  const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
  await act(async () => {
    root.render(createElement(BubbleOpacitySettings));
  });
  expect(slider().disabled).toBe(true);
  expect(alpha()).toBe('');
  expect(warn).toHaveBeenCalled();
});
