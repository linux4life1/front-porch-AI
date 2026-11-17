// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Settings → Appearance → Chat colors: the desktop's live preview and paired
// matrix (chat_capsule_preview.dart, chat_color_matrix.dart) on the web.

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

it('pairs the chips by message and paints a pick in the live preview', async () => {
  vi.spyOn(api, 'get').mockResolvedValue({ appearance: appearance() });
  vi.spyOn(api, 'post').mockResolvedValue({});
  await act(async () => {
    root.render(createElement(ChatColorsSettings));
  });
  const user = host.querySelector('[data-testid="chat-colors-user"]')!;
  const ai = host.querySelector('[data-testid="chat-colors-ai"]')!;
  expect(user.querySelector('input[aria-label="User Bubble"]')).not.toBeNull();
  expect(user.querySelector('input[aria-label="AI Bubble"]')).toBeNull();
  for (const label of ['AI Bubble', 'AI Text', 'Dialogue (Quoted)', 'Actions (*text*)']) {
    expect(ai.querySelector(`input[aria-label="${label}"]`), label).not.toBeNull();
  }

  await act(async () => {
    const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!;
    setter.call(input('AI Bubble'), '#224466');
    input('AI Bubble').dispatchEvent(new Event('input', { bubbles: true }));
  });
  const preview = host.querySelector<HTMLElement>('.color-preview')!;
  expect(preview.style.getPropertyValue('--chat-ai-bubble')).toBe('#224466');
});

it('opens a bubble’s colour from its preview bubble, as the desktop does', async () => {
  vi.spyOn(api, 'get').mockResolvedValue({ appearance: appearance() });
  await act(async () => {
    root.render(createElement(ChatColorsSettings));
  });
  const opened: string[] = [];
  for (const label of ['AI Bubble', 'User Bubble']) {
    input(label).addEventListener('click', () => opened.push(label));
  }
  act(() => {
    host.querySelector<HTMLButtonElement>('button[aria-label="Customize Character bubble color"]')!.click();
    host.querySelector<HTMLButtonElement>('button[aria-label="Customize User bubble color"]')!.click();
  });
  expect(opened).toEqual(['AI Bubble', 'User Bubble']);
});
