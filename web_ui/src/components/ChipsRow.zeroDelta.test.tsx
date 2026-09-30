// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { ChipsRow } from './ChipsRow';

let container: HTMLDivElement;
let root: Root;

describe('ChipsRow recorded zero deltas', () => {
  beforeEach(() => {
    container = document.createElement('div');
    document.body.appendChild(container);
    root = createRoot(container);
  });
  afterEach(() => {
    act(() => root.unmount());
    container.remove();
  });

  it('shows Bond +0 and Trust +0 when the judge recorded them', () => {
    act(() => {
      root.render(
        createElement(ChipsRow, {
          chips: { bondDelta: 0, trustDelta: 0, emotionLabel: 'amusement' },
          isLast: false,
          busy: false,
          onReprocess: vi.fn(),
          onRevert: vi.fn(),
        }),
      );
    });
    expect(container.textContent).toContain('Bond unchanged');
    expect(container.textContent).toContain('Trust unchanged');
  });

  it('does not invent a bond chip from mood alone', () => {
    act(() => {
      root.render(
        createElement(ChipsRow, {
          chips: { emotionLabel: 'amusement' },
          isLast: false,
          busy: false,
          onReprocess: vi.fn(),
          onRevert: vi.fn(),
        }),
      );
    });
    expect(container.textContent).not.toContain('Bond');
    expect(container.textContent).not.toContain('Trust');
  });
});
