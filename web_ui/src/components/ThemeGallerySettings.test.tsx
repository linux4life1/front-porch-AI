// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Settings → Appearance → Theme gallery: the eight cards come from the host
// (each with its own preview tokens), the selected one is the host's theme,
// a click writes that theme through /api/settings, and a change made
// elsewhere repaints the selection.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { ThemeGallerySettings } from './ThemeGallerySettings';
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

const card = (key: string, label: string) => ({
  key,
  label,
  tag: key === 'porch' ? 'Default' : 'Cool',
  blurb: `${label} blurb`,
  dark: { bg: '#1b1611', surface: '#1f1913', card: '#251e17', border: '#3e3328', text: '#ffffff', muted: '#999999', 'user-bubble': '#3b82f6', 'ai-bubble': '#374151', 'porch-amber': '#f4a259' },
  light: { bg: '#f8f4ed', surface: '#fffdf9', card: '#ffffff', border: '#e5dccb', text: '#1b1611', muted: '#666666', 'user-bubble': '#3b82f6', 'ai-bubble': '#e5e7eb', 'porch-amber': '#b45309' },
});

const appearance = (themeId = 'porch') => ({
  themeId,
  accent: null,
  accentAdjusted: false,
  accentSwatches: ['#F4A259', '#E9C46A'],
  uiFont: 'inter',
  uiFontFamily: 'Inter',
  corners: 'default',
  cornerScale: 1,
  chatFont: '',
  chatFontChoices: [{ label: 'Same as the UI font', family: '' }],
  chatColors: {
    userBubble: '#3b82f6', userText: '#ffffff', aiBubble: '#374151',
    aiText: '#ffffff', dialogue: '#ffd740', action: '#90caf9',
  },
  chatColorDefaults: {
    userBubble: '#3b82f6', userText: '#ffffff', aiBubble: '#374151',
    aiText: '#ffffff', dialogue: '#ffd740', action: '#90caf9',
  },
  gallery: [card('porch', 'Porch'), card('harbor', 'Harbor')],
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

const cards = () => [...host.querySelectorAll<HTMLButtonElement>('[role="radio"]')];

it('renders the host gallery and marks the host theme', async () => {
  vi.spyOn(api, 'get').mockResolvedValue({ appearance: appearance() });
  await act(async () => {
    root.render(createElement(ThemeGallerySettings));
  });
  expect(cards()).toHaveLength(2);
  expect(cards()[0].getAttribute('aria-checked')).toBe('true');
  expect(cards()[1].getAttribute('aria-checked')).toBe('false');
  expect(cards()[1].textContent).toContain('Harbor');
  // Each card paints that theme's own tokens, host-resolved — not the page's.
  const preview = cards()[1].querySelector<HTMLElement>('.theme-gallery-preview')!;
  expect(preview.style.background).toBe('rgb(27, 22, 17)');
  const bubble = cards()[1].querySelector<HTMLElement>('.theme-gallery-bar.left')!;
  expect(bubble.style.background).toBe('rgb(55, 65, 81)');
});

it('writes the picked theme and follows a change from elsewhere', async () => {
  vi.spyOn(api, 'get').mockResolvedValue({ appearance: appearance() });
  const post = vi.spyOn(api, 'post').mockResolvedValue({});
  await act(async () => {
    root.render(createElement(ThemeGallerySettings));
  });
  await act(async () => {
    cards()[1].click();
  });
  expect(post).toHaveBeenCalledWith('/api/settings', { themeId: 'harbor' });

  await act(async () => {
    listener?.({ event: 'settings_changed', appearance: appearance('harbor') });
  });
  expect(cards()[1].getAttribute('aria-checked')).toBe('true');
  expect(cards()[0].getAttribute('aria-checked')).toBe('false');
});
