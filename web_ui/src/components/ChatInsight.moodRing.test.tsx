// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Mood on the character in the insight panel: the portrait wrap wears the
// tone and the desktop's hue, a need in trouble throbs (hygiene inverted for
// a character who enjoys it low), and nothing of it shows with the level
// off, with Realism off for the chat, or without the desktop's colours.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import type { Realism } from './chatTypes';
import { moodPaintsOf, type MoodLook, type MoodPaints } from '../theme/moodAtmosphere';

vi.mock('../api/client', () => ({
  ApiError: class ApiError extends Error {},
  api: { get: () => new Promise(() => {}), post: () => new Promise(() => {}) },
}));

const { ChatInsight } = await import('./ChatInsight');

const paints: MoodPaints = moodPaintsOf({
  tones: { sour: '#ff5252', low: '#607d8b', anxious: '#7c4dff', lifted: '#ffc107', warm: '#ff4081', charged: '#ffab40' },
  dark: {
    needs: { hunger: '#ffab40', bladder: '#40c4ff', energy: '#ffd740', social: '#ff4081', fun: '#7c4dff', hygiene: '#18ffff', comfort: '#69f0ae' },
    haloWarm: '#ff4081', haloChill: '#448aff',
  },
  light: {
    needs: { hunger: '#a03c08', bladder: '#075985', energy: '#92400e', social: '#9d174d', fun: '#6d28d9', hygiene: '#155e75', comfort: '#1b5e20' },
    haloWarm: '#9d174d', haloChill: '#1d4ed8',
  },
}, 'dark')!;

const base: Realism = {
  realismEnabled: true,
  bond: { score: 40, tier: 'Friendly', percent: 0.7 },
  longTerm: { score: 0, tier: 'Neutral', percent: 0.5 },
  trust: { level: 55, tier: 'Trusting', percent: 0.78 },
  emotion: 'joy',
  emotionIntensity: 'strong',
  emotionHeld: 0,
  mood: 'joy (strong)',
  arousal: { level: 0, tier: 'None' },
  fixation: '',
  needsEnabled: true,
  needs: { hunger: 64, energy: 12, hygiene: 92, comfort: 77 },
};

let container: HTMLDivElement;
let root: Root;

function render(realism: Realism, moodLook: MoodLook, moodPaints: MoodPaints | null = paints) {
  act(() => {
    root.render(
      createElement(ChatInsight, {
        realism,
        moodLook,
        moodPaints,
        lorebook: [],
        authorNote: '',
        authorNoteDepth: 4,
        onSaveAuthorNote: () => {},
        characterId: 'c1',
        isGroup: false,
        focusedIsHost: true,
        toolsKey: 0,
        focusedId: null,
        onCommand: () => {},
      }),
    );
  });
}

const statOf = (label: string) =>
  [...container.querySelectorAll('.stat')].find((s) => s.querySelector('.stat-head span')?.textContent === label) ?? null;

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

it('the portrait wears the tone in the desktop hue, and a low need throbs', () => {
  render(base, { level: 'portrait', drama: 1 });
  const wrap = container.querySelector<HTMLElement>('[data-testid="mood-portrait"]')!;
  expect(wrap.className).toBe('mood-portrait on tone-lifted need');
  expect(wrap.style.getPropertyValue('--mood-hue')).toBe('#ffc107');
  expect(wrap.style.getPropertyValue('--mood-a')).toBe('0.850');
  expect(wrap.style.getPropertyValue('--mood-halo')).toBe('#ff4081');
  expect(wrap.style.getPropertyValue('--mood-need')).toBe('#ffd740');
  const energy = statOf('Energy')!;
  expect(energy.className).toBe('stat need-low');
  expect((energy as HTMLElement).style.getPropertyValue('--need-hue')).toBe('#ffd740');
  expect(energy.querySelector('.need-badge')?.textContent).toBe('!');
  // Hygiene at 92 is fine for a character who does not enjoy it low.
  expect(statOf('Hygiene')!.className).toBe('stat');
});

it('hygiene inverts for a character who enjoys it low', () => {
  render({ ...base, enjoysLowHygiene: true, needs: { ...base.needs, energy: 80 } }, { level: 'portrait', drama: 1 });
  const hygiene = statOf('Hygiene')!;
  expect(hygiene.className).toBe('stat need-low need-critical need-inverted');
  expect(hygiene.querySelector('.need-badge')?.textContent).toBe('↕');
  expect(statOf('Energy')!.className).toBe('stat');
  expect(container.querySelector<HTMLElement>('[data-testid="mood-portrait"]')!.style.getPropertyValue('--mood-need')).toBe('#18ffff');
});

it('paints nothing with the level off, with Realism off for the chat, or without the colours', () => {
  render(base, { level: 'off', drama: 1 });
  expect(container.querySelector('[data-testid="mood-portrait"]')!.className).toBe('mood-portrait');
  expect(container.querySelector('.stat.need-low')).toBeNull();
  render({ ...base, realismEnabled: false }, { level: 'all', drama: 1 });
  expect(container.querySelector('[data-testid="mood-portrait"]')!.className).toBe('mood-portrait');
  render(base, { level: 'all', drama: 1 }, null);
  expect(container.querySelector('[data-testid="mood-portrait"]')!.className).toBe('mood-portrait');
  expect(container.querySelector('.stat.need-low')).toBeNull();
});
