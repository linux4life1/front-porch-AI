// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement, createRef, type RefObject } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { ChatMessageList, type GenStatus } from './ChatMessageList';
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

function renderList(
  messages: Message[],
  scrollRef: RefObject<HTMLDivElement | null>,
  extra?: { streaming?: string; followStreamingReplies?: boolean; genStatus?: GenStatus | null },
) {
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
        streaming: extra?.streaming ?? '',
        followStreamingReplies: extra?.followStreamingReplies ?? true,
        genStatus: extra?.genStatus ?? null,
        scrollRef,
        sessionId: 's1',
      }),
    );
  });
}

/** Records observers so a test can fire the one watching the message column. */
function installFakeResizeObserver() {
  const live: FakeResizeObserver[] = [];
  class FakeResizeObserver {
    cb: ResizeObserverCallback;
    constructor(cb: ResizeObserverCallback) {
      this.cb = cb;
      live.push(this);
    }
    observe() {}
    unobserve() {}
    disconnect() {
      const i = live.indexOf(this);
      if (i >= 0) live.splice(i, 1);
    }
  }
  vi.stubGlobal('ResizeObserver', FakeResizeObserver);
  return {
    fireLatest() {
      const obs = live[live.length - 1];
      obs?.cb([], obs as unknown as ResizeObserver);
    },
  };
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

  it('does not pin a follow-off reader when the reply lands', () => {
    const fake = installFakeResizeObserver();
    try {
      const scrollRef = createRef<HTMLDivElement>();
      const opened = [
        message({ index: 0, text: 'older', sender: 'You', isUser: true }),
        message({ index: 1, text: 'look' }),
      ];
      renderList(opened, scrollRef, { followStreamingReplies: false });
      const el = container.querySelector('.chat-messages') as HTMLDivElement;
      metrics(el, 2400, 700);
      el.scrollTop = 1700;
      renderList(opened, scrollRef, {
        streaming: 'still writing',
        followStreamingReplies: false,
      });
      let height = 2400;
      Object.defineProperty(el, 'scrollHeight', {
        configurable: true,
        get: () => height,
      });
      height = 3000;
      renderList(
        [...opened, message({ index: 2, text: 'landed' })],
        scrollRef,
        { followStreamingReplies: false },
      );
      el.scrollTop = 1700;
      act(() => {
        fake.fireLatest();
      });
      expect(el.scrollTop).toBe(1700);
    } finally {
      vi.unstubAllGlobals();
    }
  });
});

describe('ChatMessageList gen-status bubble', () => {
  beforeEach(() => {
    container = document.createElement('div');
    document.body.appendChild(container);
    root = createRoot(container);
  });
  afterEach(() => {
    act(() => root.unmount());
    container.remove();
    vi.unstubAllGlobals();
  });

  // The bubble mounts after the user's line pinned, outside the observed
  // message column, and hung under the composer for the whole prompt read.
  it('keeps a reader at the bottom when the Reading prompt bubble appears', () => {
    const watching: { cb: ResizeObserverCallback; targets: Element[] }[] = [];
    vi.stubGlobal(
      'ResizeObserver',
      class {
        entry: { cb: ResizeObserverCallback; targets: Element[] };
        constructor(cb: ResizeObserverCallback) {
          this.entry = { cb, targets: [] };
          watching.push(this.entry);
        }
        observe(t: Element) {
          this.entry.targets.push(t);
        }
        unobserve() {}
        disconnect() {
          const i = watching.indexOf(this.entry);
          if (i >= 0) watching.splice(i, 1);
        }
      },
    );
    const scrollRef = createRef<HTMLDivElement>();
    const sent = [
      message({ index: 0, text: 'hello' }),
      message({ index: 1, text: 'a long question', sender: 'You', isUser: true }),
    ];
    renderList(sent, scrollRef);
    const el = container.querySelector('.chat-messages') as HTMLDivElement;
    let height = 2400;
    metrics(el, 2400, 700);
    Object.defineProperty(el, 'scrollHeight', { configurable: true, get: () => height });
    el.scrollTop = 1700;

    const status: GenStatus = {
      phase: 'prefill',
      elapsed: 1,
      busyWith: null,
      queued: 0,
      promptCur: 2048,
      promptConfirmed: 0,
      promptTotal: 22124,
      promptDone: false,
      estFraction: 0.05,
      secondsLeft: null,
      genCur: null,
      genTotal: null,
    };
    renderList(sent, scrollRef, { genStatus: status });
    height = 2457;
    const bubble = container.querySelector('.gen-status') as HTMLElement;
    expect(bubble).not.toBeNull();
    act(() => {
      for (const w of watching.filter((x) => x.targets.includes(bubble))) {
        w.cb([], {} as ResizeObserver);
      }
    });
    expect(el.scrollTop).toBe(2457);
  });
});
