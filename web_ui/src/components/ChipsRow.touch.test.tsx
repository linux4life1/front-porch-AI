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
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
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

// The tap area grows; the drawing does not. A pill or icon button that gets
// `min-height: 44px` is DRAWN 44px (Reset/Lock became square boxes, One-Shot's
// pills became circles, the cast chip grew and pushed the + onto its own
// line). The coarse-pointer block must keep the control's mouse box and put
// the 44px area on a transparent ::after instead.
describe('touch tap areas keep the mouse drawing (PR 1b)', () => {
  const css = readFileSync(join(__dirname, '..', 'styles', 'touch.css'), 'utf8');
  const coarse = /@media\s*\(pointer:\s*coarse\)\s*\{([\s\S]*)\}\s*$/.exec(css)?.[1] ?? '';

  it('finds the coarse-pointer block', () => {
    expect(coarse.length).toBeGreaterThan(200);
  });

  it('a pill is not drawn at 44px; its hit area is', () => {
    // No min-height on the drawn pill itself.
    expect(coarse).not.toMatch(/\.sidebar-reset-pill[^{]*\{[^}]*min-height/);
    expect(coarse).not.toMatch(/\.sidebar-lock-pill[^{]*\{[^}]*min-height/);
    // The 44px area is the transparent pseudo-element.
    expect(coarse).toMatch(/\.sidebar-reset-pill::after[^{]*\{[^}]*height:\s*max\(100%,\s*44px\)/);
    expect(coarse).toMatch(/\.sidebar-reset-pill::after[^{]*\{[^}]*width:\s*max\(100%,\s*44px\)/);
  });

  it('an icon button and the + keep their mouse size', () => {
    expect(coarse).not.toMatch(/\.icon-btn[^{]*\{[^}]*min-(width|height)/);
    expect(coarse).not.toMatch(/\.cast-add[^{]*\{[^}]*min-(width|height)/);
    expect(coarse).toMatch(/\.icon-btn::after[^{]*\{[^}]*height:\s*max\(100%,\s*44px\)/);
  });

  it('a card header row keeps its height so the padlock stays on the title line', () => {
    expect(coarse).not.toMatch(/\.tool-section summary[^{]*\{[^}]*min-height/);
    expect(coarse).toMatch(/\.tool-section summary::after[^{]*\{[^}]*height:\s*max\(100%,\s*44px\)/);
  });
});
