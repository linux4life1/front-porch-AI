// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Group settings save on blur. A refused save must say so, not vanish.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { ApiError } from '../api/client';

const post = vi.fn();
vi.mock('../api/client', async (orig) => ({
  ...(await orig<typeof import('../api/client')>()),
  api: { post: (...args: unknown[]) => post(...args) },
}));

const { GroupSettings } = await import('./GroupSettings');

let container: HTMLDivElement;
let root: Root;

const group = {
  name: 'Porch',
  turnOrder: 'roundRobin',
  directorMode: false,
  systemPrompt: 'old prompt',
  scenario: '',
  firstMessage: '',
  members: [],
};

describe('GroupSettings save', () => {
  beforeEach(() => {
    vi.spyOn(console, 'warn').mockImplementation(() => {});
    container = document.createElement('div');
    document.body.appendChild(container);
    root = createRoot(container);
  });

  afterEach(() => {
    act(() => root.unmount());
    container.remove();
    vi.restoreAllMocks();
  });

  it('shows why a blur-save failed, and clears once a save lands', async () => {
    await act(async () => {
      root.render(
        createElement(GroupSettings, { group, groupId: 'g1', onToggleDirector: () => {} }),
      );
    });
    const prompt = container.querySelector('textarea') as HTMLTextAreaElement;

    post.mockRejectedValueOnce(new ApiError(500, 'disk full', {}));
    await act(async () => {
      prompt.dispatchEvent(new FocusEvent('focusout', { bubbles: true }));
    });
    expect(container.querySelector('[role="alert"]')?.textContent).toContain(
      "Couldn't save the group settings.",
    );

    post.mockResolvedValueOnce({});
    await act(async () => {
      prompt.dispatchEvent(new FocusEvent('focusout', { bubbles: true }));
    });
    expect(container.querySelector('[role="alert"]')).toBeNull();
  });
});
