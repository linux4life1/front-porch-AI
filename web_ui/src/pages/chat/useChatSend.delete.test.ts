// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Desktop confirms before deleting a bubble. The PWA posted immediately.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement, useEffect } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const post = vi.fn(async () => ({}));

vi.mock('../../api/client', () => ({
  api: {
    post: (...args: unknown[]) => post(...args),
  },
}));

const { useChatSend } = await import('./useChatSend');

let container: HTMLDivElement;
let root: Root;

function Probe({
  onReady,
}: {
  onReady: (del: (index: number) => Promise<void>) => void;
}) {
  const { del } = useChatSend(async () => {});
  useEffect(() => {
    onReady(del);
  }, [del, onReady]);
  return null;
}

describe('useChatSend delete confirm', () => {
  beforeEach(() => {
    container = document.createElement('div');
    document.body.appendChild(container);
    root = createRoot(container);
    post.mockClear();
  });
  afterEach(() => {
    act(() => root.unmount());
    container.remove();
  });

  it('does not delete when the user cancels the confirm', async () => {
    const confirm = vi.spyOn(window, 'confirm').mockReturnValue(false);
    let del!: (index: number) => Promise<void>;
    act(() => {
      root.render(
        createElement(Probe, {
          onReady: (fn) => {
            del = fn;
          },
        }),
      );
    });
    await act(async () => {
      await del(3);
    });
    expect(confirm).toHaveBeenCalled();
    expect(post).not.toHaveBeenCalled();
    confirm.mockRestore();
  });

  it('posts delete after confirm', async () => {
    const confirm = vi.spyOn(window, 'confirm').mockReturnValue(true);
    let del!: (index: number) => Promise<void>;
    act(() => {
      root.render(
        createElement(Probe, {
          onReady: (fn) => {
            del = fn;
          },
        }),
      );
    });
    await act(async () => {
      await del(3);
    });
    expect(confirm.mock.calls[0][0]).toMatch(/can't be undone/i);
    expect(post).toHaveBeenCalledWith('/api/chat/delete', { index: 3 });
    confirm.mockRestore();
  });
});
