// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The web sidebar layout lock: toggled on, every grip is inert and a pointer
// drag moves nothing; Reset to default still POSTs while locked (and the lock
// stays on); toggled off, the grips come back. Desktop twin:
// test/ui/chat_components/sidebar_lock_test.dart.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import type { Realism } from './chatTypes';

const { post, saved } = vi.hoisted(() => ({
  post: vi.fn(() => Promise.resolve({})),
  saved: { order: [] as string[], locked: false },
}));

// Exact-URL answers (Error Book: a prefix mock once answered a sibling
// request); the panels' other loads never settle.
vi.mock('../api/client', () => ({
  ApiError: class ApiError extends Error {},
  api: {
    get: (url: string) =>
      url === '/api/settings'
        ? Promise.resolve({
            webSidebarOrder: saved.order,
            sidebarLayoutLocked: saved.locked,
          })
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
  saved.locked = false;
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

const buttonWithText = (text: string) =>
  Array.from(container.querySelectorAll<HTMLButtonElement>('button')).find(
    (b) => b.textContent === text,
  )!;

function pointer(el: Element, type: string, clientY: number) {
  act(() => {
    el.dispatchEvent(new MouseEvent(type, { bubbles: true, cancelable: true, clientY, button: 0 }));
  });
}

describe('ChatInsight layout lock', () => {
  it('locks the grips, keeps Reset working while locked, and unlocks again', async () => {
    await renderInsight();
    const sectionCount = sections().length;
    expect(container.querySelectorAll('.sidebar-grip.locked')).toHaveLength(0);

    // Lock: the pill posts the switch and every grip turns inert.
    const lockPill = buttonWithText('Lock layout');
    expect(lockPill).toBeTruthy();
    await act(async () => {
      lockPill.click();
    });
    expect(post).toHaveBeenCalledWith('/api/settings', { sidebarLayoutLocked: true });
    expect(container.querySelectorAll('.sidebar-grip.locked')).toHaveLength(sectionCount);
    expect(container.querySelectorAll('button.sidebar-grip')).toHaveLength(0);
    expect(buttonWithText('Layout locked').getAttribute('aria-pressed')).toBe('true');

    // A pointer drag on a locked grip moves nothing.
    const list = container.querySelector('.realism-panel')!;
    const lockedGrip = container.querySelector<HTMLElement>(
      '.insight-section[data-id="lorebook"] .sidebar-grip',
    )!;
    pointer(lockedGrip, 'pointerdown', 445);
    pointer(list, 'pointermove', 20);
    pointer(list, 'pointerup', 20);
    expect(sections()[0]).toBe('one_shot_eval');
    expect(post).not.toHaveBeenCalledWith('/api/settings', expect.objectContaining({
      webSidebarOrder: expect.anything(),
    }));

    // Reset to default still POSTs while locked, and the lock stays on.
    vi.spyOn(window, 'confirm').mockReturnValue(true);
    await act(async () => {
      buttonWithText('Reset to default').click();
    });
    expect(post).toHaveBeenCalledWith('/api/settings', { resetSidebarLayout: true });
    expect(buttonWithText('Layout locked')).toBeTruthy();
    expect(container.querySelectorAll('.sidebar-grip.locked')).toHaveLength(sectionCount);

    // Unlock: the grips come back.
    await act(async () => {
      buttonWithText('Layout locked').click();
    });
    expect(post).toHaveBeenCalledWith('/api/settings', { sidebarLayoutLocked: false });
    expect(container.querySelectorAll('.sidebar-grip.locked')).toHaveLength(0);
    expect(container.querySelectorAll('button.sidebar-grip')).toHaveLength(sectionCount);
  });
});
