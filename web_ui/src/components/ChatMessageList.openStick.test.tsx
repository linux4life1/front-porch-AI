// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement, createRef, type RefObject } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { ChatMessageList } from './ChatMessageList';
import type { Message } from './chatTypes';

let container: HTMLDivElement;
let root: Root;
const noop = vi.fn();

function message(partial: Partial<Message> & Pick<Message, 'index' | 'text'>): Message {
  return {
    sender: 'Iris',
    isUser: false,
    ...partial,
  };
}

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
        genStatus: null,
        scrollRef,
        sessionId: 's1',
      }),
    );
  });
}

function metrics(el: HTMLDivElement, scrollHeight: number, clientHeight: number) {
  Object.defineProperty(el, 'scrollHeight', {
    configurable: true,
    get: () => scrollHeight,
  });
  Object.defineProperty(el, 'clientHeight', {
    configurable: true,
    get: () => clientHeight,
  });
  el.scrollTo = (opts?: ScrollToOptions) => {
    if (opts && typeof opts.top === 'number') el.scrollTop = opts.top;
  };
}

describe('ChatMessageList open stick', () => {
  beforeEach(() => {
    container = document.createElement('div');
    document.body.appendChild(container);
    root = createRoot(container);
  });
  afterEach(() => {
    act(() => root.unmount());
    container.remove();
  });

  it('re-pins to the bottom when a chat image loads after open', () => {
    const scrollRef = createRef<HTMLDivElement>();
    renderList(
      [
        message({ index: 0, text: 'older', sender: 'You', isUser: true }),
        message({ index: 1, text: 'look', image: 'scene.png' }),
      ],
      scrollRef,
    );
    const el = container.querySelector('.chat-messages') as HTMLDivElement;
    metrics(el, 2400, 700);
    el.scrollTop = 0;
    const img = container.querySelector('img.chat-image') as HTMLImageElement;
    act(() => {
      img.dispatchEvent(new Event('load'));
    });
    expect(el.scrollTop).toBe(2400);
  });

  it('does not yank the reader back down after they scroll away', () => {
    const scrollRef = createRef<HTMLDivElement>();
    renderList(
      [message({ index: 0, text: 'look', image: 'scene.png' })],
      scrollRef,
    );
    const el = container.querySelector('.chat-messages') as HTMLDivElement;
    metrics(el, 2400, 700);
    el.scrollTop = 100;
    act(() => {
      el.dispatchEvent(new Event('scroll', { bubbles: true }));
    });
    const img = container.querySelector('img.chat-image') as HTMLImageElement;
    act(() => {
      img.dispatchEvent(new Event('load'));
    });
    expect(el.scrollTop).toBe(100);
  });
});
