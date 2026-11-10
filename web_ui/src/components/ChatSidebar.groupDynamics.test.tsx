// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// PR 2 (docs/design/one-chat-ux.md): Group Dynamics, the read-only card under
// Character State. It lists the focused member's feelings toward each other
// member, follows the cast pill (the tools snapshot is focus-scoped), and
// mounts only in a group.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

type Dynamics = {
  member: string;
  tracked: boolean;
  feelings: Array<{ id: string; name: string; score: number; tier: string; percent: number }>;
} | null;

let byParticipant: Record<string, Dynamics> = {};
let inGroup = true;

function toolsState(participant: string | null) {
  return {
    realismEnabled: true,
    needsEnabled: false,
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
    ...(inGroup
      ? {
          group: { name: 'Shop Night', turnOrder: 'roundRobin', members: [] },
          groupDynamics: participant ? byParticipant[participant] ?? null : null,
        }
      : {}),
  };
}

vi.mock('../api/client', () => ({
  ApiError: class ApiError extends Error {},
  api: {
    get: (url: string) => {
      if (url === '/api/settings') return Promise.resolve({ backend: 'openai', model: 'm' });
      const m = /^\/api\/chat\/tools(?:\?participant=([^&]*))?$/.exec(url);
      return m ? Promise.resolve(toolsState(m[1] ? decodeURIComponent(m[1]) : null)) : new Promise(() => {});
    },
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

const realism = {
  realismEnabled: true,
  bond: { tier: 'Warming', score: 340, percent: 56 },
  longTerm: { tier: 'Steady', score: 210, percent: 42 },
  trust: { tier: 'Trusting', level: 280, percent: 46 },
  emotion: 'warm',
  emotionIntensity: 'mid',
  emotionHeld: 0,
  needsEnabled: false,
  needs: {},
};

async function render(focusedId: string | null) {
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
        focusedId,
        groupId: inGroup ? 'g1' : null,
        onCommand: vi.fn(),
        focusedName: focusedId ?? undefined,
        portraitName: 'Mara Quill',
        onChatSettings: vi.fn(),
      }),
    );
    await Promise.resolve();
    await Promise.resolve();
  });
}

const card = () => container.querySelector('.group-dynamics');
const rows = () =>
  [...(card()?.querySelectorAll('.stat') ?? [])].map((el) => el.textContent ?? '');

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  localStorage.clear();
  inGroup = true;
  byParticipant = {
    ana: {
      member: 'Ana',
      tracked: true,
      feelings: [{ id: 'bea', name: 'Bea', score: 150, tier: 'Fond', percent: 0.4 }],
    },
    bea: {
      member: 'Bea',
      tracked: true,
      feelings: [{ id: 'ana', name: 'Ana', score: -90, tier: 'Wary', percent: 0.3 }],
    },
  };
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
});
afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

describe('Group Dynamics card', () => {
  it('lists the focused member\'s feelings toward the others, read-only', async () => {
    await render('ana');
    expect(card()).not.toBeNull();
    expect(card()!.textContent).toContain('Group Dynamics');
    expect(rows()).toHaveLength(1);
    expect(rows()[0]).toContain('Bea');
    expect(rows()[0]).toContain('150');
    expect(card()!.querySelector('input, button, textarea')).toBeNull();
  });

  it('follows the cast pill: another member shows their own feelings', async () => {
    await render('ana');
    await render('bea');
    expect(rows()).toHaveLength(1);
    expect(rows()[0]).toContain('Ana');
    expect(rows()[0]).toContain('-90');
    expect(rows()[0]).not.toContain('Bea');
  });

  it('sits directly under Character State', async () => {
    await render('ana');
    const state = container.querySelector('.state-card');
    expect(state?.nextElementSibling?.classList.contains('group-dynamics')).toBe(true);
  });

  it('a group over four says it is not tracked', async () => {
    byParticipant.ana = { member: 'Ana', tracked: false, feelings: [] };
    await render('ana');
    expect(card()!.textContent).toContain('groups of two to four');
    expect(rows()).toHaveLength(0);
  });

  it('is absent when the host sends none (Realism off, a guest) and in a 1:1', async () => {
    byParticipant.ana = null;
    await render('ana');
    expect(card()).toBeNull();
    inGroup = false;
    await render(null);
    expect(card()).toBeNull();
  });
});
