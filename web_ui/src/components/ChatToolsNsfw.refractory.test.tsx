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

// This chat's own Afterglow switch, back on the phone: it shows while Porch
// Life (with 18+) allows Afterglow, even with the chat switched off, and posts
// the route name it had before October. Red proof: rendering the section only
// while Afterglow runs hides the switch in the first case.
describe('ChatToolsNsfw Afterglow switch', () => {
  it("shows this chat's own switch while Porch Life allows it, even off", () => {
    const calls: Array<[string, boolean]> = [];
    act(() => {
      root.render(
        createElement(ChatToolsNsfw, {
          t: state({ cooldownEnabled: false, afterglowAllowed: true, afterglowSwitch: false }),
          toggle: (name: string, v: boolean) => {
            calls.push([name, v]);
          },
        }),
      );
    });
    const box = container.querySelector<HTMLInputElement>('input[type="checkbox"]');
    expect(box?.checked).toBe(false);
    expect(container.textContent, 'no Lust while it is off').not.toContain('Lust');
    act(() => box?.click());
    expect(calls).toEqual([['nsfwCooldown', true]]);
  });

  it('shows nothing while Porch Life does not allow it', () => {
    render(state({ cooldownEnabled: false, afterglowAllowed: false, afterglowSwitch: true }));
    expect(container.textContent).toBe('');
  });

  it("shows nothing while the chat's Realism is off, as on the desktop", () => {
    render({ ...state({ afterglowAllowed: true, afterglowSwitch: true }), realismEnabled: false });
    expect(container.textContent).toBe('');
  });
});
