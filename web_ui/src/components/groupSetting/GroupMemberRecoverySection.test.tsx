// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The phone's Group Settings: each member's Recovery block shows while
// Afterglow runs for them, and an edit reaches that member through the
// chat's tools once the last change settles.

import { act, createElement } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';

const posts: { path: string; body: unknown }[] = [];
// Holds the next save open until released.
let hold: { release: () => void } | null = null;

vi.mock('../../api/client', () => ({
  api: {
    post: async (path: string, body: unknown) => {
      posts.push({ path, body });
      if (hold) {
        const h = hold;
        await new Promise<void>((r) => (h.release = r));
      }
      return {};
    },
  },
}));

const { GroupMemberRecoverySection } = await import('./GroupMemberRecoverySection');

let container: HTMLDivElement;
let root: Root;

beforeEach(() => {
  vi.useFakeTimers();
  posts.length = 0;
  hold = null;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
  vi.useRealTimers();
});

it("shows a member's Recovery block only while Afterglow runs for them, and saves an edit to them", async () => {
  act(() => {
    root.render(
      createElement(GroupMemberRecoverySection, {
        members: [
          { id: 'mem-ana', name: 'Ana', afterglowRuns: true, recovery: { recoveryMode: 'auto' } },
          { id: 'mem-bea', name: 'Bea', afterglowRuns: false },
        ],
      }),
    );
  });
  expect(container.querySelector('[data-testid="member-recovery-mem-ana"]')).not.toBeNull();
  expect(container.querySelector('[data-testid="member-recovery-mem-bea"]'), 'Bea is switched off').toBeNull();

  const preset = container.querySelector<HTMLSelectElement>('[data-testid="member-recovery-mem-ana"] select')!;
  act(() => {
    preset.value = 'none';
    preset.dispatchEvent(new Event('change', { bubbles: true }));
  });
  expect(posts, 'waits for the last change').toHaveLength(0);
  await act(async () => {
    vi.advanceTimersByTime(500);
  });
  expect(posts).toHaveLength(1);
  expect(posts[0].path).toBe('/api/chat/tools/member-recovery');
  expect((posts[0].body as { id: string }).id).toBe('mem-ana');
  expect((posts[0].body as { recovery: { recoveryMode: string } }).recovery.recoveryMode).toBe('soft');
});

it('shows a change made elsewhere once nothing of its own is waiting to save', async () => {
  const show = (recovery: unknown) =>
    act(() => {
      root.render(
        createElement(GroupMemberRecoverySection, {
          members: [{ id: 'mem-ana', name: 'Ana', afterglowRuns: true, recovery }],
        }),
      );
    });
  const preset = () => container.querySelector<HTMLSelectElement>('[data-testid="member-recovery-mem-ana"] select')!;
  show({ recoveryMode: 'auto' });
  act(() => {
    preset().value = 'none';
    preset().dispatchEvent(new Event('change', { bubbles: true }));
  });
  await act(async () => {
    vi.advanceTimersByTime(500);
  });
  show({ recoveryMode: 'hard', recoveryMinutes: 30 });
  expect(preset().value, 'the desktop set Short (30) since').toBe('short');
});

it('keeps its own value while the save is out, whatever an older snapshot says', async () => {
  const show = (recovery: unknown) =>
    act(() => {
      root.render(
        createElement(GroupMemberRecoverySection, {
          members: [{ id: 'mem-ana', name: 'Ana', afterglowRuns: true, recovery }],
        }),
      );
    });
  const preset = () => container.querySelector<HTMLSelectElement>('[data-testid="member-recovery-mem-ana"] select')!;
  show({ recoveryMode: 'auto' });
  hold = { release: () => {} };
  const held = hold;
  act(() => {
    preset().value = 'none';
    preset().dispatchEvent(new Event('change', { bubbles: true }));
  });
  await act(async () => {
    vi.advanceTimersByTime(500);
  });
  show({ recoveryMode: 'auto' });
  expect(preset().value, 'a snapshot from before the save landed').toBe('none');
  await act(async () => {
    held.release();
  });
});
