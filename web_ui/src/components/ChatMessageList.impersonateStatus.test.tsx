// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// While Impersonate writes the user's line into the composer, the status
// line says so in the desktop's words, not that a reply is on its way.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement, createRef } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { ChatMessageList, type GenStatus } from './ChatMessageList';

let container: HTMLDivElement;
let root: Root;
const noop = vi.fn();

function statusFor(phase: string, promptTotal: number | null) {
  const genStatus: GenStatus = {
    phase,
    elapsed: 4,
    busyWith: null,
    queued: 0,
    promptCur: promptTotal == null ? null : 900,
    promptTotal,
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

describe('ChatMessageList status while Impersonate runs', () => {
  beforeEach(() => {
    container = document.createElement('div');
    document.body.appendChild(container);
    root = createRoot(container);
  });
  afterEach(() => {
    act(() => root.unmount());
    container.remove();
  });

  it('says it is writing your reply', () => {
    expect(statusFor('impersonating', null)).toBe('Writing your reply…');
  });

  it('says so even while the engine reads the prompt', () => {
    expect(statusFor('impersonating', 2000)).toBe('Writing your reply…');
  });

  it('keeps the reply wording for a reply', () => {
    expect(statusFor('idle', null)).toBe('Processing prompt… (4s)');
  });
});
