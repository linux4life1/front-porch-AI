// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// On a Japanese / Chinese / Korean keyboard, Enter first confirms the
// candidate word. That Enter must not send a half-typed message.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { ChatComposer } from './ChatComposer';

let container: HTMLDivElement;
let root: Root;
const onSend = vi.fn();

function typeInto(el: HTMLTextAreaElement, value: string) {
  const setter = Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value')!.set!;
  setter.call(el, value);
  el.dispatchEvent(new Event('input', { bubbles: true }));
}

function pressEnter(el: HTMLTextAreaElement, init: KeyboardEventInit & { keyCode?: number }) {
  const ev = new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true, ...init });
  if (init.keyCode !== undefined) Object.defineProperty(ev, 'keyCode', { value: init.keyCode });
  el.dispatchEvent(ev);
}

describe('ChatComposer IME', () => {
  beforeEach(async () => {
    onSend.mockClear();
    container = document.createElement('div');
    document.body.appendChild(container);
    root = createRoot(container);
    await act(async () => {
      root.render(
        createElement(ChatComposer, {
          onSend,
          onStop: () => {},
          isGenerating: false,
          canMic: false,
        }),
      );
    });
  });

  afterEach(() => {
    act(() => root.unmount());
    container.remove();
  });

  it('does not send on the Enter that confirms a candidate', async () => {
    const ta = container.querySelector('textarea') as HTMLTextAreaElement;
    await act(async () => typeInto(ta, 'こんにち'));
    await act(async () => pressEnter(ta, { isComposing: true }));
    await act(async () => pressEnter(ta, { keyCode: 229 }));
    expect(onSend).not.toHaveBeenCalled();

    await act(async () => pressEnter(ta, {}));
    expect(onSend).toHaveBeenCalledWith('こんにち');
  });
});
