// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Issue 668: on a touch screen the reprocess pills end the top chip row instead
// of sitting on their own row right above the message icons. The mouse layout
// is pinned by ChipsRow.reprocess.test.tsx.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { ChipsRow } from './ChipsRow';
import { type Chips } from './chatTypes';

let container: HTMLDivElement;
let root: Root;

describe('ChipsRow reprocess pills on a touch screen (#668)', () => {
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

  it('puts Reprocess and Revert at the end of the Realism row, not on their own row', () => {
    const onRevert = vi.fn();
    const onReprocess = vi.fn();
    act(() => {
      root.render(createElement(ChipsRow, {
        chips: { bondDelta: 2, trustDelta: 1, needsReprocessable: true, needsRevertable: true, needsDeltas: { social: { delta: 8, reason: '' } } } as Chips,
        isLast: true, busy: false, onReprocess, onRevert,
      }));
    });
    const reprocess = byLabel('Manual Reprocess');
    const revert = byLabel('Revert reprocess');
    expect(reprocess?.closest('.chips-row.realism')).not.toBeNull();
    expect(revert?.closest('.chips-row.realism')).not.toBeNull();
    expect(container.querySelector('.needs-reprocess-row')).toBeNull();
    const realismRow = container.querySelector('.chips-row.realism')!;
    expect(realismRow.lastElementChild).toBe(revert);
    act(() => reprocess!.dispatchEvent(new MouseEvent('click', { bubbles: true })));
    act(() => revert!.dispatchEvent(new MouseEvent('click', { bubbles: true })));
    expect(onReprocess).toHaveBeenCalledTimes(1);
    expect(onRevert).toHaveBeenCalledTimes(1);
  });

  it('ends the Needs row when the reply has no Realism chips', () => {
    act(() => {
      root.render(createElement(ChipsRow, {
        chips: { needsReprocessable: true, needsDeltas: { hunger: { delta: -5, reason: '' } } } as Chips,
        isLast: true, busy: false, onReprocess: vi.fn(), onRevert: vi.fn(),
      }));
    });
    expect(byLabel('Manual Reprocess')?.closest('.chips-row.needs')).not.toBeNull();
    expect(container.querySelector('.needs-reprocess-row')).toBeNull();
  });
});
