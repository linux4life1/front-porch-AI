// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The wide sidebar's contract (PR 1a): portrait first, the Main Settings
// button opens Chat Settings / Model Settings (Edit Character only when an
// editor is wired, Group Settings… only for a group), the layout pills keep
// their names, and no-portrait characters get the window's initial square.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

let isGroupChat = false;

function toolsState() {
  return {
    realismEnabled: true,
    needsEnabled: false,
    realismOneShotEval: false,
    memory: {
      ragEnabled: true,
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
    ...(isGroupChat
      ? { group: { name: 'Shop Night', turnOrder: 'roundRobin', members: [] } }
      : {}),
  };
}

vi.mock('../api/client', () => ({
  ApiError: class ApiError extends Error {},
  api: {
    get: (url: string) =>
      url === '/api/settings'
        ? Promise.resolve({ backend: 'openai', model: 'test-model' })
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

async function render(isGroup: boolean) {
  isGroupChat = isGroup;
  await act(async () => {
    root.render(
      createElement(ChatSidebar, {
        realism: realism as never,
        authorNote: 'more evening light',
        authorNoteDepth: 4,
        onSaveAuthorNote: vi.fn(),
        characterId: 'mara',
        isGroup,
        focusedIsHost: !isGroup,
        focusedPlaceholderPortrait: true,
        toolsKey: 1,
        focusedId: isGroup ? 'm1' : null,
        groupId: isGroup ? 'g1' : null,
        onCommand: vi.fn(),
        castBar: isGroup ? createElement('div', { className: 'cast-stand-in' }) : undefined,
        focusedName: isGroup ? 'Mara' : undefined,
        portraitName: 'Mara Quill',
        onChatSettings: vi.fn(),
      }),
    );
    await Promise.resolve();
  });
}

const sectionIds = () =>
  [...container.querySelectorAll('.insight-section[data-id]')].map((el) =>
    el.getAttribute('data-id'),
  );
const menuLabels = () =>
  [...document.querySelectorAll('[role="menuitem"]')].map((b) => b.textContent ?? '');

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  localStorage.clear();
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
});
afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

describe('wide sidebar cards', () => {
  it('portraits first; pills keep their names; no-portrait gets the initial square', async () => {
    await render(false);
    expect(sectionIds()[0]).toBe('portrait');
    expect(container.textContent).toContain('Reset to default');
    expect(container.textContent).toMatch(/Lock layout|Layout locked/);
    // The expression picture is attempted; when it fails, the window's
    // initial square shows (a placeholder card picture never shows flat).
    const img = container.querySelector('.portrait-wrap img.portrait') as HTMLImageElement | null;
    if (img) act(() => img.dispatchEvent(new Event('error')));
    expect(container.querySelector('.portrait-initial')?.textContent).toBe('M');
  });

  it('Main Settings opens Chat Settings and Model Settings (no editor, no group)', async () => {
    await render(false);
    act(() => {
      container.querySelector<HTMLButtonElement>('.sidebar-main-settings')?.click();
    });
    expect(menuLabels().some((l) => l.includes('Chat Settings'))).toBe(true);
    expect(menuLabels().some((l) => l.includes('Model Settings'))).toBe(true);
    expect(menuLabels().some((l) => l.includes('Edit Character'))).toBe(false);
    expect(menuLabels().some((l) => l.includes('Group Settings'))).toBe(false);
  });

  it('a group gets the cast pills and Group Settings…', async () => {
    await render(true);
    expect(container.querySelector('.cast-stand-in')).not.toBeNull();
    expect(sectionIds()).toContain('cast');
    act(() => {
      container.querySelector<HTMLButtonElement>('.sidebar-main-settings')?.click();
    });
    expect(menuLabels().some((l) => l.includes('Group Settings…'))).toBe(true);
  });
});
