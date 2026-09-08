// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement, createRef } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { ChatMessageList } from './ChatMessageList';

let container: HTMLDivElement;
let root: Root;
const noop = vi.fn();

function renderStreaming(streaming: string) {
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
        streaming,
        genStatus: null,
        scrollRef: createRef<HTMLDivElement>(),
      }),
    );
  });
}

describe('ChatMessageList live think', () => {
  beforeEach(() => {
    container = document.createElement('div');
    document.body.appendChild(container);
    root = createRoot(container);
  });
  afterEach(() => {
    act(() => root.unmount());
    container.remove();
  });

  it('keeps streaming think collapsed until the details is opened', () => {
    renderStreaming('<think>secret live plan</think>\nhello there');
    const details = container.querySelector(
      'details.thinking',
    ) as HTMLDetailsElement | null;
    expect(details).not.toBeNull();
    expect(details!.open).toBe(false);
    expect(details!.querySelector('.thinking-body')?.textContent).toContain(
      'secret live plan',
    );
  });
});
