// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The phone's Chaos section has the desktop's SPIN NOW: one tap posts the
// spin, and a pending event holds the button. Red proof: posting to any
// other path, or dropping the disabled guard, fails a case.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import type { ToolsState } from './ChatToolsShared';

const { post } = vi.hoisted(() => ({ post: vi.fn(async () => ({})) }));

vi.mock('../api/client', () => ({ api: { post } }));

const { ChatToolsChaos } = await import('./ChatToolsRealism');

let container: HTMLDivElement;
let root: Root;

function state(chaos: Partial<ToolsState['chaos']>): ToolsState {
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
      ...chaos,
    },
    nsfw: {
      cooldownEnabled: true,
      refractoryMinutesRemaining: 0,
      refractoryClockRunning: true,
      refractoryLabel: '',
      arousalLevel: 0,
      arousalTier: 'Neutral',
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
    root.render(createElement(ChatToolsChaos, { t, toggle: () => {} }));
  });
}

function spinButton(): HTMLButtonElement | undefined {
  return Array.from(container.querySelectorAll('button')).find((b) =>
    /SPIN NOW|EVENT PENDING/.test(b.textContent ?? ''),
  );
}

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT =
    true;
  post.mockClear();
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

describe('ChatToolsChaos SPIN NOW', () => {
  it('posts the spin when tapped', () => {
    render(state({ enabled: true, pressure: 40 }));
    const button = spinButton();
    expect(button?.textContent).toBe('SPIN NOW');
    act(() => button!.click());
    expect(post).toHaveBeenCalledWith('/api/chat/chance-time/spin');
  });

  it('holds while an event is pending', () => {
    render(state({ enabled: true, hasPendingEvent: true }));
    const button = spinButton();
    expect(button?.textContent).toBe('EVENT PENDING');
    expect(button?.disabled).toBe(true);
    act(() => button!.click());
    expect(post).not.toHaveBeenCalled();
  });

  it('is not offered with Chaos off', () => {
    render(state({ enabled: false }));
    expect(spinButton()).toBeUndefined();
  });
});
