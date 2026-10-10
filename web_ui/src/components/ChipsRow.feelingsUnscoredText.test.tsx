// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The "not scored" chip shows the text the desktop sends with the chip
// (kFeelingsUnscoredLabel / kFeelingsUnscoredTip), so the two surfaces read
// from one source. A server that sends no text still gets the old wording.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { ChipsRow } from './ChipsRow';
import type { Chips } from './chatTypes';

let container: HTMLDivElement;
let root: Root;

function render(chips: Chips) {
  act(() => {
    root.render(
      createElement(ChipsRow, {
        chips,
        isLast: false,
        busy: false,
        onReprocess: vi.fn(),
        onRevert: vi.fn(),
      }),
    );
  });
}

describe('ChipsRow "not scored" text', () => {
  beforeEach(() => {
    container = document.createElement('div');
    document.body.appendChild(container);
    root = createRoot(container);
  });
  afterEach(() => {
    act(() => root.unmount());
    container.remove();
  });

  it('uses the label and tip the desktop sends', () => {
    render({
      feelingsUnscored: true,
      feelingsUnscoredLabel: 'Desktop label',
      feelingsUnscoredTip: 'Desktop tip',
    });
    const chip = container.querySelector('.chip');
    expect(chip?.textContent).toContain('Desktop label');
    expect(chip?.getAttribute('title')).toBe('Desktop tip');
    expect(container.textContent).not.toContain('Feelings not scored');
  });

  it('falls back to its own copy when the server sends none', () => {
    render({ feelingsUnscored: true });
    const chip = container.querySelector('.chip');
    expect(chip?.textContent).toContain('Feelings not scored this time');
    expect(chip?.getAttribute('title')).toContain('Manual Reprocess');
  });
});
