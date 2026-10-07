// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The chat sidebar's Needs switch carries the clock-off line while Porch
// Life's Passage of Time is off (docs/design/needs-on-the-clock.md, "Clock
// off"), and only then. Desktop twin: the chat gear case in
// test/ui/widgets/needs_clock_off_note_test.dart.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import type { ToolsState } from './ChatToolsShared';

const LINE = 'With Passage of time off, needs change only when the story says so.';

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

function needsToggle(): HTMLElement {
  const toggle = [...container.querySelectorAll<HTMLElement>('label.tool-toggle')].find(
    (l) => l.querySelector('span')?.textContent === 'Needs simulation',
  );
  if (!toggle) throw new Error('Needs simulation toggle not rendered');
  return toggle;
}

describe('ChatTools Needs switch', () => {
  it('shows the clock-off line right under it while Passage of Time is off', async () => {
    passageEnabled = false;
    await renderTools();
    const note = needsToggle().nextElementSibling;
    expect(note?.classList.contains('needs-clock-off')).toBe(true);
    expect(note?.textContent).toBe(LINE);
  });

  it('shows nothing extra while the clock runs', async () => {
    passageEnabled = true;
    await renderTools();
    expect(needsToggle()).toBeTruthy();
    expect(container.querySelector('.needs-clock-off')).toBeNull();
    expect(container.textContent).not.toContain(LINE);
  });
});
