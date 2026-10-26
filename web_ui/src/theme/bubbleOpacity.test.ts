// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The page's bubbles fade with the desktop's Bubble Opacity: the settings
// snapshot read at sign-in and each `settings_changed` set
// `--chat-bubble-alpha` on the page, and the bubble CSS mixes that into the
// fill only, so the text never fades.

import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { api } from '../api/client';
import { applyBubbleOpacity, asBubbleOpacity } from './bubbleOpacity';
import { useDesktopTheme } from './useDesktopTheme';

type Listener = (e: { event: string; bubbleOpacity?: unknown }) => void;
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

function Probe() {
  useDesktopTheme(true);
  return null;
}

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  document.documentElement.style.removeProperty('--chat-bubble-alpha');
  host = document.createElement('div');
  document.body.appendChild(host);
  root = createRoot(host);
});

afterEach(() => {
  act(() => root.unmount());
  host.remove();
  vi.restoreAllMocks();
});

it('sets the bubble alpha from the settings snapshot and each settings_changed', async () => {
  vi.spyOn(api, 'get').mockResolvedValue({ bubbleOpacity: 0.25 });
  await act(async () => {
    root.render(createElement(Probe));
  });
  expect(alpha()).toBe('0.25');

  await act(async () => {
    listener?.({ event: 'settings_changed', bubbleOpacity: 1 });
  });
  expect(alpha()).toBe('1');

  // An older desktop sends no opacity: the page keeps what it has.
  await act(async () => {
    listener?.({ event: 'settings_changed' });
  });
  expect(alpha()).toBe('1');
});

it('holds the value to the desktop slider range', () => {
  expect(asBubbleOpacity(0.01)).toBe(0.1);
  expect(asBubbleOpacity(4)).toBe(1);
  expect(asBubbleOpacity('0.5')).toBeNull();
  expect(asBubbleOpacity(Number.NaN)).toBeNull();
  applyBubbleOpacity('junk');
  expect(alpha()).toBe('');
});

it('fades the bubble fill, never the text', () => {
  const css = readFileSync(join(__dirname, '..', 'styles', 'insight.css'), 'utf8');
  for (const role of ['user', 'ai']) {
    const rule = new RegExp(`^\\.bubble\\.${role} \\{[^}]*\\}`, 'm').exec(css)?.[0] ?? '';
    expect(rule, `.bubble.${role}`).toContain(
      `background: color-mix(in srgb, var(--chat-${role}-bubble) calc(var(--chat-bubble-alpha, 1) * 100%), transparent)`,
    );
    expect(rule).toContain(`color: var(--chat-${role}-text)`);
    expect(rule).not.toMatch(/(^|[^-])opacity:/);
  }
});
