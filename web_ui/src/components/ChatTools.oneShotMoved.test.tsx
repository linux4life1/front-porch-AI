// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// One-Shot Eval moved out of the chat tools list to sit above the
// tool-calling pill (OneShotEvalControl.test.tsx).

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import type { ToolsState } from './ChatToolsShared';

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
      passageEnabled: true,
      clockRunning: true,
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

describe('ChatTools', () => {
  it('no longer carries One-Shot Eval', async () => {
    await renderTools();
    expect(container.querySelector('.chat-tools')).not.toBeNull();
    expect(container.textContent).not.toContain('One-Shot Eval');
    expect(container.textContent).not.toContain('Realism performance');
  });
});
