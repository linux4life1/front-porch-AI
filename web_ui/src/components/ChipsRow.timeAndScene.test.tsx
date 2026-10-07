// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A needs chip whose reason carries both the time and the scene ("1 hr 20 min
// · lunch", built by the engine when time and the scene both moved a bar)
// shows that reason whole: on hover and when tapped, never cut at the dot.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { ChipsRow } from './ChipsRow';

const REASON = '1 hr 20 min · lunch: hunger +55, bladder -12';

let container: HTMLDivElement;
let root: Root;

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  act(() =>
    root.render(
      createElement(ChipsRow, {
        chips: {
          needsDeltas: {
            hunger: { delta: 55, reason: REASON },
            bladder: { delta: -12, reason: '1 hr 20 min' },
          },
        },
        isLast: false,
        busy: false,
        onReprocess: () => {},
        onRevert: () => {},
      }),
    ),
  );
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

function chip(label: string): HTMLElement {
  const found = [...container.querySelectorAll<HTMLElement>('.chips-row.needs .chip')].find(
    (c) => c.textContent?.startsWith(label),
  );
  if (!found) throw new Error(`no needs chip ${label}`);
  return found;
}

describe('ChipsRow time-and-scene reason', () => {
  it('keeps the whole reason on hover', () => {
    expect(chip('Hunger +55').title).toBe(REASON);
    expect(chip('Bladder -12').title).toBe('1 hr 20 min');
  });

  it('reveals the whole reason on tap', () => {
    act(() => chip('Hunger +55').click());
    expect(container.querySelector('.chip-reason')?.textContent).toBe(REASON);
  });
});
