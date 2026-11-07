// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The web Chat Tools column is reorderable: a pointer drag on a grip trades
// sections live as the pointer crosses a neighbour's midpoint (the
// InterviewCard rule) and POSTs the new order. ChatInsight's twin for the
// tools surface; desktop twin: sidebar_reorder_test.dart.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import type { ToolsState } from './ChatToolsShared';

const { post, saved } = vi.hoisted(() => ({
  post: vi.fn(() => Promise.resolve({})),
  saved: { order: [] as string[] },
}));

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

// Exact-URL answers (Error Book: a prefix mock once answered a sibling
// request); the panels' own loads never settle.
vi.mock('../api/client', () => ({
  ApiError: class ApiError extends Error {},
  api: {
    get: (url: string) =>
      url === '/api/settings'
        ? Promise.resolve({ webSidebarToolsOrder: saved.order })
        : /^\/api\/chat\/tools(\?|$)/.test(url)
          ? Promise.resolve(toolsState())
          : new Promise(() => {}),
    post,
  },
}));
vi.mock('../api/ws', () => ({
  ChatSocket: class {
    connect() {}
    close() {}
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
  post.mockReset();
  saved.order = [];
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
  vi.restoreAllMocks();
});

async function renderTools() {
  await act(async () => {
    root.render(createElement(ChatTools, { reloadKey: 0 }));
    await new Promise((r) => setTimeout(r, 0));
  });
}

const sections = () =>
  Array.from(container.querySelectorAll<HTMLElement>('.tools-section')).map(
    (el) => el.dataset.id!,
  );

function pointer(el: Element, type: string, clientY: number) {
  act(() => {
    el.dispatchEvent(new MouseEvent(type, { bubbles: true, cancelable: true, clientY, button: 0 }));
  });
}

const grip = (id: string) =>
  container.querySelector<HTMLElement>(`.tools-section[data-id="${id}"] .sidebar-grip`)!;

describe('ChatTools reorder', () => {
  it('a grip drag trades sections live and POSTs the new order', async () => {
    // P40: this state (no journal, no group) shows 14 sections; each is 50
    // tall at 60 apart, so section i has top i*60 and middle i*60 + 25.
    // nsfw is last (index 13, middle 805); the pointer moves to y=20, below
    // section 0's middle (25) — the rule walks it straight to index 0.
    vi.spyOn(HTMLElement.prototype, 'getBoundingClientRect').mockImplementation(function (
      this: HTMLElement,
    ) {
      const i = Array.from(this.parentElement?.children ?? []).indexOf(this);
      return {
        top: i * 60, height: 50, bottom: i * 60 + 50,
        left: 0, right: 0, width: 0, x: 0, y: i * 60, toJSON() {},
      };
    });
    await renderTools();
    expect(sections()).toHaveLength(14);
    expect(sections().at(-1)).toBe('nsfw');

    const list = container.querySelector('.chat-tools')!;
    pointer(grip('nsfw'), 'pointerdown', 805);
    pointer(list, 'pointermove', 20);
    // Live: traded before the pointer lifts.
    expect(sections()[0]).toBe('nsfw');
    pointer(list, 'pointerup', 20);

    expect(post).toHaveBeenCalledWith('/api/settings', {
      webSidebarToolsOrder: [
        'nsfw',
        'realism_toggle',
        'needs_toggle',
        'context_budget',
        'wiki',
        'memory',
        'ambitions',
        'pockets',
        'our_story',
        'promises',
        'belongings',
        'chaos',
        'objectives',
        'scene_time',
      ],
    });
  });

  it('paints the remembered order and keeps hidden ids out of the paint', async () => {
    saved.order = ['scene_time', 'group_settings', 'nsfw', 'wiki'];
    await renderTools();
    // group_settings is not visible here (no group id) and simply stays in
    // the host's stored list; the rest paint in the remembered sequence and
    // the unknown ones append per the default.
    expect(sections().slice(0, 3)).toEqual(['scene_time', 'nsfw', 'wiki']);
    expect(sections()).not.toContain('group_settings');
  });
});
