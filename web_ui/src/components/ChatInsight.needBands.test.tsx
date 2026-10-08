// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The phone's needs bars, rendered through the real insight panel, follow the
// needs bands (docs/design/needs-on-the-clock.md, "Bands"): calm above 40,
// porch amber from 40, red from 25. A need at 1 (the on-screen wear floor)
// draws a sliver, not a full bar. Desktop twin:
// test/ui/widgets/needs_band_colours_test.dart.

import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import type { Realism } from './chatTypes';

// The panel's own requests (tools, places) never settle: nothing they would
// load is part of this pin, and nothing lands after the test.
vi.mock('../api/client', () => ({
  ApiError: class ApiError extends Error {},
  api: { get: () => new Promise(() => {}), post: () => new Promise(() => {}) },
}));

const { ChatInsight } = await import('./ChatInsight');

const realism: Realism = {
  realismEnabled: true,
  bond: { score: 12, tier: 'Friendly', percent: 0.52 },
  longTerm: { score: 4, tier: 'Warm', percent: 0.51 },
  trust: { level: 8, tier: 'Some', percent: 0.54 },
  emotion: 'calm',
  emotionIntensity: 'mild',
  mood: 'calm',
  arousal: { level: 0, tier: 'None' },
  fixation: '',
  needsEnabled: true,
  needs: { hunger: 41, bladder: 40, energy: 25, social: 1, fun: 100 },
};

let container: HTMLDivElement;
let root: Root;

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  act(() => {
    root.render(
      createElement(ChatInsight, {
        realism,
        authorNote: '',
        authorNoteDepth: 4,
        onSaveAuthorNote: () => {},
        characterId: 'c1',
        isGroup: true,
        focusedIsHost: false,
        toolsKey: 0,
        focusedId: null,
        groupId: null,
        onCommand: () => {},
      }),
    );
  });
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

function fill(label: string): HTMLElement {
  const stat = [...container.querySelectorAll('.stat')].find(
    (s) => s.querySelector('.stat-head span')?.textContent === label,
  );
  const bar = stat?.querySelector<HTMLElement>('.stat-fill');
  if (!bar) throw new Error(`no stat bar labelled ${label}`);
  return bar;
}

const TONES = ['ok', 'warn', 'danger'];
const toneOf = (bar: HTMLElement) => TONES.filter((t) => bar.classList.contains(t));

describe('ChatInsight needs bars', () => {
  it('colour by band: calm above 40, amber from 40, red from 25', () => {
    expect(toneOf(fill('Fun'))).toEqual(['ok']);
    expect(toneOf(fill('Hunger'))).toEqual(['ok']);
    expect(toneOf(fill('Bladder'))).toEqual(['warn']);
    expect(toneOf(fill('Energy'))).toEqual(['danger']);
    expect(toneOf(fill('Social'))).toEqual(['danger']);
  });

  it('draw a need at 1 as a sliver and a full need as a full bar', () => {
    expect(fill('Social').style.width).toBe('1%');
    expect(fill('Bladder').style.width).toBe('40%');
    expect(fill('Fun').style.width).toBe('100%');
  });

  it('leave the bond and trust bars on their own fill', () => {
    expect(toneOf(fill('Bond'))).toEqual([]);
    expect(toneOf(fill('Trust'))).toEqual([]);
  });

  it('paint warn in the warm-porch amber and ok in honey', () => {
    const css = readFileSync(join(__dirname, '../styles/insight.css'), 'utf8');
    expect(css).toContain('.stat-fill.ok { background: var(--porch-honey); }');
    expect(css).toContain('.stat-fill.warn { background: var(--porch-amber); }');
    expect(css).toContain('.stat-fill.danger { background: var(--danger); }');
  });
});
