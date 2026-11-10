// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The web insight column is reorderable: a pointer drag on a grip trades
// sections live as the pointer crosses a neighbour's midpoint (the
// InterviewCard rule) and POSTs the new order; the Reset pill asks first
// (global order) and only then POSTs the reset. Desktop twin:
// test/ui/chat_components/sidebar_reorder_test.dart.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import type { Realism } from './chatTypes';

const { post, saved } = vi.hoisted(() => ({
  post: vi.fn(() => Promise.resolve({})),
  saved: { order: [] as string[] },
}));

// Exact-URL answers (Error Book: a prefix mock once answered a sibling
// request); the panels' other loads never settle.
vi.mock('../api/client', () => ({
  ApiError: class ApiError extends Error {},
  api: {
    get: (url: string) =>
      url === '/api/settings'
        ? Promise.resolve({ webSidebarOrder: saved.order })
        : url === '/api/chat/tools'
          ? Promise.resolve({ realismOneShotMode: 'off', realismOneShotEval: false })
          : new Promise(() => {}),
    post,
  },
}));
vi.mock('./ChatTools', () => ({ ChatTools: () => null }));
vi.mock('../api/ws', () => ({
  ChatSocket: class {
    connect() {}
    close() {}
  },
}));

const { ChatInsight } = await import('./ChatInsight');

const realism = {
  realismEnabled: true,
  bond: { score: 12, tier: 'Friendly', percent: 0.52 },
  longTerm: { score: 4, tier: 'Warm', percent: 0.51 },
  trust: { level: 8, tier: 'Some', percent: 0.54 },
  arousal: { level: 0, tier: 'Calm' },
  emotion: 'calm',
  emotionIntensity: 'mild',
  mood: 'calm',
  needs: {},
} as unknown as Realism;

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

async function renderInsight() {
  await act(async () => {
    root.render(
      createElement(ChatInsight, {
        realism,
        authorNote: '',
        authorNoteDepth: 4,
        onSaveAuthorNote: () => {},
        characterId: 'c1',
        isGroup: false,
        focusedIsHost: false,
        toolsKey: 0,
        focusedId: null,
        groupId: null,
        onCommand: () => {},
        toolSupport: { state: 'supported', testing: false },
      }),
    );
    await new Promise((r) => setTimeout(r, 0));
  });
}

const sections = () =>
  Array.from(container.querySelectorAll<HTMLElement>('.insight-section')).map(
    (el) => el.dataset.id!,
  );

function pointer(el: Element, type: string, clientY: number) {
  act(() => {
    el.dispatchEvent(new MouseEvent(type, { bubbles: true, cancelable: true, clientY, button: 0 }));
  });
}

/** A touch pointer: no preventDefault on the way down, so an early move is a
 *  scroll; the hold timer is what starts a drag. */
function touch(el: Element, type: string, clientY: number) {
  const ev = new MouseEvent(type, {
    bubbles: true,
    cancelable: true,
    clientY,
    clientX: 10,
    button: 0,
  });
  Object.defineProperty(ev, 'pointerType', { value: 'touch' });
  Object.defineProperty(ev, 'pointerId', { value: 7 });
  act(() => {
    el.dispatchEvent(ev);
  });
}

const grip = (id: string) =>
  container.querySelector<HTMLElement>(`.insight-section[data-id="${id}"] .sidebar-grip`)!;

