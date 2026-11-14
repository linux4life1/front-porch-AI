// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Settings → Appearance → Accent: the theme swatch is selected when there is
// no custom accent, a swatch click writes the pick, the wheel writes any
// colour, and the note says when the host fitted the pick for readability.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { AccentPickerSettings } from './AccentPickerSettings';
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

const base = (accent: string | null, accentAdjusted = false) => ({
  themeId: 'porch',
  accent,
  accentAdjusted,
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
  gallery: [{
    key: 'porch', label: 'Porch', tag: 'Default', blurb: 'Warm.',
    dark: { bg: '#1b1611', 'porch-amber': '#f4a259' },
    light: { bg: '#f8f4ed', 'porch-amber': '#b45309' },
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

const swatches = () => [...host.querySelectorAll<HTMLButtonElement>('.accent-swatch')];
const note = () => host.textContent ?? '';

it('selects the theme accent and writes a swatch pick', async () => {
  vi.spyOn(api, 'get').mockResolvedValue({ appearance: base(null) });
  const post = vi.spyOn(api, 'post').mockResolvedValue({});
  await act(async () => {
    root.render(createElement(AccentPickerSettings));
  });
  expect(note()).toContain('Theme accent');
  expect(swatches()[0].getAttribute('aria-checked')).toBe('true');

  await act(async () => {
    swatches()[1].click();
  });
  expect(post).toHaveBeenCalledWith('/api/settings', { accent: '#F4A259' });
});

it('the theme swatch clears a custom accent', async () => {
  vi.spyOn(api, 'get').mockResolvedValue({ appearance: base('#2E7D32') });
  const post = vi.spyOn(api, 'post').mockResolvedValue({});
  await act(async () => {
    root.render(createElement(AccentPickerSettings));
  });
  expect(note()).toContain('Custom accent');
  await act(async () => {
    swatches()[0].click();
  });
  expect(post).toHaveBeenCalledWith('/api/settings', { accent: '' });
});

it('says when the host adjusted the pick for readability', async () => {
  vi.spyOn(api, 'get').mockResolvedValue({ appearance: base('#111111', true) });
  await act(async () => {
    root.render(createElement(AccentPickerSettings));
  });
  expect(note()).toContain('Custom accent, adjusted for readability');
});
