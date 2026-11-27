// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Heat on the phone (docs/design/heat-meter.md): a bar directly under Lust
// whenever Lust shows, at 0 too ("Heat: Cool"), as the desktop's HeatRow in
// bond_bars.dart; hidden when an older desktop sends no Heat. The Lust bar
// takes the desktop's three hues. Red proofs: drop the Heat StatBar, gate it
// on heatLevel > 0, or move it below the recovery line, and a case fails.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import type { Realism } from './chatTypes';
import type { ToolsState } from './ChatToolsShared';

let nsfw: Record<string, unknown> = {};

function toolsState() {
  return {
    realismEnabled: true,
    realismSwitch: true,
    memberId: null,
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
    nsfw: {
      cooldownEnabled: true,
      afterglowAllowed: true,
      afterglowSwitch: true,
      arousalLevel: 82,
      arousalTier: 'Overwhelming',
      refractoryMinutesRemaining: 0,
      refractoryClockRunning: true,
      refractoryLabel: '',
      ...nsfw,
    },
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
    get: (url: string) =>
      url === '/api/settings'
        ? Promise.resolve({ backend: 'openai', model: 'm' })
        : /^\/api\/chat\/tools(\?|$)/.test(url)
          ? Promise.resolve(toolsState())
          : new Promise(() => {}),
    post: () => Promise.resolve(toolsState()),
  },
}));
vi.mock('../api/ws', () => ({
  ChatSocket: class {
    connect() {}
    close() {}
  },
}));

const { ChatSidebar } = await import('./ChatSidebar');
const { ChatInsight } = await import('./ChatInsight');
const { ChatToolsNsfw } = await import('./ChatToolsRealism');

let container: HTMLDivElement;
let root: Root;

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  nsfw = {};
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

const sidebarRealism = {
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

async function renderSidebar() {
  await act(async () => {
    root.render(
      createElement(ChatSidebar, {
        realism: sidebarRealism as never,
        authorNote: '',
        authorNoteDepth: 4,
        onSaveAuthorNote: vi.fn(),
        characterId: 'mara',
        isGroup: false,
        focusedIsHost: true,
        focusedPlaceholderPortrait: true,
        toolsKey: 1,
        focusedId: null,
        groupId: null,
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

const statLabels = () =>
  [...container.querySelectorAll('.stat .stat-head > span:first-child')].map(
    (s) => s.textContent ?? '',
  );

describe('Heat on the phone', () => {
  it('sits directly under Lust, shown at 0 as Cool', async () => {
    nsfw = { heatLevel: 0, heatTier: 'Cool' };
    await renderSidebar();
    const labels = statLabels();
    const lust = labels.indexOf('Lust: Overwhelming');
    expect(lust).toBeGreaterThan(-1);
    expect(labels[lust + 1]).toBe('Heat: Cool');
    const heat = container.querySelector('.heat-bar');
    expect(heat?.textContent).toContain('0/100');
  });

  it('fills to its level', async () => {
    nsfw = { heatLevel: 72, heatTier: 'Close' };
    await renderSidebar();
    const fill = container.querySelector<HTMLElement>('.heat-bar .stat-fill');
    expect(fill?.style.width).toBe('72%');
    expect(statLabels()).toContain('Heat: Close');
  });

  it('is hidden when an older desktop sends no Heat', async () => {
    await renderSidebar();
    expect(container.querySelector('.heat-bar')).toBeNull();
    expect(statLabels()).toContain('Lust: Overwhelming');
  });

  it('Lust takes the desktop hues: deep rose from 60', async () => {
    nsfw = { heatLevel: 0, heatTier: 'Cool' };
    await renderSidebar();
    const fill = container.querySelector<HTMLElement>('.lust-bar .stat-fill');
    expect(fill?.style.background).toBe('var(--lust-deep)');
  });

  it('the Stats panel and chat tools list Heat after Lust', () => {
    const realism: Realism = {
      realismEnabled: true,
      bond: { score: 12, tier: 'Friendly', percent: 0.52 },
      longTerm: { score: 4, tier: 'Warm', percent: 0.51 },
      trust: { level: 8, tier: 'Some', percent: 0.54 },
      emotion: 'calm',
      emotionIntensity: 'mild',
      mood: 'calm',
      arousal: { level: 70, tier: 'Overcome' },
      heat: { level: 42, tier: 'Climbing' },
      lustOn: true,
      fixation: '',
    };
    act(() => {
      root.render(
        createElement(ChatInsight, {
          realism,
          authorNote: '',
          authorNoteDepth: 4,
          onSaveAuthorNote: () => {},
          characterId: 'c1',
          isGroup: false,
          focusedIsHost: true,
          toolsKey: 0,
          focusedId: null,
          groupId: null,
          onCommand: () => {},
        }),
      );
    });
    const lines = () =>
      [...container.querySelectorAll('.stat-line')].map((l) => l.textContent ?? '');
    const insight = lines();
    const at = insight.findIndex((l) => l.startsWith('Lust'));
    expect(insight[at + 1]).toBe('HeatClimbing · 42');

    const t = {
      realismEnabled: true,
      nsfw: {
        cooldownEnabled: true,
        refractoryMinutesRemaining: 0,
        refractoryClockRunning: true,
        refractoryLabel: '',
        arousalLevel: 70,
        arousalTier: 'Overcome',
        heatLevel: 42,
        heatTier: 'Climbing',
      },
    } as ToolsState;
    act(() => {
      root.render(createElement(ChatToolsNsfw, { t, toggle: () => {} }));
    });
    const tools = lines();
    const lustAt = tools.findIndex((l) => l.startsWith('Lust'));
    expect(tools[lustAt + 1]).toBe('HeatClimbing · 42');
  });
});
