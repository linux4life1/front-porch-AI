// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The small Appearance controls: UI font, corners, the reset, the chat font
// select and General's auto-check switch. Each writes the host setting it
// owns; the auto-check card hides on a host that has no update service.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { UiFontSettings } from './UiFontSettings';
import { CornersSettings } from './CornersSettings';
import { ThemeResetSettings } from './ThemeResetSettings';
import { ChatFontSettings } from './ChatFontSettings';
import { ChatColorsResetSettings } from './ChatColorsResetSettings';
import { AutoCheckSettings } from './AutoCheckSettings';
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

const appearance = {
  themeId: 'porch',
  accent: null,
  accentAdjusted: false,
  accentSwatches: ['#F4A259'],
  uiFont: 'inter',
  uiFontFamily: 'Inter',
  corners: 'default',
  cornerScale: 1,
  chatFont: '',
  chatFontChoices: [
    { label: 'Same as the UI font', family: '' },
    { label: 'Fira Code', family: 'Fira Code' },
  ],
  chatColors: {
    userBubble: '#3b82f6', userText: '#ffffff', aiBubble: '#374151',
    aiText: '#ffffff', dialogue: '#ffd740', action: '#90caf9',
  },
  chatColorDefaults: {
    userBubble: '#3b82f6', userText: '#ffffff', aiBubble: '#374151',
    aiText: '#ffffff', dialogue: '#ffd740', action: '#90caf9',
  },
  gallery: [{
    key: 'porch', label: 'Porch', tag: 'Default', blurb: 'Warm.',
    dark: { bg: '#1b1611' }, light: { bg: '#f8f4ed' },
  }],
};

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

const radios = () => [...host.querySelectorAll<HTMLButtonElement>('[role="radio"]')];

it('UI font: marks the host choice and writes a pick', async () => {
  vi.spyOn(api, 'get').mockResolvedValue({ appearance });
  const post = vi.spyOn(api, 'post').mockResolvedValue({});
  await act(async () => {
    root.render(createElement(UiFontSettings));
  });
  expect(radios()[0].getAttribute('aria-checked')).toBe('true');
  await act(async () => {
    radios()[2].click();
  });
  expect(post).toHaveBeenCalledWith('/api/settings', { uiFont: 'atkinson' });
});

it('Corners: marks the host choice and writes a pick', async () => {
  vi.spyOn(api, 'get').mockResolvedValue({ appearance });
  const post = vi.spyOn(api, 'post').mockResolvedValue({});
  await act(async () => {
    root.render(createElement(CornersSettings));
  });
  expect(radios()[1].getAttribute('aria-checked')).toBe('true');
  await act(async () => {
    radios()[2].click();
  });
  expect(post).toHaveBeenCalledWith('/api/settings', { corners: 'round' });
});

it('the reset posts one host write', async () => {
  const post = vi.spyOn(api, 'post').mockResolvedValue({});
  await act(async () => {
    root.render(createElement(ThemeResetSettings));
  });
  const button = host.querySelector('button')!;
  expect(button.textContent).toBe('Reset accent, font and corners');
  await act(async () => {
    button.click();
  });
  expect(post).toHaveBeenCalledWith('/api/settings', { resetAppearance: true });
});

it('the chat-colour reset posts one host write', async () => {
  const post = vi.spyOn(api, 'post').mockResolvedValue({});
  await act(async () => {
    root.render(createElement(ChatColorsResetSettings));
  });
  const button = host.querySelector('button')!;
  expect(button.textContent).toBe("Use the theme's chat colors");
  await act(async () => {
    button.click();
  });
  expect(post).toHaveBeenCalledWith('/api/settings', { resetChatColors: true });
});

it('chat font: clamps an unknown stored family to the UI font', async () => {
  vi.spyOn(api, 'get').mockResolvedValue({
    appearance: { ...appearance, chatFont: 'Comic Sans' },
  });
  const post = vi.spyOn(api, 'post').mockResolvedValue({});
  await act(async () => {
    root.render(createElement(ChatFontSettings));
  });
  const select = host.querySelector<HTMLSelectElement>('select')!;
  expect(select.value).toBe('');
  await act(async () => {
    select.value = 'Fira Code';
    select.dispatchEvent(new Event('change', { bubbles: true }));
  });
  expect(post).toHaveBeenCalledWith('/api/settings', { chatFont: 'Fira Code' });
});

it('auto-check shows the host switch and writes it', async () => {
  vi.spyOn(api, 'get').mockResolvedValue({ autoCheckForUpdates: false });
  const post = vi.spyOn(api, 'post').mockResolvedValue({});
  await act(async () => {
    root.render(createElement(AutoCheckSettings));
  });
  const box = host.querySelector<HTMLInputElement>('input[type="checkbox"]')!;
  expect(box.checked).toBe(false);
  await act(async () => {
    box.click();
  });
  expect(post).toHaveBeenCalledWith('/api/settings', { autoCheckForUpdates: true });
});

it('auto-check renders nothing on a host without the update service', async () => {
  vi.spyOn(api, 'get').mockResolvedValue({});
  await act(async () => {
    root.render(createElement(AutoCheckSettings));
  });
  expect(host.textContent).toBe('');
});
