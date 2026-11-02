// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// G: ChipsRow's Manual Reprocess button is gated by chips.needsReprocessable
// alone (/workspace/sow/rn-spec.md item 8: "ChipsRow.tsx needs no change").
// The facade now sets that flag from the resolver (E pins), so this is a
// GUARD: green on Rawhide by design, and it must stay green after the fix.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { ChipsRow } from './ChipsRow';
import { type Chips } from './chatTypes';

let container: HTMLDivElement;
let root: Root;

function render(chips: Chips, isLast = true, busy = false) {
  const onReprocess = vi.fn();
  act(() => {
    root.render(createElement(ChipsRow, { chips, isLast, busy, onReprocess, onRevert: vi.fn() }));
  });
  return onReprocess;
}

const reprocessButton = () =>
  Array.from(container.querySelectorAll('button')).find((b) =>
    (b.textContent ?? '').includes('Manual Reprocess'),
  );

describe('ChipsRow Manual Reprocess gate (guard)', () => {
  beforeEach(() => {
    container = document.createElement('div');
    document.body.appendChild(container);
    root = createRoot(container);
  });
  afterEach(() => {
    act(() => root.unmount());
    container.remove();
  });

  it('G1 guard: shows the button when the facade says needsReprocessable', () => {
    const onReprocess = render({ needsReprocessable: true, needsDeltas: { hunger: { delta: -5, reason: '' } } } as Chips);
    const b = reprocessButton();
    expect(b).toBeDefined();
    act(() => b!.dispatchEvent(new MouseEvent('click', { bubbles: true })));
    expect(onReprocess).toHaveBeenCalledTimes(1);
  });

  it('G2 guard: no button when needsReprocessable is absent (resolver null)', () => {
    render({ needsDeltas: { hunger: { delta: -5, reason: '' } } } as Chips);
    expect(reprocessButton()).toBeUndefined();
  });

  it('G4 guard: does not re-derive the gate from enabledNeeds (folded from the PR)', () => {
    render({ enabledNeeds: ['hunger', 'energy'] } as unknown as Chips);
    expect(reprocessButton()).toBeUndefined();
  });

  it('G3 guard: no button on a non-last or busy message even when reprocessable', () => {
    render({ needsReprocessable: true } as Chips, false);
    expect(reprocessButton()).toBeUndefined();
    render({ needsReprocessable: true } as Chips, true, true);
    expect(reprocessButton()).toBeUndefined();
  });
});

// Issue 668: on a touch screen the reprocess pills end the top chip row instead
// of sitting on their own row right above the message icons.
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
