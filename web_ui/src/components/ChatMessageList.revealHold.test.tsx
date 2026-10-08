// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Older rows mounting at the top must push the reader down by exactly
// their own height. Growth since the last render (a Thought opened, an
// image decoded) is not part of that and must not throw the reader down.
// A tap that opens a Thought ends the open-time stick to the bottom.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement, createRef, type RefObject } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { ChatMessageList } from './ChatMessageList';
import type { Message } from './chatTypes';

let container: HTMLDivElement;
let root: Root;
const noop = vi.fn();

function renderList(messages: Message[], scrollRef: RefObject<HTMLDivElement | null>) {
  act(() => {
    root.render(
      createElement(ChatMessageList, {
        messages,
        castById: new Map(),
        multiCast: false,
        lastIndex: messages.length - 1,
        busy: false,
        canSpeak: false,
        onBeginEdit: noop,
        onSwipe: noop,
        onRegenerate: noop,
        onContinue: noop,
        onFork: noop,
        onDelete: noop,
        onReprocess: noop,
        onRevert: noop,
        streaming: '',
        followStreamingReplies: true,
        genStatus: null,
        scrollRef,
        sessionId: 's1',
      }),
    );
  });
}

describe('ChatMessageList reveal hold', () => {
  beforeEach(() => {
    container = document.createElement('div');
    document.body.appendChild(container);
    root = createRoot(container);
  });
  afterEach(() => {
    act(() => root.unmount());
    container.remove();
  });

  it('a Thought opened before the reveal does not add to the hold', () => {
    const rowHeight = 100;
    let opened = 0;
    const scrollRef = createRef<HTMLDivElement>();
    const messages: Message[] = Array.from({ length: 48 }, (_, i) => ({
      index: i,
      text: `ROW${i}`,
      sender: i % 2 ? 'Iris' : 'You',
      isUser: i % 2 === 0,
    }));
    renderList(messages, scrollRef);
    const el = container.querySelector('.chat-messages') as HTMLDivElement;
    const rows = () => (el.textContent?.match(/ROW\d+/g) ?? []).length;
    Object.defineProperty(el, 'scrollHeight', {
      configurable: true,
      get: () => rows() * rowHeight + opened,
    });
    Object.defineProperty(el, 'clientHeight', { configurable: true, get: () => 700 });
    el.scrollTo = (opts?: ScrollToOptions) => {
      if (opts && typeof opts.top === 'number') el.scrollTop = opts.top;
    };
    expect(rows()).toBe(24);
    // Re-render so the list records the measured height as its baseline.
    renderList([...messages], scrollRef);

    act(() => {
      el.scrollTop = 900;
      el.dispatchEvent(new Event('scroll'));
    });
    opened = 400;
    act(() => {
      el.scrollTop = 20;
      el.dispatchEvent(new Event('scroll'));
    });

    expect(rows()).toBe(48);
    expect(el.scrollTop).toBe(20 + 24 * rowHeight);
  });

  it('a tap in the transcript ends the open stick', () => {
    const scrollRef = createRef<HTMLDivElement>();
    const messages: Message[] = [
      { index: 0, text: 'look', sender: 'Iris', isUser: false, image: 'scene.png' },
    ];
    renderList(messages, scrollRef);
    const el = container.querySelector('.chat-messages') as HTMLDivElement;
    let height = 2400;
    Object.defineProperty(el, 'scrollHeight', { configurable: true, get: () => height });
    Object.defineProperty(el, 'clientHeight', { configurable: true, get: () => 700 });
    el.scrollTo = (opts?: ScrollToOptions) => {
      if (opts && typeof opts.top === 'number') el.scrollTop = opts.top;
    };
    el.scrollTop = 1700;
    const img = container.querySelector('img.chat-image') as HTMLImageElement;
    act(() => {
      img.dispatchEvent(new Event('pointerdown', { bubbles: true }));
    });
    height = 3000;
    act(() => {
      img.dispatchEvent(new Event('load'));
    });
    expect(el.scrollTop).toBe(1700);
  });
});
