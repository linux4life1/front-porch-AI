// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The goal-check overlay offers "Skip goal check" (desktop twin:
// objective_check_overlay.dart). It stops only the goal check: the button
// posts to /api/chat/skip-objective-check and the overlay closes. The
// Realism overlay keeps its own Cancel and has no Skip.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { ProcessingOverlay, NO_PROCESSING, type Processing } from './ProcessingOverlay';

const get = vi.fn();
const post = vi.fn(async () => ({}));

vi.mock('../api/client', async (orig) => ({
  ...(await orig<typeof import('../api/client')>()),
  api: {
    get: (...args: unknown[]) => get(...args),
    post: (...args: unknown[]) => post(...args),
  },
}));
const auth = { setAuthenticated: () => {} };
vi.mock('../auth/AuthContext', () => ({ useAuth: () => auth }));

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

const { useChatSession } = await import('../pages/chat/useChatSession');

let container: HTMLDivElement;
let root: Root;

beforeEach(() => {
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
});
afterEach(() => {
  act(() => root.unmount());
  container.remove();
  vi.unstubAllGlobals();
});

const button = (label: string) =>
  Array.from(container.querySelectorAll('button')).find((b) => b.textContent === label);

function renderOverlay(p: Processing) {
  const onCancel = vi.fn();
  const onSkipObjective = vi.fn();
  act(() => {
    root.render(createElement(ProcessingOverlay, { p, onCancel, onSkipObjective }));
  });
  return { onCancel, onSkipObjective };
}

describe('ProcessingOverlay Skip goal check', () => {
  it('shows Skip goal check while the goal check runs, and a click asks to skip', () => {
    const { onCancel, onSkipObjective } = renderOverlay({
      ...NO_PROCESSING,
      active: true,
      objective: true,
    });
    expect(button('Stop this reply')).toBeUndefined();
    act(() => button('Skip goal check')!.click());
    expect(onSkipObjective).toHaveBeenCalledTimes(1);
    expect(onCancel).not.toHaveBeenCalled();
  });

  it('the Realism overlay has no Skip goal check', () => {
    renderOverlay({ ...NO_PROCESSING, active: true, realism: true, objective: true });
    expect(button('Skip goal check')).toBeUndefined();
    expect(button('Stop this reply')).toBeDefined();
  });

  it('skipping posts the skip route and closes the overlay', async () => {
    vi.stubGlobal('WebSocket', TestSocket);
    get.mockResolvedValue({ sessionId: 'c1', isGenerating: true, messages: [], character: { name: 'A', id: '1' } });
    post.mockClear();
    let session!: ReturnType<typeof useChatSession>;
    function Probe() {
      session = useChatSession();
      return null;
    }
    await act(async () => {
      root.render(createElement(MemoryRouter, null, createElement(Probe)));
    });
    await act(async () =>
      TestSocket.last.emit({ event: 'processing', active: true, realism: false, objective: true }),
    );
    expect(session.processing.objective).toBe(true);

    await act(async () => session.skipObjectiveCheck());
    expect(post).toHaveBeenCalledWith('/api/chat/skip-objective-check');
    expect(post).not.toHaveBeenCalledWith('/api/chat/cancel-realism');
    expect(session.processing.active).toBe(false);
  });
});
