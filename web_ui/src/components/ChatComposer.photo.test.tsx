// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A photo the browser can't decode used to be dropped and the text sent on
// its own. The user must get both back with a reason instead. (jsdom has no
// image decoder, so preparing the photo genuinely fails here.)

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

describe('ChatComposer photo failure', () => {
  beforeEach(async () => {
    vi.spyOn(console, 'warn').mockImplementation(() => {});
    URL.createObjectURL = () => 'blob:preview';
    URL.revokeObjectURL = () => {};
    onSend.mockClear();
    container = document.createElement('div');
    document.body.appendChild(container);
    root = createRoot(container);
    await act(async () => {
      root.render(
        createElement(ChatComposer, { onSend, onStop: () => {}, isGenerating: false, canMic: false }),
      );
    });
  });

  afterEach(() => {
    act(() => root.unmount());
    container.remove();
    vi.restoreAllMocks();
  });

  it('keeps the text and photo and explains, instead of sending text alone', async () => {
    const input = container.querySelector('input[type="file"]') as HTMLInputElement;
    const file = new File([new Uint8Array([1, 2, 3])], 'porch.heic', { type: 'image/heic' });
    Object.defineProperty(input, 'files', { value: [file], configurable: true });
    await act(async () => input.dispatchEvent(new Event('change', { bubbles: true })));

    const ta = container.querySelector('textarea') as HTMLTextAreaElement;
    await act(async () => typeInto(ta, 'look at this'));
    const send = [...container.querySelectorAll('button')].find((b) => b.textContent === 'Send')!;
    await act(async () => send.click());
    await act(async () => {});

    expect(onSend).not.toHaveBeenCalled();
    expect(container.querySelector('[role="alert"]')?.textContent).toContain("couldn't be read");
    expect((container.querySelector('textarea') as HTMLTextAreaElement).value).toBe('look at this');
    expect(container.querySelector('.composer-photo-chip')).not.toBeNull();
  });
});
