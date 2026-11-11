// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// One UI (CLAUDE.md): the time line follows the window's rule in 1:1 and
// group alike. It shows while Realism runs for the character or the story
// clock runs, and hides when both are off; a group is not an exception.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

let inGroup = true;
let clockRunning = true;

function toolsState() {
  return {
    realismEnabled: true,
    needsEnabled: true,
    realismOneShotEval: false,
    memory: {
      ragEnabled: false,
      ragRetrievalCount: 3,
      ragWindowSize: 5,
      journalEnabled: true,
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
      clockRunning,
    },
    objectives: { primary: null, secondary: [], isChecking: false },
    ...(inGroup ? { group: { name: 'Shop Night', turnOrder: 'roundRobin', members: [] } } : {}),
  };
}

vi.mock('../api/client', () => ({
  ApiError: class ApiError extends Error {},
  api: {
    get: (url: string) =>
      url === '/api/settings'
        ? Promise.resolve({ backend: 'openai', model: 'm' })
        : /^\/api\/chat\/tools(\?|$)/.test(url)
          ? Promise.resolve(toolsState())
          : new Promise(() => {}),
    post: () => new Promise(() => {}),
  },
}));
vi.mock('../api/ws', () => ({
  ChatSocket: class {
    connect() {}
    close() {}
  },
}));

const { ChatSidebar } = await import('./ChatSidebar');

let container: HTMLDivElement;
let root: Root;

const on = {
  realismEnabled: true,
  bond: { tier: 'Warming', score: 340, percent: 56 },
  longTerm: { tier: 'Steady', score: 210, percent: 42 },
  trust: { tier: 'Trusting', level: 280, percent: 46 },
  emotion: 'warm',
  emotionIntensity: 'mid',
  emotionHeld: 0,
  needsEnabled: true,
  needs: { hunger: 12 },
};
// What the host sends for a group member while the chat's Realism is off:
// no scores at all.
const off = { realismEnabled: false, realismAllowed: true };

async function render(realism: object, opts: { lite?: boolean } = {}) {
  await act(async () => {
    root.render(
      createElement(ChatSidebar, {
        realism: realism as never,
        authorNote: '',
        authorNoteDepth: 4,
        onSaveAuthorNote: vi.fn(),
        characterId: 'mara',
        isGroup: inGroup,
        focusedIsHost: !inGroup,
        focusedIsLiteGuest: opts.lite,
        focusedPlaceholderPortrait: true,
        toolsKey: 1,
        focusedId: inGroup ? 'm1' : null,
        groupId: inGroup ? 'g1' : null,
        onCommand: vi.fn(),
        focusedName: 'Mara',
        portraitName: 'Mara Quill',
        onChatSettings: vi.fn(),
      }),
    );
    await Promise.resolve();
    await Promise.resolve();
  });
}

const body = () => container.querySelector('.state-card > .tool-body')?.textContent ?? '';

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  localStorage.clear();
  inGroup = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
});
afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

const timeShown = () => container.querySelector('.state-time') !== null;

for (const mode of ['group', '1:1'] as const) {
  describe(`the time line in a ${mode}`, () => {
    beforeEach(() => {
      inGroup = mode === 'group';
      clockRunning = true;
    });

    it('hides when Realism is off and the clock is paused', async () => {
      clockRunning = false;
      await render(off);
      expect(timeShown()).toBe(false);
    });

    it('shows when Realism is off but the clock runs', async () => {
      await render(off);
      expect(timeShown()).toBe(true);
    });

    it('shows when Realism is on, even with the clock paused', async () => {
      clockRunning = false;
      await render(on);
      expect(timeShown()).toBe(true);
    });
  });
}
