// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A greyed control is really disabled: no keyboard or pointer input changes
// it, it is not in the tab order, and nothing is drawn over it.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { GreyedOut } from './GreyedOut';

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

describe('GreyedOut', () => {
  it('disables native controls, takes custom ones out of the tab order, and covers nothing', () => {
    const onChange = vi.fn();
    const onClick = vi.fn();
    act(() =>
      root.render(
        createElement(
          GreyedOut,
          { tooltip: 'Set per group.' },
          createElement('input', { defaultValue: 'a', onChange }),
          createElement('select', { defaultValue: 'x' }, createElement('option', { value: 'x' }, 'x')),
          createElement('button', { onClick }, 'Go'),
          createElement('div', { role: 'slider', tabIndex: 0, onClick }, 'custom'),
        ),
      ),
    );
    for (const sel of ['input', 'select', 'button']) {
      expect(container.querySelector(sel)!.matches(':disabled'), `${sel} is disabled`).toBe(true);
    }
    const custom = container.querySelector('[role="slider"]') as HTMLElement;
    expect(custom.getAttribute('tabindex')).toBe('-1');
    expect(custom.getAttribute('aria-disabled')).toBe('true');
    // Nothing is laid over the controls.
    for (const el of Array.from(container.querySelectorAll('*'))) {
      expect((el as HTMLElement).style.pointerEvents).not.toBe('none');
    }
    // Keyboard and pointer input never reach the control.
    const input = container.querySelector('input') as HTMLInputElement;
    act(() => {
      input.dispatchEvent(new KeyboardEvent('keydown', { key: 'z', bubbles: true, cancelable: true }));
      input.dispatchEvent(new Event('input', { bubbles: true }));
      custom.click();
      custom.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));
    });
    expect(onChange).not.toHaveBeenCalled();
    expect(onClick).not.toHaveBeenCalled();
    expect(input.value).toBe('a');
    expect(container.querySelector('.greyed-out')!.getAttribute('title')).toBe('Set per group.');
  });
});
