// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Draft persistence through the mounted composer: type, let the debounce
// write, unmount (leaving /chat), remount — the line is back in the box.
// The route rule is the desktop store's: a chat that has sent a message
// keys by session, a never-sent one keys by owner.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { ChatComposer } from './ChatComposer';

let container: HTMLDivElement;
let root: Root;

type Box = { sessionKey: string; ownerKey: string; fresh: boolean };

function render(box: Box) {
  act(() => {
    root.render(
      createElement(ChatComposer, {
        onSend: vi.fn(),
        onStop: vi.fn(),
        isGenerating: false,
        canMic: false,
        apiReady: true,
        draftBox: box,
      }),
    );
  });
}

function area(): HTMLTextAreaElement {
  return container.querySelector('textarea')!;
}

function type(text: string) {
  const ta = area();
  const setter = Object.getOwnPropertyDescriptor(
    HTMLTextAreaElement.prototype,
    'value',
  )!.set!;
  act(() => {
    setter.call(ta, text);
    ta.dispatchEvent(new Event('input', { bubbles: true }));
  });
}

function advance(ms: number) {
  act(() => {
    vi.advanceTimersByTime(ms);
  });
}

describe('ChatComposer draft persistence', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    localStorage.clear();
    container = document.createElement('div');
    document.body.appendChild(container);
    root = createRoot(container);
  });

  afterEach(() => {
    act(() => root.unmount());
    container.remove();
    vi.useRealTimers();
  });

  it('writes a typed line to the session key after the debounce', () => {
    const box: Box = {
      sessionKey: 'fpai.draft.s.42',
      ownerKey: 'fpai.draft.o.nina',
      fresh: false,
    };
    render(box);
    type('half a thought');
    advance(600);
    expect(localStorage.getItem('fpai.draft.s.42')).toBe('half a thought');
    expect(localStorage.getItem('fpai.draft.o.nina')).toBeNull();
  });

  it('restores the line into a freshly mounted box', () => {
    const box: Box = {
      sessionKey: 'fpai.draft.s.42',
      ownerKey: 'fpai.draft.o.nina',
      fresh: false,
    };
    render(box);
    type('come back to me');
    advance(600);
    act(() => root.unmount());
    root = createRoot(container);
    render(box);
    expect(area().value).toBe('come back to me');
  });

  it('routes a never-sent chat to the owner mailbox', () => {
    const box: Box = {
      sessionKey: 'fpai.draft.s.fresh-1',
      ownerKey: 'fpai.draft.o.nina',
      fresh: true,
    };
    render(box);
    type('a first hello');
    advance(600);
    expect(localStorage.getItem('fpai.draft.o.nina')).toBe('a first hello');
    expect(localStorage.getItem('fpai.draft.s.fresh-1')).toBeNull();
  });

  it('flushes on unmount so the debounce window cannot eat the line', () => {
    const box: Box = {
      sessionKey: 'fpai.draft.s.42',
      ownerKey: 'fpai.draft.o.nina',
      fresh: false,
    };
    render(box);
    type('typed then left');
    act(() => root.unmount());
    expect(localStorage.getItem('fpai.draft.s.42')).toBe('typed then left');
    root = createRoot(container); // so afterEach's unmount is a no-op no-op
  });

  it('a cleared box clears both keys — a sent line never returns', () => {
    const box: Box = {
      sessionKey: 'fpai.draft.s.42',
      ownerKey: 'fpai.draft.o.nina',
      fresh: false,
    };
    localStorage.setItem('fpai.draft.o.nina', 'stale mailbox line');
    render(box);
    type('about to send');
    advance(600);
    type(''); // sendComposerMessage's twin: the box clears after the send
    advance(600);
    expect(localStorage.getItem('fpai.draft.s.42')).toBeNull();
    expect(localStorage.getItem('fpai.draft.o.nina')).toBeNull();
  });
});
