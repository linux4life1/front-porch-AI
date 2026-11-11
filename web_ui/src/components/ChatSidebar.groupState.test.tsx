// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// PR 2 (docs/design/one-chat-ux.md), the window's Character State rules in a
// group: Realism off says how to turn it on (and a member with no scores
// must not crash the card), a lite guest keeps its note, and the switches
// need a member id (PR 3: ChatSidebar.memberSwitches.test.tsx has them).

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

let inGroup = true;

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
      clockRunning: true,
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

describe('Character State in a group', () => {
  it('Realism off says where to turn it on, and shows no scores', async () => {
    await render(off);
    expect(body()).toContain('The Realism Engine is off for Mara in this chat');
    expect(body()).toContain('flip the switch');
    expect(body()).not.toContain('Short-Term Bond');
    expect(body()).not.toContain('Needs');
    // Pockets and time are not Realism's, so they stay.
    expect(container.querySelector('.state-time-line')).not.toBeNull();
  });

  it('a 1:1 with Realism off keeps the switch copy', async () => {
    inGroup = false;
    await render(off);
    expect(body()).toContain('flip the switch');
    expect(body()).not.toContain('Short-Term Bond');
  });

  it('the Needs line has no switch for a guest (no member id), and one in a 1:1', async () => {
    await render(on);
    expect(body()).toContain('Needs');
    expect(container.querySelector('input[aria-label="Needs"]')).toBeNull();
    // The bars still follow the member's needs.
    expect(body()).toContain('Hunger');

    inGroup = false;
    await render(on);
    expect(container.querySelector('input[aria-label="Needs"]')).not.toBeNull();
  });

  it('the Realism switch is not in the header without a member id, and is in a 1:1', async () => {
    await render(on);
    expect(container.querySelector('input[aria-label="Realism engine"]')).toBeNull();

    inGroup = false;
    await render(on);
    expect(container.querySelector('.state-card > summary input[aria-label="Realism engine"]')).not.toBeNull();
  });
});
