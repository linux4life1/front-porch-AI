// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// While a reply waits, the line under the chat says what it waits for, in
// the desktop's words: a pass of the chat, or what has the engine (the speed
// test in the preset editor), which the server sends already in words.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement, createRef } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { ChatMessageList, type GenStatus } from './ChatMessageList';

let container: HTMLDivElement;
let root: Root;
const noop = vi.fn();

function waitingFor(busyWith: string | null) {
  const genStatus: GenStatus = {
    phase: 'prefill',
    elapsed: 12,
    busyWith,
    queued: 0,
    promptCur: null,
    promptTotal: null,
    promptDone: false,
    estFraction: null,
    genCur: null,
    genTotal: null,
  };
  act(() => {
    root.render(
      createElement(ChatMessageList, {
        messages: [],
        castById: new Map(),
        multiCast: false,
        lastIndex: -1,
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
        streaming: '',
        followStreamingReplies: true,
        genStatus,
        scrollRef: createRef<HTMLDivElement>(),
        sessionId: 's1',
      }),
    );
  });
  return container.querySelector('.gen-status')?.textContent ?? '';
}

describe('ChatMessageList waiting status', () => {
  beforeEach(() => {
    container = document.createElement('div');
    document.body.appendChild(container);
    root = createRoot(container);
  });
  afterEach(() => {
    act(() => root.unmount());
    container.remove();
  });

  it('names what has the engine when the server sends it in words', () => {
    expect(waitingFor('the speed test')).toBe(
      'Waiting — the speed test is using the model…',
    );
  });

  it('still names the passes of the chat', () => {
    expect(waitingFor('journal')).toBe('Waiting — journal pass is using the model…');
    expect(waitingFor('growth')).toBe('Waiting — growth pass is using the model…');
  });
});
