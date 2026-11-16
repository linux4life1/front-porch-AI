// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The regen wire body: the plain last-reply regen posts exactly what it
// always posted (no keys appear), and only the buried-host main-character
// path adds `target: 'mainCharacter'` — with the critique note and the
// lookup selection riding along unchanged (drift ledger #15a; the route
// 400s any other target, so the spelling matters).

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement, useEffect } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const post = vi.fn(async () => ({}));

vi.mock('../../api/client', () => ({
  api: {
    post: (...args: unknown[]) => post(...args),
    get: vi.fn(async () => ({})),
  },
}));

const { useChatSend } = await import('./useChatSend');

let container: HTMLDivElement;
let root: Root;
let regenerate!: (
  critique?: string,
  lookup?: { source: 'web' | 'wiki'; query: string },
  target?: 'mainCharacter',
) => Promise<void>;

function Page() {
  const send = useChatSend(async () => {});
  useEffect(() => {
    regenerate = send.regenerate;
  }, [send.regenerate]);
  return null;
}

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  post.mockClear();
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  act(() => root.render(createElement(Page)));
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

const regenBody = () => {
  const call = post.mock.calls.find(([path]) => path === '/api/chat/regenerate');
  return call?.[1] as Record<string, string> | undefined;
};

describe('useChatSend regenerate body', () => {
  it('sends no target — and no body at all when bare — for the plain regen', async () => {
    await act(async () => {
      await regenerate();
    });
    expect(regenBody()).toBeUndefined();
  });

  it('carries the note and lookup without a target on the plain regen', async () => {
    await act(async () => {
      await regenerate('too cautious', { source: 'web', query: 'herbal teas' });
    });
    expect(regenBody()).toEqual({
      critique: 'too cautious',
      webQuery: 'herbal teas',
    });
  });

  it('adds exactly the mainCharacter target when asked for the host', async () => {
    await act(async () => {
      await regenerate('too cautious', { source: 'wiki', query: 'herbal teas' }, 'mainCharacter');
    });
    expect(regenBody()).toEqual({
      critique: 'too cautious',
      wikiQuery: 'herbal teas',
      target: 'mainCharacter',
    });
  });

  it('posts the target alone when the dialog was left empty', async () => {
    await act(async () => {
      await regenerate('', undefined, 'mainCharacter');
    });
    expect(regenBody()).toEqual({ target: 'mainCharacter' });
  });
});
