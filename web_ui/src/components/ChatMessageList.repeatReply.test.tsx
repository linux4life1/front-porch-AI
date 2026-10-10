// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A reply that repeats the last one word for word, arriving together with
// the line before it, is new rows at the bottom, not older history at the
// top. Read as older history, it slid the mounted rows down and the first
// lines of a short chat left the phone with nothing to scroll back to.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement, createRef } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { ChatMessageList } from './ChatMessageList';
import type { Message } from './chatTypes';

let container: HTMLDivElement;
let root: Root;
const noop = vi.fn();
const scrollRef = createRef<HTMLDivElement>();

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
        scrollRef,
        sessionId: 's1',
      }),
    );
  });
}

const reply = 'REPLY the same, word for word.';
const row = (index: number, text: string, isUser: boolean): Message => ({
  index,
  text,
  sender: isUser ? 'You' : 'Iris',
  isUser,
});

describe('ChatMessageList repeated reply', () => {
  beforeEach(() => {
    container = document.createElement('div');
    document.body.appendChild(container);
    root = createRoot(container);
  });
  afterEach(() => {
    act(() => root.unmount());
    container.remove();
  });

  it('keeps the first lines of a short chat when a repeated reply lands with its prompt', () => {
    const first = [row(0, 'GREETING welcome', false), row(1, 'FIRSTLINE swing', true), row(2, reply, false)];
    renderList(first);
    expect(container.textContent).toContain('GREETING');

    renderList([...first, row(3, 'SECONDLINE more', true), row(4, reply, false)]);

    const text = container.textContent ?? '';
    expect(text).toContain('GREETING');
    expect(text).toContain('FIRSTLINE');
    expect(text).toContain('SECONDLINE');
    expect(text.match(/REPLY/g) ?? []).toHaveLength(2);
  });
});
