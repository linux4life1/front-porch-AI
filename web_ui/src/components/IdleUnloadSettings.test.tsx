// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "Free graphics memory when idle" on the phone: it shows the host's choice
// (Off unless changed), a new choice is saved to the same setting the desktop
// uses, a save that fails is put back and said so, and a host without the
// setting shows no card. Renders the real component; the host's answers are
// supplied.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const { get, post } = vi.hoisted(() => ({ get: vi.fn(), post: vi.fn() }));
vi.mock('../api/client', () => ({ api: { get, post } }));

import { IdleUnloadSettings } from './IdleUnloadSettings';

let container: HTMLDivElement;
let root: Root;

async function show(settings: Record<string, unknown>) {
  get.mockResolvedValue(settings);
  await act(async () => {
    root.render(createElement(IdleUnloadSettings));
  });
}

const select = () =>
  container.querySelector<HTMLSelectElement>('[data-testid="kobold-idle-select"]');

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

describe('Free graphics memory when idle', () => {
  it('shows Off by default with the desktop choices, and a new choice is saved', async () => {
    await show({ koboldIdleUnloadMinutes: 0, koboldIdleUnloadChoices: [0, 10, 30, 60] });
    expect(select()?.value).toBe('0');
    expect(Array.from(select()!.options).map((o) => o.textContent)).toEqual([
      'Off',
      '10 min',
      '30 min',
      '1 hour',
    ]);

    post.mockResolvedValue({});
    await choose('30');

    expect(post).toHaveBeenCalledWith('/api/settings', { koboldIdleUnloadMinutes: 30 });
    expect(select()?.value).toBe('30');
  });

  it('a save that fails puts the old choice back and says so', async () => {
    await show({ koboldIdleUnloadMinutes: 10, koboldIdleUnloadChoices: [0, 10, 30, 60] });
    post.mockRejectedValue(new Error('offline'));

    await choose('60');

    expect(select()?.value).toBe('10');
    expect(container.querySelector('[role="alert"]')?.textContent).toContain('could not be saved');
  });

  it('a host without the setting shows no card', async () => {
    await show({ backend: 'kobold' });
    expect(container.querySelector('[data-testid="kobold-idle-card"]')).toBeNull();
  });
});
