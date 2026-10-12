// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Library Manage Chats modal: lists sessions and delete posts action: 'delete'
// with startReplacement: false so emptying a card does not mint a new chat.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const posts: { path: string; body: unknown }[] = [];

vi.mock('../../api/client', () => ({
  api: {
    get: (path: string) => {
      if (path.startsWith('/api/chat/sessions')) {
        return Promise.resolve({
          sessions: [
            {
              id: 's1',
              preview: 'Coffee on the porch',
              message_count: 4,
              user_message_count: 2,
              date: '2026-08-21T14:05:00.000Z',
            },
          ],
        });
      }
      return Promise.resolve({});
    },
    post: (path: string, body: unknown) => {
      posts.push({ path, body });
      return Promise.resolve({ status: 'ok' });
    },
  },
  ApiError: class ApiError extends Error {},
}));

const { ChatHistoryModal } = await import('./ChatHistoryModal');

let container: HTMLDivElement;
let root: Root;

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  posts.length = 0;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

describe('ChatHistoryModal', () => {
  it('lists sessions then delete posts action: delete', async () => {
    await act(async () => {
      root.render(
        createElement(
          MemoryRouter,
          null,
          createElement(ChatHistoryModal, {
            characterId: 'c1',
            onClose: () => {},
            onNewChat: () => {},
          }),
        ),
      );
    });

    expect(container.textContent).toContain('Manage Chats');
    expect(container.textContent).toContain('Coffee on the porch');

    const trash = container.querySelector('button[aria-label="Delete chat"]') as HTMLButtonElement;
    expect(trash).toBeTruthy();
    await act(async () => {
      trash.click();
    });

    const confirm = [...container.querySelectorAll('button')].find(
      (b) => b.textContent === 'Delete',
    );
    expect(confirm).toBeTruthy();
    await act(async () => {
      confirm!.click();
    });

    expect(posts).toContainEqual({
      path: '/api/chat/session',
      body: { action: 'delete', sessionId: 's1', startReplacement: false },
    });
  });

  it('always offers Start new chat and hands off to onNewChat', async () => {
    const onNewChat = vi.fn();
    await act(async () => {
      root.render(
        createElement(
          MemoryRouter,
          null,
          createElement(ChatHistoryModal, {
            characterId: 'c1',
            onClose: () => {},
            onNewChat,
          }),
        ),
      );
    });

    const btn = Array.from(container.querySelectorAll('button')).find((b) =>
      b.textContent?.includes('Start new chat'),
    ) as HTMLButtonElement;
    expect(btn).toBeTruthy();
    await act(async () => {
      btn.click();
    });
    expect(onNewChat).toHaveBeenCalledTimes(1);
  });
});
