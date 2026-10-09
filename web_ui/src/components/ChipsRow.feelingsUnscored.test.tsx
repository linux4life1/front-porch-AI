// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Phone twin of test/ui/chat_components/feelings_unscored_chip_test.dart: a
// reply whose bond/trust judge could not be read shows one "not scored" chip,
// never "Bond unchanged". A scored zero still says "unchanged".

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
        isLast: true,
        busy: false,
        onReprocess: vi.fn(),
        onRevert: vi.fn(),
      }),
    );
  });
}

describe('ChipsRow feelings not scored', () => {
  beforeEach(() => {
    container = document.createElement('div');
    document.body.appendChild(container);
    root = createRoot(container);
  });
  afterEach(() => {
    act(() => root.unmount());
    container.remove();
  });

  it('shows one "not scored" chip and no "unchanged" chips', () => {
    render({ feelingsUnscored: true, emotionLabel: 'amusement', needsReprocessable: true });
    expect(container.textContent).toContain('Feelings not scored this time');
    expect(container.textContent).not.toContain('Bond');
    expect(container.textContent).not.toContain('Trust');
    expect(container.textContent).toContain('Manual Reprocess');
  });

  it('a scored zero still says unchanged', () => {
    render({ bondDelta: 0, trustDelta: 0 });
    expect(container.textContent).toContain('Bond unchanged');
    expect(container.textContent).toContain('Trust unchanged');
    expect(container.textContent).not.toContain('not scored');
  });
});
