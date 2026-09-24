// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Passage of Time is the only clock driver. The leftover standalone
// sub-switch must not come back on the web Porch Life card.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

vi.mock('../api/client', () => ({
  ApiError: class ApiError extends Error {},
  api: {
    get: () =>
      Promise.resolve({
        realism: { passageOfTimeDefault: true, realismDefault: false },
      }),
    post: async () => ({}),
  },
}));

const { PorchLifeSettings } = await import('./PorchLifeSettings');

let container: HTMLDivElement;
let root: Root;

beforeEach(async () => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean })
    .IS_REACT_ACT_ENVIRONMENT = true;
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
});

describe('Porch Life Passage of Time', () => {
  it('is the new-chat default and does not nest a standalone switch', () => {
    expect(container.textContent).toContain('Passage of Time');
    expect(container.textContent).toContain('default for new chats');
    expect(container.textContent).toContain('Automatic Passage of Time');
    expect(container.textContent).not.toContain(
      'Keep the clock running without the engine',
    );
    expect(
      container.querySelector(
        'input[aria-label="Keep the clock running without the engine"]',
      ),
    ).toBeNull();
  });
});
