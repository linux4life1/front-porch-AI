// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// PR 1b: the touch screen uses the same chip rows as the mouse — Realism,
// then Needs, then the Manual Reprocess / Revert row. Issue 668's inline
// placement (the pills at the end of a chip row) was for the old phone
// layout, where the chips sat above the message icons; the desktop row keeps
// the pills inside the bubble, under the chips, as the sketch draws them.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { ChipsRow } from './ChipsRow';
import { type Chips } from './chatTypes';

let container: HTMLDivElement;
let root: Root;

describe('ChipsRow reprocess pills on a touch screen (PR 1b)', () => {
  let original: typeof window.matchMedia | undefined;
  const touchMatchMedia = (query: string) =>
    ({
      matches: query.includes('hover: none'),
      media: query,
      addEventListener: () => {},
      removeEventListener: () => {},
    }) as unknown as MediaQueryList;

  beforeEach(() => {
    original = window.matchMedia;
    window.matchMedia = touchMatchMedia;
    container = document.createElement('div');
    document.body.appendChild(container);
    root = createRoot(container);
  });
  afterEach(() => {
    act(() => root.unmount());
    container.remove();
    window.matchMedia = original as typeof window.matchMedia;
  });

  const byLabel = (label: string) => container.querySelector(`button[aria-label="${label}"]`) as HTMLButtonElement | null;

  it('keeps Reprocess and Revert on their own row, under the chips', () => {
    const onRevert = vi.fn();
    const onReprocess = vi.fn();
    act(() => {
      root.render(createElement(ChipsRow, {
        chips: { bondDelta: 2, trustDelta: 1, needsReprocessable: true, needsRevertable: true, needsDeltas: { social: { delta: 8, reason: '' } } } as Chips,
        isLast: true, busy: false, onReprocess, onRevert,
      }));
    });
    const reprocess = Array.from(container.querySelectorAll('button')).find((b) =>
      (b.textContent ?? '').includes('Manual Reprocess'),
    )!;
    const revert = Array.from(container.querySelectorAll('button')).find((b) =>
      (b.textContent ?? '').includes('Revert'),
    )!;
    const row = container.querySelector('.needs-reprocess-row')!;
    expect(row).not.toBeNull();
    expect(reprocess.parentElement).toBe(row);
    expect(revert.parentElement).toBe(row);
    expect(reprocess.closest('.chips-row')).toBeNull();
    expect(revert.closest('.chips-row')).toBeNull();
    act(() => reprocess.dispatchEvent(new MouseEvent('click', { bubbles: true })));
    act(() => revert.dispatchEvent(new MouseEvent('click', { bubbles: true })));
    expect(onReprocess).toHaveBeenCalledTimes(1);
    expect(onRevert).toHaveBeenCalledTimes(1);
    expect(byLabel('Manual Reprocess')).toBeNull(); // no second, inline copy
  });

  it('the Needs row is still its own row when the reply has no Realism chips', () => {
    act(() => {
      root.render(createElement(ChipsRow, {
        chips: { needsReprocessable: true, needsDeltas: { hunger: { delta: -5, reason: '' } } } as Chips,
        isLast: true, busy: false, onReprocess: vi.fn(), onRevert: vi.fn(),
      }));
    });
    expect(container.querySelectorAll('.chips-row')).toHaveLength(1);
    expect(container.querySelector('.chips-row.needs')).not.toBeNull();
    expect(container.querySelector('.needs-reprocess-row')).not.toBeNull();
  });
});
