// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A transcript action the desktop refuses must say so. These rejected into
// nowhere: a failed regenerate did nothing, and a failed edit closed the editor
// and threw the user's new text away.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { ApiError } from '../../api/client';

const post = vi.fn();

vi.mock('../../api/client', async (orig) => ({
  ...(await orig<typeof import('../../api/client')>()),
  api: { post: (...args: unknown[]) => post(...args) },
}));

const { useChatSend } = await import('./useChatSend');

type Hook = ReturnType<typeof useChatSend>;
let hook: Hook;
let container: HTMLDivElement;
let root: Root;

function Probe() {
  hook = useChatSend(async () => {});
  return null;
}

describe('useChatSend failures', () => {
  beforeEach(async () => {
    post.mockReset();
    container = document.createElement('div');
    document.body.appendChild(container);
    root = createRoot(container);
    await act(async () => root.render(createElement(Probe)));
  });

  afterEach(() => {
    act(() => root.unmount());
    container.remove();
  });

  it('a refused regenerate shows a plain-English banner', async () => {
    post.mockRejectedValueOnce(new ApiError(409, 'Already generating', {}));
    await act(async () => {
      await hook.regenerate();
    });
    expect(hook.actionError).toBe("Couldn't regenerate that reply. Already generating");
  });

  it('a failed edit keeps the editor open and explains why', async () => {
    await act(async () => {
      hook.beginEdit({ index: 2, text: 'old line' } as Parameters<Hook['beginEdit']>[0]);
    });
    post.mockRejectedValueOnce(new TypeError('Failed to fetch'));

    let thrown: unknown;
    await act(async () => {
      await hook.saveEdit('my new line').catch((e: unknown) => {
        thrown = e;
      });
    });

    expect(post).toHaveBeenCalledWith('/api/chat/edit', { index: 2, text: 'my new line' });
    expect(hook.editTarget).toEqual({ index: 2, text: 'old line' });
    expect((thrown as Error).message).toMatch(/^Couldn't save your edit\. Front Porch AI didn't answer/);
  });

  it('a successful edit closes the editor', async () => {
    await act(async () => {
      hook.beginEdit({ index: 0, text: 'hi' } as Parameters<Hook['beginEdit']>[0]);
    });
    post.mockResolvedValueOnce({});
    await act(async () => {
      await hook.saveEdit('hello');
    });
    expect(hook.editTarget).toBeNull();
  });
});
