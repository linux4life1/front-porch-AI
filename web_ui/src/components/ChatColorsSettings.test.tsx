// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Settings → Appearance → Chat colors, now host settings: the values are the
// ones the host paints, each pick writes through /api/settings, and "Use the
// theme's chat colors" clears the host picks.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { ChatColorsSettings } from './ChatColorsSettings';
import { api } from '../api/client';

type Listener = (e: { event: string; appearance?: unknown }) => void;
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

const COLORS = {
  userBubble: '#3b82f6', userText: '#ffffff', aiBubble: '#374151',
  aiText: '#ffffff', dialogue: '#ffd740', action: '#90caf9',
};

const appearance = (chatColors = COLORS) => ({
  themeId: 'porch',
  accent: null,
  accentAdjusted: false,
  accentSwatches: ['#F4A259'],
  uiFont: 'inter',
  uiFontFamily: 'Inter',
  corners: 'default',
  cornerScale: 1,
  chatFont: '',
  chatFontChoices: [{ label: 'Same as the UI font', family: '' }],
  chatColors,
  chatColorDefaults: COLORS,
  gallery: [{
    key: 'porch', label: 'Porch', tag: 'Default', blurb: 'Warm.',
    dark: { bg: '#1b1611' }, light: { bg: '#f8f4ed' },
  }],
});

let host: HTMLDivElement;
let root: Root;

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
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

const input = (label: string) =>
  host.querySelector<HTMLInputElement>(`input[aria-label="${label}"]`)!;

it('shows the host colours and writes a pick', async () => {
  vi.spyOn(api, 'get').mockResolvedValue({
    appearance: appearance({ ...COLORS, aiBubble: '#101010' }),
  });
  const post = vi.spyOn(api, 'post').mockResolvedValue({});
  await act(async () => {
    root.render(createElement(ChatColorsSettings));
  });
  expect(host.textContent).toContain('Chat colors');
  expect(input('AI Bubble').value).toBe('#101010');

  await act(async () => {
    // React's value tracker only sees a change through the native setter.
    const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!;
    setter.call(input('User Bubble'), '#123456');
    input('User Bubble').dispatchEvent(new Event('input', { bubbles: true }));
  });
  expect(post).toHaveBeenCalledWith('/api/settings', { chatColors: { userBubble: '#123456' } });
  // Optimistic: the preview shows the pick before the host answers.
  expect(input('User Bubble').value).toBe('#123456');
});

it('keeps the desktop\u2019s row wording', async () => {
  vi.spyOn(api, 'get').mockResolvedValue({ appearance: appearance() });
  await act(async () => {
    root.render(createElement(ChatColorsSettings));
  });
  for (const label of ['User Bubble', 'User Text', 'AI Bubble', 'AI Text', 'Dialogue (Quoted)', 'Actions (*text*)']) {
    expect(input(label), label).not.toBeNull();
  }
});
