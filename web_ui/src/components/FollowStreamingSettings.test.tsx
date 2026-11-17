// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { act, createElement } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const post = vi.fn(async (_url?: string, _body?: unknown) => ({}));
let savedStreaming = true;

vi.mock('../api/client', () => ({
  api: {
    get: () => Promise.resolve({ followStreamingReplies: savedStreaming }),
    post: (url: string, body?: unknown) => post(url, body),
  },
}));

const { FollowStreamingSettings } = await import('./FollowStreamingSettings');

let container: HTMLDivElement;
let root: Root;

async function mount(node: ReturnType<typeof createElement>) {
  await act(async () => {
    root.render(node);
    await Promise.resolve();
  });
}

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  post.mockClear();
  savedStreaming = true;
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

describe('FollowStreamingSettings', () => {
  it('renders switch with min 48px hit area and toggles state on click', async () => {
    savedStreaming = true;
    await mount(createElement(FollowStreamingSettings));

    const card = container.querySelector('[data-testid="follow-streaming-card"]');
    expect(card).not.toBeNull();

    const switchLabel = container.querySelector<HTMLLabelElement>('label.toggle-switch');
    expect(switchLabel).not.toBeNull();

    const box = container.querySelector<HTMLInputElement>('input[aria-label="Follow streaming replies"]')!;
    expect(box.checked).toBe(true);

    await act(async () => {
      box.click();
    });

    expect(box.checked).toBe(false);
    expect(post).toHaveBeenCalledWith('/api/settings', { followStreamingReplies: false });
  });
});
