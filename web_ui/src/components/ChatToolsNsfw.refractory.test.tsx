// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The phone shows the refractory in the desktop chip's own words, ready-made
// by the facade: story minutes with Passage of Time on, replies with it off.
// Red proof: rendering the minute count instead of refractoryLabel fails the
// first two cases.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import type { ToolsState } from './ChatToolsShared';

vi.mock('../api/client', () => ({
  api: { post: vi.fn(async () => ({})) },
}));

const { ChatToolsNsfw } = await import('./ChatToolsRealism');

let container: HTMLDivElement;
let root: Root;

function state(nsfw: Partial<ToolsState['nsfw']>): ToolsState {
  return {
    realismEnabled: true,
    needsEnabled: false,
    realismOneShotEval: false,
    memory: {
      ragEnabled: false,
      ragRetrievalCount: 3,
      ragWindowSize: 5,
      journalEnabled: false,
      journalInterval: 10,
      growthEnabled: false,
      growthInterval: 10,
      growthReviewFirst: false,
    },
    summary: { text: '', paused: false, isGenerating: false, lastIndex: 0 },
    chaos: {
      enabled: false,
      nsfwEnabled: false,
      pressure: 0,
      hasPendingEvent: false,
    },
    nsfw: {
      cooldownEnabled: true,
      refractoryMinutesRemaining: 0,
      refractoryClockRunning: true,
      refractoryLabel: '',
      arousalLevel: 0,
      arousalTier: 'Neutral',
      ...nsfw,
    },
    time: {
      weekday: 'Tuesday',
      dayCount: 3,
      timeOfDay: 'evening',
      passageEnabled: true,
    },
    objectives: { primary: null, secondary: [], isChecking: false },
  };
}

function render(t: ToolsState) {
  act(() => {
    root.render(createElement(ChatToolsNsfw, { t, toggle: () => {} }));
  });
}

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT =
    true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

describe('ChatToolsNsfw refractory', () => {
  it('shows the minutes label with the clock on', () => {
    render(
      state({
        refractoryMinutesRemaining: 47,
        refractoryLabel: 'Refractory: about 45 min',
      }),
    );
    expect(container.textContent).toContain('Refractory: about 45 min');
    expect(container.textContent).not.toMatch(/turns/);
  });

  it('shows the replies label with the clock off', () => {
    render(
      state({
        refractoryMinutesRemaining: 45,
        refractoryClockRunning: false,
        refractoryLabel: 'Refractory: 3 replies',
      }),
    );
    expect(container.textContent).toContain('Refractory: 3 replies');
  });

  it('shows nothing when no refractory runs or NSFW is off', () => {
    render(state({ refractoryMinutesRemaining: 0, refractoryLabel: '' }));
    expect(container.textContent).not.toContain('Refractory');
    render(
      state({
        cooldownEnabled: false,
        refractoryMinutesRemaining: 30,
        refractoryLabel: 'Refractory: about 30 min',
      }),
    );
    expect(container.textContent).not.toContain('Refractory');
  });
});
