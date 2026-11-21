// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Two chat-page dead ends, pinned at their call sites (not just at the pure
// helper, so deleting the wiring goes red too):
//
//  1. A revoked / expired web session. Nothing in the app mapped a 401 back to
//     the sign-in form, so `/api/chat/state` rejecting left the page on a
//     spinner that never resolved — and an installed PWA has no address bar to
//     force a reload with.
//  2. Switching conversations mid-generation. The old chat's live streaming
//     bubble stayed on screen under the NEW conversation and kept growing with
//     the old reply's tokens (the shared socket keeps delivering them; the
//     server's settle wait gives up after 15s).

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { MemoryRouter } from 'react-router-dom';
import { createElement, type ReactNode } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

class FakeApiError extends Error {
  status: number;
  payload: Record<string, unknown>;
  constructor(status: number, message: string) {
    super(message);
    this.status = status;
    this.payload = {};
  }
}

/** Set per test: what GET /api/chat/state does. */
let stateAnswer: () => Promise<unknown> = () => Promise.resolve(chatState);

vi.mock('../api/client', () => ({
  api: {
    get: (path: string) => {
      if (path === '/api/chat/state') return stateAnswer();
      if (path === '/api/chat/sessions') {
        return Promise.resolve({
          sessions: [
            { id: 's2', preview: 'Older chat', message_count: 4, user_message_count: 2, date: '' },
          ],
        });
      }
      return new Promise(() => {});
    },
    post: () => Promise.resolve({}),
    upload: () => new Promise(() => {}),
  },
  ApiError: FakeApiError,
}));

// The socket handlers ChatPage and the sidebar order hook register — tests
// drive `token` through all of them (the panels keep their own sockets now).
let eventHandlers: ((e: Record<string, unknown>) => void)[] = [];
vi.mock('../api/ws', () => ({
  ChatSocket: class {
    private handler: (e: Record<string, unknown>) => void;
    constructor(handler: (e: Record<string, unknown>) => void) {
      this.handler = handler;
      eventHandlers.push(handler);
    }
    connect() {}
    close() {
      eventHandlers = eventHandlers.filter((h) => h !== this.handler);
    }
  },
}));
const emit = (e: Record<string, unknown>) => {
  for (const h of [...eventHandlers]) h(e);
};

// Stable identity, like the real useState setter (a fresh function each render
// would re-run the socket effect forever).
const authCalls: boolean[] = [];
const auth = { setAuthenticated: (v: boolean) => authCalls.push(v) };
vi.mock('../auth/AuthContext', () => ({ useAuth: () => auth }));

const chatState = {
  character: { name: 'Ann', id: 'c1' },
  sessionId: 's1',
  messages: [],
  isGenerating: true,
  cast: [{ id: 'c1', dbId: 'c1', name: 'Ann', isHost: true, realismEnabled: true }],
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

const { ChatPage } = await import('./ChatPage');

function wrap(children: ReactNode) {
  return createElement(MemoryRouter, null, children);
}

let container: HTMLDivElement;
let root: Root;

async function flush() {
  await act(async () => {
    await Promise.resolve();
  });
}

async function render() {
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  act(() => {
    root.render(wrap(createElement(ChatPage)));
  });
  await flush();
}

function click(selector: string) {
  const el = container.querySelector(selector) as HTMLElement | null;
  if (!el) throw new Error(`no element for ${selector}`);
  act(() => {
    el.dispatchEvent(new MouseEvent('click', { bubbles: true }));
  });
}

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  (Element.prototype as unknown as { scrollTo: () => void }).scrollTo = () => {};
  (window as { innerWidth: number }).innerWidth = 1280;
  authCalls.length = 0;
  eventHandlers = [];
  stateAnswer = () => Promise.resolve(chatState);
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

describe('ChatPage session recovery', () => {
  it('drops back to sign-in (not a forever spinner) when the session is revoked', async () => {
    stateAnswer = () => Promise.reject(new FakeApiError(401, 'unauthorized'));
    await render();
    expect(authCalls).toEqual([false]);
    expect(container.querySelector('.spinner')).toBeNull();
    expect(container.textContent).toContain('sign in again');
  });

  it('says what went wrong, with a retry, when the desktop is unreachable', async () => {
    stateAnswer = () => Promise.reject(new TypeError('Failed to fetch'));
    await render();
    expect(authCalls).toEqual([]); // not a sign-out — do not evict the session
    expect(container.querySelector('.spinner')).toBeNull();
    expect(container.textContent).toContain('Try again');
  });
});

describe('ChatPage conversation switch', () => {
  it('drops the old chat\'s live streaming bubble when another chat is opened', async () => {
    await render();
    act(() => emit({ event: 'token', data: 'half a rep' }));
    expect(container.querySelector('.bubble.ai.streaming')).not.toBeNull();

    // PR 1a: at wide, Conversations ▾ sits one click deeper — behind the
    // composer's Chat Management folder. Same button, one lookup added.
    click('.chat-mgmt-btn');
    await flush();
    click('.conversations-btn');
    await flush();
    click('.conv-item');
    await flush();

    expect(container.querySelector('.bubble.ai.streaming')).toBeNull();
  });

  it('drops it for "New chat" too', async () => {
    await render();
    act(() => emit({ event: 'token', data: 'half a rep' }));
    expect(container.querySelector('.bubble.ai.streaming')).not.toBeNull();

    // PR 1a: at wide, Conversations ▾ sits one click deeper — behind the
    // composer's Chat Management folder. Same button, one lookup added.
    click('.chat-mgmt-btn');
    await flush();
    click('.conversations-btn');
    await flush();
    click('.new-chat');
    await flush();

    expect(container.querySelector('.bubble.ai.streaming')).toBeNull();
  });
});
