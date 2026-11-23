// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Boons & Bogies line in the web Character State sidebar: boons then
// bogies, each under the header the desktop line prints, with the bogey cap
// trailing on its own header (ruling 18, One UI).

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import type { GrowthRing } from './GrowthPanel';

type Bb = {
  enabled?: boolean;
  allowed?: boolean;
  rings?: GrowthRing[];
  cap?: number;
};

let bb: Bb = {};

function ring(
  id: string,
  content: string,
  kind: 'boon' | 'bogey',
  extra: Partial<GrowthRing> = {},
): GrowthRing {
  return {
    id,
    content,
    category: kind === 'bogey' ? 'bogey' : 'skill',
    tier: 'developing',
    strength: 0.6,
    pinned: kind === 'bogey',
    retired: false,
    receipts: [],
    kind,
    bbTier: 'skilled',
    seeded: true,
    ...extra,
  };
}

function toolsState() {
  return {
    realismEnabled: true,
    needsEnabled: false,
    realismOneShotEval: false,
    boonsBogiesEnabled: bb.enabled ?? true,
    boonsBogiesAllowed: bb.allowed ?? true,
    boonsBogiesRings: bb.rings ?? [],
    boonsBogiesBogeyCap: bb.cap ?? 3,
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
  };
}

vi.mock('../api/client', () => ({
  ApiError: class ApiError extends Error {},
  api: {
    get: (url: string) => {
      if (url === '/api/settings') return Promise.resolve({ backend: 'openai', model: 'm' });
      return /^\/api\/chat\/tools(?:\?.*)?$/.test(url)
        ? Promise.resolve(toolsState())
        : new Promise(() => {});
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

async function render() {
  await act(async () => {
    root.render(
      createElement(ChatSidebar, {
        realism: realism as never,
        authorNote: '',
        authorNoteDepth: 4,
        onSaveAuthorNote: vi.fn(),
        characterId: 'mira',
        isGroup: false,
        focusedIsHost: true,
        focusedPlaceholderPortrait: true,
        toolsKey: 1,
        focusedId: null,
        groupId: null,
        onCommand: vi.fn(),
        focusedName: 'Mira Vale',
        portraitName: 'Mira Vale',
        onChatSettings: vi.fn(),
      }),
    );
    await Promise.resolve();
    await Promise.resolve();
  });
}

const heads = () =>
  [...container.querySelectorAll('.bb-group-head')].map((el) => ({
    label: el.querySelector('span')?.textContent ?? '',
    trailing: el.querySelector('em')?.textContent ?? '',
  }));
const rowText = () =>
  [...container.querySelectorAll('.bb-group .growth-ring-text')].map(
    (el) => el.textContent ?? '',
  );

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  localStorage.clear();
  bb = {};
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
});
afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

describe('Boons & Bogies line', () => {
  it('groups boons then bogies under the desktop line\'s headers', async () => {
    bb = {
      rings: [
        ring('b1', 'reads a room in one breath', 'boon'),
        ring('b2', 'steady hands under pressure', 'boon'),
        ring('g1', 'bad temper when cornered', 'bogey'),
      ],
    };
    await render();
    expect(heads()).toEqual([
      { label: 'Boons', trailing: '' },
      { label: 'Bogies', trailing: '1 of 3' },
    ]);
    expect(rowText()).toEqual([
      'reads a room in one breath',
      'steady hands under pressure',
      'bad temper when cornered',
    ]);
  });

  it('drops a header with no rings under it, and carries the live cap', async () => {
    bb = { rings: [ring('g1', 'skips sleep to finish the job', 'bogey')], cap: 4 };
    await render();
    expect(heads()).toEqual([{ label: 'Bogies', trailing: '1 of 4' }]);
    expect(rowText()).toEqual(['skips sleep to finish the job']);
  });

  it('says the kit seeds at open when the chat has no rings', async () => {
    await render();
    expect(heads()).toEqual([]);
    expect(container.textContent).toContain('a card kit seeds when a chat opens');
  });

  it('hides the line when Porch Life has the feature off', async () => {
    bb = { allowed: false, rings: [ring('b1', 'reads a room', 'boon')] };
    await render();
    expect(heads()).toEqual([]);
    expect(container.textContent).toContain('Off in Porch Life');
  });
});
