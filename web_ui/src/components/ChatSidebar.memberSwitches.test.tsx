// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// PR 3 (docs/design/one-chat-ux.md): in a group the Realism header switch, the
// Needs line and the Afterglow line are the focused member's own and post to
// the member toggles with their id; a 1:1 posts the chat's toggles unchanged.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

let inGroup = true;
const posts: { url: string; body: Record<string, unknown> }[] = [];

function toolsState() {
  return {
    realismEnabled: true,
    realismSwitch: true,
    memberId: inGroup ? 'm1' : null,
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
    nsfw: {
      cooldownEnabled: true,
      afterglowAllowed: true,
      afterglowSwitch: true,
      cooldownTurnsRemaining: 0,
      arousalLevel: 10,
      arousalTier: 'Warm',
      refractoryMinutesRemaining: 0,
      refractoryLabel: '',
    },
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
    post: (url: string, body: Record<string, unknown>) => {
      posts.push({ url, body });
      return Promise.resolve(toolsState());
    },
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

async function render(realism: object) {
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

function flip(selector: string) {
  const el = container.querySelector<HTMLInputElement>(selector);
  expect(el).not.toBeNull();
  act(() => el!.click());
}
const last = () => posts[posts.length - 1];

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  localStorage.clear();
  posts.length = 0;
  inGroup = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
});
afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

describe('per-member switches in a group', () => {
  it('the header Realism switch posts memberRealism with the focused member', async () => {
    await render(on);
    flip('.state-card > summary input[aria-label="Realism engine"]');
    expect(last().url).toBe('/api/chat/tools/toggle?participant=m1');
    expect(last().body).toEqual({ name: 'memberRealism', value: false, id: 'm1' });
  });

  it('the Needs line posts memberNeeds', async () => {
    await render(on);
    flip('input[aria-label="Needs"]');
    expect(last().body).toEqual({ name: 'memberNeeds', value: false, id: 'm1' });
  });

  it('the Afterglow line posts memberAfterglow', async () => {
    await render(on);
    flip('input[aria-label="Afterglow"]');
    expect(last().body).toEqual({ name: 'memberAfterglow', value: false, id: 'm1' });
  });

  it('a 1:1 still posts the chat toggles', async () => {
    inGroup = false;
    await render(on);
    flip('.state-card > summary input[aria-label="Realism engine"]');
    expect(last().body).toEqual({ name: 'realism', value: false });
    flip('input[aria-label="Needs"]');
    expect(last().body).toEqual({ name: 'needs', value: false });
    flip('input[aria-label="Afterglow"]');
    expect(last().body).toEqual({ name: 'nsfwCooldown', value: false });
  });
});
