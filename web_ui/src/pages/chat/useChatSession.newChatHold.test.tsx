// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// New chat and opening another conversation: the host refuses a send until
// the switch lands, so the page holds the chat (no composer) until the switch
// request and the refresh after it are both done. The Director journey typed
// /join while New chat was still running and the join came out half done.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const get = vi.fn();
const post = vi.fn<(...args: unknown[]) => Promise<unknown>>(async () => ({}));

vi.mock('../../api/client', async (orig) => ({
  ...(await orig<typeof import('../../api/client')>()),
  api: {
    get: (...args: unknown[]) => get(...args),
    post: (...args: unknown[]) => post(...args),
  },
}));
const auth = { setAuthenticated: () => {} };
vi.mock('../../auth/AuthContext', () => ({ useAuth: () => auth }));

/** Stand-in for the browser socket: the test pushes server frames itself. */
class TestSocket {
  static last: TestSocket;
  onopen: (() => void) | null = null;
  onmessage: ((m: { data: string }) => void) | null = null;
  onclose: (() => void) | null = null;
  onerror: (() => void) | null = null;
  constructor() {
    TestSocket.last = this;
  }
  send() {}
  close() {}
  emit(frame: Record<string, unknown>) {
    this.onmessage?.({ data: JSON.stringify(frame) });
  }
}

const { useChatSession } = await import('./useChatSession');

type Session = ReturnType<typeof useChatSession>;
let session: Session;
let container: HTMLDivElement;
let root: Root;

function Probe() {
  session = useChatSession();
  return null;
}

function chatState(sessionId: string) {
  return { sessionId, isGenerating: false, messages: [], character: { name: 'A', id: '1' } };
}

describe('useChatSession holds the chat while it switches', () => {
  beforeEach(async () => {
    vi.stubGlobal('WebSocket', TestSocket);
    get.mockReset();
    post.mockReset();
    get.mockResolvedValue(chatState('chat-a'));
    container = document.createElement('div');
    document.body.appendChild(container);
    root = createRoot(container);
    await act(async () => {
      root.render(createElement(MemoryRouter, null, createElement(Probe)));
    });
  });

  afterEach(() => {
    act(() => root.unmount());
    container.remove();
    vi.unstubAllGlobals();
  });

  for (const [what, start] of [
    ['New chat', () => session.newChat()],
    ['opening another conversation', () => session.loadSession('chat-b')],
  ] as const) {
    it(`${what}: switching until the host has answered and state is fresh`, async () => {
      let answer: () => void = () => {};
      post.mockImplementation(() => new Promise((resolve) => { answer = () => resolve({}); }));
      expect(session.switching).toBe(false);
      let done: Promise<void> = Promise.resolve();
      await act(async () => {
        done = start();
      });
      expect(session.switching).toBe(true);

      get.mockResolvedValue(chatState('chat-b'));
      await act(async () => {
        answer();
        await done;
      });
      expect(session.switching).toBe(false);
      expect(session.state?.sessionId).toBe('chat-b');
    });
  }

  it('a refused switch still lets go of the chat', async () => {
    post.mockRejectedValue(new Error('409'));
    await act(async () => {
      await session.newChat().catch(() => {});
    });
    expect(session.switching).toBe(false);
  });
});
