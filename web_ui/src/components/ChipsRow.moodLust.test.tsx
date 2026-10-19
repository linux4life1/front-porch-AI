// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Mood and Lust chips under a reply say why, like Bond and Trust: hover
// shows the reason as the title, a tap opens it inline. Desktop twin:
// message_bubble.realism.dart.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { ChipsRow } from './ChipsRow';
import { type Chips } from './chatTypes';

let container: HTMLDivElement;
let root: Root;

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

function render(chips: Chips) {
  act(() =>
    root.render(
      createElement(ChipsRow, { chips, isLast: false, busy: false, onReprocess: () => {}, onRevert: () => {} }),
    ),
  );
}

function chip(label: string): HTMLElement {
  const found = [...container.querySelectorAll<HTMLElement>('.chips-row.realism .chip')].find(
    (c) => c.textContent?.startsWith(label),
  );
  if (!found) throw new Error(`no realism chip ${label}`);
  return found;
}

describe('ChipsRow mood and lust reasons', () => {
  it('Lust shows why it moved on hover and on tap', () => {
    render({ arousalDelta: 8, arousalReason: 'The way they said my name.' });
    expect(chip('Lust +8').title).toBe('The way they said my name.');
    act(() => chip('Lust +8').click());
    expect(container.querySelector('.chip-reason')?.textContent).toBe('The way they said my name.');
  });

  it('Mood shows the cause, then what they came in carrying', () => {
    render({ emotionLabel: 'love', emotionCause: 'he stayed', moodStanding: 'tired after a long shift' });
    expect(chip('love').title).toBe('Because he stayed\nCame in tired after a long shift');
  });

  it('a chip with no reason has no hover box and does not open', () => {
    render({ emotionLabel: 'calm', arousalDelta: -3 });
    expect(chip('calm').title).toBe('');
    expect(chip('Lust -3').getAttribute('role')).toBeNull();
  });
});
