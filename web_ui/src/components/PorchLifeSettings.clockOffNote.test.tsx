// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Porch Life's Needs default carries the clock-off line while Passage of Time
// is off, whether or not Needs itself is on, and drops it the moment the
// clock goes back on. Desktop twin: the Porch Life case in
// test/ui/widgets/needs_clock_off_note_test.dart.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const LINE = 'With Passage of time off, needs change only when the story says so.';

const post = vi.fn(async (_url?: string, _body?: unknown) => ({}));

vi.mock('../api/client', () => ({
  ApiError: class ApiError extends Error {},
  api: {
    get: () =>
      Promise.resolve({
        realism: { realismDefault: true, needsSimDefault: true, passageOfTimeDefault: false },
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

function row(label: string): HTMLElement {
  const found = [...container.querySelectorAll<HTMLElement>('.pl-row')].find(
    (r) => r.querySelector('.pl-label')?.textContent === label,
  );
  if (!found) throw new Error(`no Porch Life row labelled ${label}`);
  return found;
}

function click(label: string) {
  const input = container.querySelector<HTMLInputElement>(`input[aria-label="${label}"]`);
  if (!input) throw new Error(`no switch labelled ${label}`);
  act(() => input.click());
}

describe('Porch Life Needs row', () => {
  it('shows the clock-off line while the clock is off, Needs on or off', () => {
    expect(row('Needs').querySelector('.needs-clock-off')?.textContent).toBe(LINE);

    click('Needs');
    expect(post).toHaveBeenCalledWith('/api/settings', { realism: { needsSimDefault: false } });
    expect(row('Needs').querySelector('.needs-clock-off')?.textContent).toBe(LINE);
  });

  it('drops the line when Passage of Time goes back on', () => {
    click('Passage of Time');
    expect(post).toHaveBeenCalledWith('/api/settings', { realism: { passageOfTimeDefault: true } });
    expect(container.querySelector('.needs-clock-off')).toBeNull();
    expect(container.textContent).not.toContain(LINE);
  });
});
