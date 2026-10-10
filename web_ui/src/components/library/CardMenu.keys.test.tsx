// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The popover menu's arrow keys move between its items only while focus is
// in the menu. A field outside (the chat composer, a search box) keeps its own
// arrow keys while a menu is open. Red proof: listening for arrows on window
// fails the first case (the key is swallowed and focus jumps into the menu).

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { CardMenu } from './CardMenu';

let container: HTMLDivElement;
let root: Root;
let outside: HTMLInputElement;

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  outside = document.createElement('input');
  document.body.appendChild(outside);
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  act(() => {
    root.render(
      createElement(CardMenu, {
        menu: {
          x: 0,
          y: 0,
          items: [
            { label: 'One', onClick: () => {} },
            { label: 'Two', onClick: () => {} },
          ],
        },
        onClose: () => {},
      }),
    );
  });
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
  outside.remove();
});

const items = () => [...container.querySelectorAll<HTMLButtonElement>('[role="menuitem"]')];

function press(target: Element, key: string): KeyboardEvent {
  const e = new KeyboardEvent('keydown', { key, bubbles: true, cancelable: true });
  act(() => {
    target.dispatchEvent(e);
  });
  return e;
}

describe('CardMenu arrow keys', () => {
  it('leave a field outside the menu alone', () => {
    outside.focus();
    const e = press(outside, 'ArrowDown');
    expect(e.defaultPrevented).toBe(false);
    expect(document.activeElement).toBe(outside);
  });

  it('move between the items while focus is in the menu', () => {
    expect(document.activeElement).toBe(items()[0]);
    const e = press(items()[0], 'ArrowDown');
    expect(e.defaultPrevented).toBe(true);
    expect(document.activeElement).toBe(items()[1]);
    press(items()[1], 'ArrowDown');
    expect(document.activeElement).toBe(items()[0]);
    press(items()[0], 'ArrowUp');
    expect(document.activeElement).toBe(items()[1]);
  });
});
