// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Main Settings > Avatar Gallery, as on the desktop: in a 1:1 it opens the
// character's gallery; in a group it opens the gallery of the library
// character behind the tapped member (looked up through the relay).

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

let isGroupChat = false;
let needsOn = false;

function toolsState() {
  return {
    realismEnabled: true,
    needsEnabled: needsOn,
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

const asked: string[] = [];
vi.mock('../api/client', () => ({
  ApiError: class ApiError extends Error {},
  api: {
    get: (url: string) => {
      asked.push(url);
      return url === '/api/settings'
        ? Promise.resolve({ backend: 'openai', model: 'test-model' })
        : /^\/api\/chat\/tools(\?|$)/.test(url)
          ? Promise.resolve(toolsState())
          : url === '/api/groups/g1/members/m1/library'
            ? Promise.resolve({ id: 'lib-mara', name: 'Mara Quill' })
            : new Promise(() => {});
    },
    post: () => new Promise(() => {}),
  },
}));
vi.mock('../components/AvatarManager', () => ({
  AvatarManager: ({ characterId }: { characterId: string }) =>
    createElement('div', { 'data-testid': 'gallery-for' }, characterId),
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
        authorNote: '',
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
        castBar: isGroup ? createElement('div') : undefined,
        focusedName: 'Mara',
        portraitName: 'Mara Quill',
        onChatSettings: vi.fn(),
      }),
    );
    await Promise.resolve();
  });
}

const openGallery = async () => {
  act(() => {
    container.querySelector<HTMLButtonElement>('.sidebar-main-settings')?.click();
  });
  const item = [...document.querySelectorAll('[role="menuitem"]')].find((b) =>
    (b.textContent ?? '').includes('Avatar Gallery'),
  ) as HTMLElement | undefined;
  expect(item).toBeDefined();
  await act(async () => {
    item!.click();
    await Promise.resolve();
  });
};

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  asked.length = 0;
  localStorage.clear();
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
});
afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

describe('Main Settings > Avatar Gallery', () => {
  it('a 1:1 opens the character gallery', async () => {
    await render(false);
    await openGallery();
    expect(document.querySelector('[data-testid="gallery-for"]')?.textContent).toBe('mara');
    expect(asked.some((u) => u.includes('/library'))).toBe(false);
  });

  it('a group opens the gallery of the library character behind the tapped member', async () => {
    await render(true);
    await openGallery();
    expect(document.querySelector('[data-testid="gallery-for"]')?.textContent).toBe('lib-mara');
    expect(document.querySelector('[data-testid="avatar-gallery"]')?.textContent).toContain(
      'Avatar Gallery — Mara Quill',
    );
  });
});
