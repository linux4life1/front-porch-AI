// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Time-skip bridge switch sits under Passage of Time, reads the host's
// value, and writes `timeSkipBridgeEnabled` back. Desktop twin: the row in
// lib/ui/settings/tabs/porch_life_tab.dart.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const post = vi.fn(async (_url?: string, _body?: unknown) => ({}));

vi.mock('../api/client', () => ({
  ApiError: class ApiError extends Error {},
  api: {
    get: () =>
      Promise.resolve({
        realism: { passageOfTimeDefault: true, timeSkipBridgeEnabled: true },
      }),
    post: (url: string, body?: unknown) => post(url, body),
  },
}));

const { PorchLifeSettings } = await import('./PorchLifeSettings');

let container: HTMLDivElement;
let root: Root;

beforeEach(async () => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  await act(async () => {
    root.render(createElement(PorchLifeSettings));
    await Promise.resolve();
  });
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
  post.mockClear();
});

describe('Porch Life Time-skip bridge', () => {
  it('shows the host value and writes the switch back', () => {
    const input = container.querySelector<HTMLInputElement>(
      'input[aria-label="Time-skip bridge"]',
    );
    expect(input).not.toBeNull();
    expect(input!.checked).toBe(true);
    expect(container.textContent).toContain('a short narrator card fills in how those days went');

    act(() => input!.click());
    expect(post).toHaveBeenCalledWith('/api/settings', {
      realism: { timeSkipBridgeEnabled: false },
    });
  });
});