describe('ChatInsight reorder', () => {
  it('a grip drag trades sections live and POSTs the new order', async () => {
    // P40: the numbers this test derives from the product's midpoint rule.
    // 1:1 insight shows 8 sections; each is 50 tall at 60 apart, so section
    // i has top i*60 and middle i*60 + 25. Lorebook (index 7) starts at
    // middle 445; the pointer moves to y=20, below section 0's middle (25)
    // and above nothing else's — so the rule walks it straight to index 0.
    vi.spyOn(HTMLElement.prototype, 'getBoundingClientRect').mockImplementation(function (
      this: HTMLElement,
    ) {
      const i = Array.from(this.parentElement?.children ?? []).indexOf(this);
      return {
        top: i * 60, height: 50, bottom: i * 60 + 50,
        left: 0, right: 0, width: 0, x: 0, y: i * 60, toJSON() {},
      };
    });
    await renderInsight();
    expect(sections()[0]).toBe('one_shot_eval');

    const list = container.querySelector('.realism-panel')!;
    pointer(grip('lorebook'), 'pointerdown', 445);
    pointer(list, 'pointermove', 20);
    // Live: traded before the pointer lifts.
    expect(sections()[0]).toBe('lorebook');
    pointer(list, 'pointerup', 20);

    expect(post).toHaveBeenCalledWith('/api/settings', {
      webSidebarOrder: [
        'lorebook',
        'one_shot_eval',
        'tool_calling_pill',
        'portrait',
        'author_note',
        'realism_stats',
        'chat_tools',
        'places',
      ],
    });
  });

  it('paints the remembered order and appends ids it does not know per the default', async () => {
    // The host's stored list puts places first and still hides the cast
    // chips id from a group chat; wiki is new to it and appends per default
    // (the default puts it after author_note).
    saved.order = ['places', 'one_shot_eval', 'portrait', 'cast_chips', 'places_extra'];
    await renderInsight();
    expect(sections()).toEqual([
      'places',
      'one_shot_eval',
      'portrait',
      'tool_calling_pill',
      'author_note',
      'realism_stats',
      'chat_tools',
      'lorebook',
    ]);
  });

  it('the Reset pill asks first; Yes POSTs the reset, No POSTs nothing', async () => {
    await renderInsight();
    const pill = Array.from(container.querySelectorAll('button')).find(
      (b) => b.textContent === 'Reset to default',
    )!;
    expect(pill).toBeTruthy();

    const confirmSpy = vi.spyOn(window, 'confirm').mockReturnValue(false);
    await act(async () => {
      pill.click();
    });
    expect(confirmSpy).toHaveBeenCalled();
    expect(post).not.toHaveBeenCalled();

    confirmSpy.mockReturnValue(true);
    await act(async () => {
      pill.click();
    });
    expect(post).toHaveBeenCalledWith('/api/settings', { resetSidebarLayout: true });
  });

  it('a touch drag waits for a still hold; an early move is a scroll', async () => {
    // Same midpoint table as the mouse test above.
    vi.spyOn(HTMLElement.prototype, 'getBoundingClientRect').mockImplementation(function (
      this: HTMLElement,
    ) {
      const i = Array.from(this.parentElement?.children ?? []).indexOf(this);
      return {
        top: i * 60, height: 50, bottom: i * 60 + 50,
        left: 0, right: 0, width: 0, x: 0, y: i * 60, toJSON() {},
      };
    });
    // Render before faking timers: the mount's own tick is real.
    await renderInsight();
    vi.useFakeTimers();
    try {
      const list = container.querySelector('.realism-panel')!;

      // A finger that moves before the hold never becomes a drag.
      touch(grip('lorebook'), 'pointerdown', 445);
      touch(list, 'pointermove', 20);
      act(() => {
        vi.advanceTimersByTime(500);
      });
      expect(sections()[0]).toBe('one_shot_eval');
      expect(container.querySelector('.insight-section.dragging')).toBeNull();

      // A finger held still for the hold starts the drag, and then trades.
      touch(grip('lorebook'), 'pointerdown', 445);
      act(() => {
        vi.advanceTimersByTime(450);
      });
      expect(
        container.querySelector('.insight-section.dragging')?.getAttribute('data-id'),
      ).toBe('lorebook');
      touch(list, 'pointermove', 20);
      expect(sections()[0]).toBe('lorebook');
      touch(list, 'pointerup', 20);
    } finally {
      vi.useRealTimers();
    }
  });
});
