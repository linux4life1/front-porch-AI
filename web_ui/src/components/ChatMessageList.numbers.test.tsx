// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Each message shows its place in the whole chat, counting from #1 — the
// same number the desktop shows under the avatar and the receipt chips use.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement, createRef } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { ChatMessageList } from './ChatMessageList';
import type { Message } from './chatTypes';

let container: HTMLDivElement;
let root: Root;
const noop = vi.fn();

function renderList(messages: Message[]) {
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
        scrollRef: createRef<HTMLDivElement>(),
        sessionId: 's1',
      }),
    );
  });
}

const numbers = () =>
  Array.from(container.querySelectorAll('.msg-number')).map((n) => n.textContent);

describe('ChatMessageList message numbers', () => {
  beforeEach(() => {
    container = document.createElement('div');
    document.body.appendChild(container);
    root = createRoot(container);
  });
  afterEach(() => {
    act(() => root.unmount());
    container.remove();
  });

  it('counts from #1 at the place in the whole chat', () => {
    renderList([
      { index: 0, position: 40, text: 'Evening.', sender: 'Iris', isUser: false },
      { index: 1, position: 41, text: 'Pull up a chair.', sender: 'Sam', isUser: true },
    ]);
    expect(numbers()).toEqual(['#41', '#42']);
    expect(container.querySelectorAll('.msg-number.user')).toHaveLength(1);
  });

  it('falls back to the index when an older app sends no position', () => {
    renderList([
      { index: 0, text: 'Evening.', sender: 'Iris', isUser: false },
      { index: 1, text: 'Pull up a chair.', sender: 'Sam', isUser: true },
    ]);
    expect(numbers()).toEqual(['#1', '#2']);
  });
});
