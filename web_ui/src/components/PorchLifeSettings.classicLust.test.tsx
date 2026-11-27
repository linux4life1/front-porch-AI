// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// After Dark → Classic Lust bar (docs/design/heat-meter.md): off by default,
// which shows the Heat bar; on keeps the old single Lust bar. The phone's row
// reads the desktop's setting and writes `realism.classicLustEnabled`. Desktop
// twin: the classic-lust-row in lib/ui/settings/tabs/porch_life_groups.dart.

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
        realism: {
          realismAllowed: true,
          adultThemesEnabled: true,
          nsfwCooldownDefault: true,
        },
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

describe('Porch Life Classic Lust bar row', () => {
  it('sits under After Dark, starts off, and writes the desktop setting', () => {
    const row = input('Classic Lust bar');
    expect(row.checked).toBe(false);
    expect(row.disabled).toBe(false);

    act(() => row.click());
    expect(post).toHaveBeenCalledWith('/api/settings', {
      realism: { classicLustEnabled: true },
    });
  });

  it('sits between Afterglow and Acts on desires, as on the desktop', () => {
    const labels = [...container.querySelectorAll('input[aria-label]')].map(
      (el) => el.getAttribute('aria-label'),
    );
    const at = labels.indexOf('Classic Lust bar');
    expect(labels[at - 1]).toBe('Afterglow');
    expect(labels[at + 1]).toBe('Acts on desires');
  });
});
