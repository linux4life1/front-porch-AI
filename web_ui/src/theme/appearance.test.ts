// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Appearance block the desktop sends (theme/appearance.ts): it parses
// defensively, paints the UI font, corner scale and chat colours, loads the
// chosen chat face, and remembers the block so a reload paints before the
// socket connects. Colours come from the host; nothing here computes one.

import { beforeEach, describe, expect, it } from 'vitest';
import {
  APPEARANCE_EVENT,
  applyAppearance,
  applyCachedAppearance,
  currentAppearanceWire,
  parseAppearanceWire,
  receiveAppearanceWire,
  type AppearanceWire,
} from './appearance';

const COLORS = {
  userBubble: '#3b82f6',
  userText: '#ffffff',
  aiBubble: '#374151',
  aiText: '#ffffff',
  dialogue: '#ffd740',
  action: '#90caf9',
};

const block = (over: Record<string, unknown> = {}): Record<string, unknown> => ({
  themeId: 'porch',
  accent: null,
  accentAdjusted: false,
  accentSwatches: ['#F4A259', '#E9C46A'],
  uiFont: 'inter',
  uiFontFamily: 'Inter',
  corners: 'default',
  cornerScale: 1,
  chatFont: '',
  chatFontChoices: [{ label: 'Same as the UI font', family: '' }],
  chatColors: { ...COLORS },
  chatColorDefaults: { ...COLORS },
  gallery: [
    {
      key: 'porch',
      label: 'Porch',
      tag: 'Default',
      blurb: 'Warm studio brown with porch amber.',
      dark: { bg: '#1b1611', 'porch-amber': '#f4a259' },
      light: { bg: '#f8f4ed', 'porch-amber': '#f4a259' },
    },
  ],
  ...over,
});

const root = () => document.documentElement;

beforeEach(() => {
  localStorage.clear();
  root().removeAttribute('style');
  document.getElementById('fpai-chat-font')?.remove();
});

describe('appearance wire', () => {
  it('parses the host block', () => {
    const w = parseAppearanceWire(block());
    expect(w?.themeId).toBe('porch');
    expect(w?.gallery).toHaveLength(1);
    expect(w?.uiFontFamily).toBe('Inter');
    expect(w?.chatFontChoices[0]).toEqual({ label: 'Same as the UI font', family: '' });
  });

  it('refuses a block it cannot paint from', () => {
    expect(parseAppearanceWire(null)).toBeNull();
    expect(parseAppearanceWire({})).toBeNull();
    expect(parseAppearanceWire(block({ gallery: 'nope' }))).toBeNull();
    // A colour role missing means the card cannot paint; fall back whole.
    expect(parseAppearanceWire(block({ chatColors: { userBubble: '#000000' } }))).toBeNull();
  });

  it('paints the bundled UI font, the corner scale and the chat colours', () => {
    applyAppearance(parseAppearanceWire(block())!);
    expect(root().style.getPropertyValue('--ui-font')).toContain("'Inter'");
    expect(root().style.getPropertyValue('--radius-scale')).toBe('1');
    // The chat colour equals the theme default, so it stays unpinned.
    expect(root().style.getPropertyValue('--chat-user-bubble')).toBe('');
  });

  it('maps an unknown family to the page stack and paints picks', () => {
    const w = parseAppearanceWire(
      block({
        uiFontFamily: 'Comic Sans',
        cornerScale: 0.25,
        chatColors: { ...COLORS, userBubble: '#101010' },
      }),
    )!;
    applyAppearance(w);
    expect(root().style.getPropertyValue('--ui-font')).toContain('system-ui');
    expect(root().style.getPropertyValue('--radius-scale')).toBe('0.25');
    expect(root().style.getPropertyValue('--chat-user-bubble')).toBe('#101010');
  });

  it('loads the chosen chat face once and clears it for the UI font', () => {
    applyAppearance(parseAppearanceWire(block({ chatFont: 'Fira Code' }))!);
    expect(root().style.getPropertyValue('--chat-font')).toContain("'Fira Code'");
    const link = document.getElementById('fpai-chat-font') as HTMLLinkElement;
    expect(link.href).toContain('family=Fira+Code');

    applyAppearance(parseAppearanceWire(block({ chatFont: '' }))!);
    expect(root().style.getPropertyValue('--chat-font')).toBe('');
  });

  it('remembers the block and repaints it before first paint', () => {
    let fired = 0;
    const onEvent = () => (fired += 1);
    window.addEventListener(APPEARANCE_EVENT, onEvent, { once: true });
    expect(receiveAppearanceWire(block({ cornerScale: 1.6 }))).not.toBeNull();
    window.removeEventListener(APPEARANCE_EVENT, onEvent);
    expect(fired).toBe(1);
    expect(currentAppearanceWire()?.cornerScale).toBe(1.6);

    root().removeAttribute('style');
    applyCachedAppearance();
    expect(root().style.getPropertyValue('--radius-scale')).toBe('1.6');
  });

  it('ignores a malformed block instead of half-painting it', () => {
    expect(receiveAppearanceWire({ themeId: 3 })).toBeNull();
    // Nothing painted from the bad block: the root keeps its blank state.
    expect(root().style.getPropertyValue('--ui-font')).toBe('');
  });
});

// Type guard: the interface stays the contract the components read.
const _typed: AppearanceWire['themeId'] = 'porch';
void _typed;
