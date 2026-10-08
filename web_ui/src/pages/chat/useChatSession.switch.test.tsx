// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Switching chats while a reply is still streaming: the desktop finishes that
// reply before it switches, and its tokens keep arriving on the shared socket
// with no chat id. They must not reappear as a live bubble in the new chat.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const get = vi.fn();
const post = vi.fn(async () => ({}));

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

function chatState(sessionId: string, isGenerating: boolean) {
  return { sessionId, isGenerating, messages: [], character: { name: 'A', id: '1' } };
}

describe('useChatSession chat switch mid-reply', () => {
  beforeEach(async () => {
    vi.stubGlobal('WebSocket', TestSocket);
    get.mockReset();
    get.mockResolvedValue(chatState('chat-a', true));
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

  it("drops the old chat's tokens until its reply is over", async () => {
    await act(async () => TestSocket.last.emit({ event: 'token', data: 'Old rep' }));
    expect(session.streaming).toBe('Old rep');

    get.mockResolvedValue(chatState('chat-b', true));
    await act(async () => {
      await session.loadSession('chat-b');
    });
    await act(async () => TestSocket.last.emit({ event: 'token', data: 'ly continues' }));
    expect(session.streaming).toBe('');

    get.mockResolvedValue(chatState('chat-b', false));
    await act(async () => TestSocket.last.emit({ event: 'done' }));
    await act(async () => TestSocket.last.emit({ event: 'token', data: 'New chat reply' }));
    expect(session.streaming).toBe('New chat reply');
  });

  it('switching from an idle chat does not swallow the next reply', async () => {
    get.mockResolvedValue(chatState('chat-a', false));
    await act(async () => {
      await session.refresh();
    });
    get.mockResolvedValue(chatState('chat-b', false));
    await act(async () => {
      await session.loadSession('chat-b');
    });
    await act(async () => TestSocket.last.emit({ event: 'token', data: 'Hello' }));
    expect(session.streaming).toBe('Hello');
  });
});
