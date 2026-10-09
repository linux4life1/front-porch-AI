// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "Temperatures in °F" hangs off Story Weather, which hangs off Passage of
// Time. With the clock off, Story Weather greys out even while its own switch
// is on, so °F must grey out with it. Desktop twin:
// test/ui/settings/porch_life_fahrenheit_gate_test.dart.

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
        realism: { passageOfTimeDefault: false, weatherEnabled: true },
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

const input = (label: string) => {
  const el = container.querySelector<HTMLInputElement>(`input[aria-label="${label}"]`);
  if (!el) throw new Error(`no switch labelled ${label}`);
  return el;
};

describe('Porch Life °F row', () => {
  it('greys out with the clock off, and comes back when the clock goes on', () => {
    expect(input('Story Weather').disabled).toBe(true);
    expect(input('Temperatures in °F').disabled).toBe(true);

    act(() => input('Passage of Time').click());
    expect(input('Temperatures in °F').disabled).toBe(false);
  });
});
