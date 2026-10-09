// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The regenerate dialog confirms from the keyboard: Ctrl/⌘+Enter, main or
// numpad, regenerates with the note and lookup as set. Plain Enter is left
// to the note for a new line.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { MessageActions } from './MessageActions';
import { type Message } from './chatTypes';

let container: HTMLDivElement;
let root: Root;

const bot: Message = {
  index: 1,
  text: 'He stands at the window.',
  sender: 'Mara',
  isUser: false,
  swipeIndex: 0,
  swipeCount: 1,
};

function open(lookupWeb = false) {
  const onRegenerate = vi.fn();
  act(() => {
    root.render(
      createElement(MessageActions, {
        m: bot,
        isLast: true,
        busy: false,
        canSpeak: false,
        onSwipe: vi.fn(),
        onRegenerate,
        lookupWeb,
        onContinue: vi.fn(),
        onFork: vi.fn(),
        onEdit: vi.fn(),
        onDelete: vi.fn(),
      }),
    );
  });
  act(() => {
    (container.querySelector('button[title="Regenerate"]') as HTMLButtonElement).click();
  });
  return onRegenerate;
}

function type(el: HTMLTextAreaElement | HTMLInputElement, value: string) {
  const proto =
    el instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
  act(() => {
    Object.getOwnPropertyDescriptor(proto, 'value')?.set?.call(el, value);
    el.dispatchEvent(new Event('input', { bubbles: true }));
  });
}

function press(el: Element, init: KeyboardEventInit) {
  const ev = new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true, ...init });
  act(() => {
    el.dispatchEvent(ev);
  });
  return ev;
}

const field = () =>
  container.querySelector('textarea[data-testid="regen-critique-field"]') as HTMLTextAreaElement | null;

describe('MessageActions regen keyboard confirm', () => {
  beforeEach(() => {
    container = document.createElement('div');
    document.body.appendChild(container);
    root = createRoot(container);
  });
  afterEach(() => {
    act(() => root.unmount());
    container.remove();
  });

  for (const [label, init] of [
    ['Ctrl+Enter', { ctrlKey: true, code: 'Enter' }],
    ['⌘+Enter', { metaKey: true, code: 'Enter' }],
    ['Ctrl+numpad Enter', { ctrlKey: true, code: 'NumpadEnter' }],
    ['⌘+numpad Enter', { metaKey: true, code: 'NumpadEnter' }],
  ] as const) {
    it(`${label} regenerates with the note`, () => {
      const onRegenerate = open();
      type(field()!, 'less lecture');
      const ev = press(field()!, init);
      expect(onRegenerate).toHaveBeenCalledWith('less lecture');
      expect(ev.defaultPrevented).toBe(true);
      expect(field()).toBeNull();
    });
  }

  for (const code of ['Enter', 'NumpadEnter']) {
    it(`plain ${code} is left to the note`, () => {
      const onRegenerate = open();
      type(field()!, 'first line');
      const ev = press(field()!, { code });
      expect(onRegenerate).not.toHaveBeenCalled();
      expect(ev.defaultPrevented).toBe(false);
      expect(field()).not.toBeNull();
    });
  }

  it('the chord carries the lookup words too', () => {
    const onRegenerate = open(true);
    type(field()!, 'wrong year');
    const query = container.querySelector('[data-testid="regen-lookup-query"]') as HTMLInputElement;
    type(query, 'Treaty of Ghent');
    press(query, { ctrlKey: true });
    expect(onRegenerate).toHaveBeenCalledWith('wrong year', { source: 'web', query: 'Treaty of Ghent' });
  });

  it('shows the chord next to Regenerate', () => {
    open();
    expect(container.querySelector('.regen-critique-actions')?.textContent).toContain('⌘/Ctrl+Enter');
  });
});
