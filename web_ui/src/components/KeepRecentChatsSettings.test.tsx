// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "Keep recent chats ready" on the phone: it shows the host's count (Off,
// only the open chat, unless changed) with the desktop's choices, a new
// count is saved to the same setting the desktop and the keeper use, a save
// that fails is put back and said so, and a host without the setting shows
// no card. Renders the real component; the host's answers are supplied.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const { get, post } = vi.hoisted(() => ({ get: vi.fn(), post: vi.fn() }));
vi.mock('../api/client', () => ({ api: { get, post } }));

import { KeepRecentChatsSettings } from './KeepRecentChatsSettings';

let container: HTMLDivElement;
let root: Root;

async function show(settings: Record<string, unknown>) {
  get.mockResolvedValue(settings);
  await act(async () => {
    root.render(createElement(KeepRecentChatsSettings));
  });
}

const select = () =>
  container.querySelector<HTMLSelectElement>('[data-testid="kobold-keep-recent-select"]');

async function choose(value: string) {
  await act(async () => {
    const s = select()!;
    s.value = value;
    s.dispatchEvent(new Event('change', { bubbles: true }));
  });
}

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  get.mockReset();
  post.mockReset();
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

describe('Keep recent chats ready', () => {
  it('shows Off by default with the desktop choices, and a new count is saved', async () => {
    await show({ koboldKeepRecentChats: 0, koboldKeepRecentChoices: [0, 1, 2, 3, 4] });
    expect(select()?.value).toBe('0');
    expect(Array.from(select()!.options).map((o) => o.textContent)).toEqual([
      'Off',
      '1',
      '2',
      '3',
      '4',
    ]);
    expect(container.textContent).toContain('frees its memory when you leave it');

    post.mockResolvedValue({});
    await choose('2');

    expect(post).toHaveBeenCalledWith('/api/settings', { koboldKeepRecentChats: 2 });
    expect(select()?.value).toBe('2');
  });

  it('a save that fails puts the old count back and says so', async () => {
    await show({ koboldKeepRecentChats: 1, koboldKeepRecentChoices: [0, 1, 2, 3, 4] });
    post.mockRejectedValue(new Error('offline'));

    await choose('3');

    expect(select()?.value).toBe('1');
    expect(container.querySelector('[role="alert"]')?.textContent).toContain('could not be saved');
  });

  it('a host without the setting shows no card', async () => {
    await show({ backend: 'kobold' });
    expect(container.querySelector('[data-testid="kobold-keep-recent-card"]')).toBeNull();
  });
});
