// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { ChipsRow } from './ChipsRow';

let container: HTMLDivElement;
let root: Root;

function render(
  needsReprocessable?: boolean,
  extra?: { enabledNeeds?: string[] },
) {
  act(() => {
    root.render(
      createElement(ChipsRow, {
        chips: {
          emotionLabel: 'calm',
          needsReprocessable,
          enabledNeeds: extra?.enabledNeeds,
        },
        isLast: true,
        busy: false,
        onReprocess: () => {},
        onRevert: () => {},
      }),
    );
  });
}

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

describe('ChipsRow reprocess gate', () => {
  it('has no Reprocess button without needsReprocessable', () => {
    render(undefined);
    expect(container.querySelector('.btn-reprocess')).toBeNull();
  });

  it('does not re-derive the gate from enabledNeeds', () => {
    render(undefined, { enabledNeeds: ['hunger', 'energy'] });
    expect(container.querySelector('.btn-reprocess')).toBeNull();
  });

  it('shows Reprocess when needsReprocessable is set', () => {
    render(true);
    expect(container.querySelector('.btn-reprocess')).not.toBeNull();
    expect(container.textContent).toContain('Manual Reprocess');
  });
});
