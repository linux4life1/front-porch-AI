// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A reply's Realism chips and Needs chips are always two rows (PR 1b): Bond /
// Trust / mood / time on the first, the Needs deltas starting a new row. On a
// wide tablet bubble one wrapping row put Bond and Hunger side by side — the
// maintainer caught it in the sketch.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { ChipsRow } from './ChipsRow';

let container: HTMLDivElement;
let root: Root;

beforeEach(() => {
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
});
afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

describe('ChipsRow rows', () => {
  it('puts the Needs deltas on their own row, never beside Bond', () => {
    act(() => {
      root.render(
        createElement(ChipsRow, {
          chips: {
            bondDelta: 13,
            trustDelta: 1,
            emotionLabel: 'happy',
            timePassed: '5 min',
            needsDeltas: { hunger: -4, bladder: -4, energy: -2, social: 5 },
          },
          isLast: false,
          busy: false,
          onReprocess: vi.fn(),
          onRevert: vi.fn(),
        }),
      );
    });
    const rows = [...container.querySelectorAll('.chips-row')];
    expect(rows).toHaveLength(2);
    const [realism, needs] = rows;
    expect(realism.className).toContain('realism');
    expect(realism.textContent).toContain('Bond +13');
    expect(realism.textContent).toContain('Trust +1');
    expect(realism.textContent).toContain('happy');
    expect(realism.textContent).toContain('5 min');
    expect(realism.textContent).not.toContain('Hunger');

    expect(needs.className).toContain('needs');
    expect(needs.textContent).toContain('Hunger -4');
    expect(needs.textContent).toContain('Bladder -4');
    expect(needs.textContent).not.toContain('Bond');
  });
});
