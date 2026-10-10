// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A character made without a portrait carries a flat coloured card picture.
// The chat state marks it (cast[].placeholderPortrait), and the phone's chat
// header and side portrait then skip that picture: with no mood picture they
// show nothing, as for a character with no picture at all, instead of a flat
// colour box. Pinned through the real ChatPage. Relay twin (the real chat
// state sets the flag): test/services/web/placeholder_portrait_relay_test.dart.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

vi.mock('../api/client', () => ({
  api: {
    get: (path: string) => {
      if (path === '/api/chat/state') return Promise.resolve(chatState);
      return new Promise(() => {});
    },
    post: () => Promise.resolve({}),
    upload: () => new Promise(() => {}),
  },
  ApiError: class ApiError extends Error {},
}));

vi.mock('../api/ws', () => ({
  ChatSocket: class {
    connect() {}
    close() {}
  },
}));

const auth = { setAuthenticated: () => {} };
vi.mock('../auth/AuthContext', () => ({ useAuth: () => auth }));

let chatState: Record<string, unknown> = {};

function stateFor(placeholderPortrait: boolean | undefined) {
  return {
    character: { name: 'Juniper', id: 'c1' },
    sessionId: 's1',
    messages: [],
    isGenerating: false,
    cast: [
      {
        id: 'c1',
        dbId: 'c1',
        name: 'Juniper',
        isHost: true,
        realismEnabled: true,
        hasAvatar: true,
        avatarUrl: '/api/characters/c1/avatar',
        ...(placeholderPortrait === undefined ? {} : { placeholderPortrait }),
      },
    ],
    realism: {
      realismEnabled: true,
      bond: { score: 0, tier: 'Acquaintance', percent: 0 },
      longTerm: { score: 0, tier: 'Acquaintance', percent: 0 },
      trust: { level: 0, tier: 'Wary', percent: 0 },
      emotion: 'neutral',
      emotionIntensity: 'mild',
      mood: 'neutral',
      arousal: { level: 0, tier: 'calm' },
      fixation: '',
      needsEnabled: false,
      needs: {},
    },
  };
}

const { ChatPage } = await import('./ChatPage');

let container: HTMLDivElement;
let root: Root;

async function render() {
  (window as { innerWidth: number }).innerWidth = 1280;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  act(() => {
    root.render(
      createElement(
        MemoryRouter,
        { initialEntries: ['/chat'] },
        createElement(
          Routes,
          null,
          createElement(Route, { path: '/chat', element: createElement(ChatPage) }),
        ),
      ),
    );
  });
  await act(async () => {
    await Promise.resolve();
  });
}

/** No mood picture for this character: the expression request fails. */
function failExpression(selector: string) {
  const img = container.querySelector(selector) as HTMLImageElement | null;
  expect(img?.getAttribute('src')).toContain('/api/chat/expression-avatar');
  act(() => {
    img!.dispatchEvent(new Event('error'));
  });
}

const headerImg = () => container.querySelector('.chat-header img.chat-header-avatar');
const sideImg = () => container.querySelector('.portrait-wrap img.portrait');

const realComplete = Object.getOwnPropertyDescriptor(HTMLImageElement.prototype, 'complete');

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  (Element.prototype as unknown as { scrollTo: () => void }).scrollTo = () => {};
  // jsdom never loads a picture; only the error event below decides.
  Object.defineProperty(HTMLImageElement.prototype, 'complete', {
    configurable: true,
    get: () => false,
  });
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
  if (realComplete) Object.defineProperty(HTMLImageElement.prototype, 'complete', realComplete);
});

describe('chat avatars for a character made without a portrait', () => {
  it('show nothing instead of the flat colour card picture', async () => {
    chatState = stateFor(true);
    await render();
    failExpression('.chat-header img.chat-header-avatar');
    expect(headerImg()).toBeNull();
    failExpression('.portrait-wrap img.portrait');
    expect(sideImg()).toBeNull();
  });

  it.each([false, undefined])('keep a real portrait (flag %s; undefined is an older app)', async (flag) => {
    chatState = stateFor(flag);
    await render();
    failExpression('.chat-header img.chat-header-avatar');
    expect(headerImg()?.getAttribute('src')).toBe('/api/characters/c1/avatar');
    failExpression('.portrait-wrap img.portrait');
    expect(sideImg()?.getAttribute('src')).toBe('/api/characters/c1/avatar');
  });
});
