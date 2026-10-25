// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The chat tools list has no Needs switch (2026-10-25): Needs is set on the
// card, so the per-chat switch and the clock-off line that sat under it are
// gone, whatever the clock. One-Shot Eval moved out of this list to sit above
// the tool-calling pill (OneShotEvalControl.test.tsx). Desktop twin: the
// Character State case in test/ui/settings/after_dark_group_test.dart.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import type { ToolsState } from './ChatToolsShared';

const LINE = 'With Passage of time off, hunger, bathroom and energy wear a little each reply; the rest move only when the story says so.';

let passageEnabled = true;

function toolsState(): ToolsState {
  return {
    realismEnabled: true,
    needsEnabled: true,
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
    chaos: { enabled: false, nsfwEnabled: false, pressure: 0, hasPendingEvent: false },
    nsfw: { cooldownEnabled: false, cooldownTurnsRemaining: 0, arousalLevel: 0, arousalTier: '' },
    time: {
      weekday: 'Tuesday',
      dayCount: 3,
      timeOfDay: 'evening',
      passageEnabled,
      clockRunning: passageEnabled,
    },
    objectives: { primary: null, secondary: [], isChecking: false },
  };
}

// The tools snapshot answers; the panels' own loads never settle.
vi.mock('../api/client', () => ({
  ApiError: class ApiError extends Error {},
  api: {
    get: (url: string) =>
      /^\/api\/chat\/tools(\?|$)/.test(url) ? Promise.resolve(toolsState()) : new Promise(() => {}),
    post: () => new Promise(() => {}),
  },
}));

const { ChatTools } = await import('./ChatTools');

let container: HTMLDivElement;
let root: Root;

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

async function renderTools() {
  await act(async () => {
    root.render(createElement(ChatTools, { reloadKey: 0 }));
    await new Promise((r) => setTimeout(r, 0));
  });
}

describe('ChatTools without a Needs switch', () => {
  for (const clockOn of [false, true]) {
    it(`has no Needs switch or clock-off line (clock ${clockOn ? 'on' : 'off'})`, async () => {
      passageEnabled = clockOn;
      await renderTools();
      expect(container.querySelector('.chat-tools')).not.toBeNull();
      expect(container.textContent).not.toContain('Needs simulation');
      expect(container.querySelector('.needs-clock-off')).toBeNull();
      expect(container.textContent).not.toContain(LINE);
    });
  }

  it('no longer carries One-Shot Eval', async () => {
    await renderTools();
    expect(container.querySelector('.chat-tools')).not.toBeNull();
    expect(container.textContent).not.toContain('One-Shot Eval');
    expect(container.textContent).not.toContain('Realism performance');
  });
});
