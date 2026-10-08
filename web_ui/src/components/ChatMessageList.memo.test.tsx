// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Streamed tokens re-render the list many times a second. Re-rendering every
// transcript row per token is what froze iPad Safari on long chats, so the
// rows must sit out frames where only the streaming tail changed.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement, createRef } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { Message } from './chatTypes';

let actionRenders = 0;
vi.mock('./MessageActions', () => ({
  MessageActions: () => {
    actionRenders += 1;
    return null;
  },
}));

const { ChatMessageList } = await import('./ChatMessageList');

let container: HTMLDivElement;
let root: Root;
const noop = () => {};
const scrollRef = createRef<HTMLDivElement>();
const messages: Message[] = Array.from({ length: 10 }, (_, i) => ({
  index: i,
  text: `line ${i}`,
  sender: i % 2 ? 'Iris' : 'You',
  isUser: i % 2 === 0,
}));
const castById = new Map();

function renderList(streaming: string) {
  act(() => {
    root.render(
      createElement(ChatMessageList, {
        messages,
        castById,
        multiCast: false,
        lastIndex: messages.length - 1,
        busy: true,
        canSpeak: false,
        onBeginEdit: noop,
        onSwipe: noop,
        onRegenerate: noop,
        onContinue: noop,
        onFork: noop,
        onDelete: noop,
        onReprocess: noop,
        onRevert: noop,
        streaming,
        genStatus: null,
        scrollRef,
        sessionId: 's1',
      }),
    );
  });
}

describe('ChatMessageList streaming', () => {
  beforeEach(() => {
    actionRenders = 0;
    container = document.createElement('div');
    document.body.appendChild(container);
    root = createRoot(container);
  });

  afterEach(() => {
    act(() => root.unmount());
    container.remove();
  });

  it('does not re-render transcript rows for each streamed token', () => {
    renderList('');
    const afterOpen = actionRenders;
    expect(afterOpen).toBeGreaterThanOrEqual(messages.length);

    renderList('Th');
    renderList('The ');
    renderList('The porch');

    expect(actionRenders).toBe(afterOpen);
    expect(container.querySelector('.bubble.streaming')?.textContent).toContain('The porch');
  });
});
