// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Desktop (≥1024) message row layout (PR 1a): the avatar column carries the
// initial and the number, the bubble's top row carries the speaker's name and
// the per-message tools (speak / inspect / other words / fork / edit / delete),
// and the reply controls (regenerate / continue / swipe) sit in their own row
// under the bubble. The phone hover row must not have these desktop containers.
// Guards the isDesktop branch — every other list test renders at phone width.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement, createRef } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { ChatMessageList } from './ChatMessageList';
import type { CastMember } from './CastBar';
import type { Message } from './chatTypes';

let container: HTMLDivElement;
let root: Root;
const noop = vi.fn();

const mara: CastMember = {
  id: 'mara', dbId: 'mara', name: 'Mara', isHost: true, isLite: false,
  realismEnabled: true, emotion: null, isNext: false, hasAvatar: false, avatarUrl: '',
};

function renderList(messages: Message[], isDesktop: boolean) {
  act(() => {
    root.render(
      createElement(ChatMessageList, {
        messages,
        castById: new Map([['mara', mara]]),
        multiCast: false,
        isDesktop,
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

const reply: Message = {
  index: 1, position: 11, sender: 'Mara', text: 'Traffic on the bridge.',
  isUser: false, characterId: 'mara', hasContext: true,
};
const userLine: Message = {
  index: 0, position: 10, sender: 'You', text: 'What is the weather?', isUser: true,
};

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
});
afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

describe('desktop message row', () => {
  it('puts the initial + number in a left column, name + tools in the bubble, reply controls under it', () => {
    renderList([userLine, reply], true);
    const rows = container.querySelectorAll('.msg-row-desktop');
    expect(rows).toHaveLength(2);
    const row = rows[1] as HTMLElement;

    // Left avatar column: initial circle + the number under it.
    const col = row.querySelector('.msg-avatar-col') as HTMLElement;
    expect(col.querySelector('.msg-avatar')?.textContent).toBe('M');
    expect(col.querySelector('.msg-number')?.textContent).toBe('#12');

    // Bubble's top row: the speaker's name plus the tools, INSIDE the bubble.
    const bubble = row.querySelector('.bubble.ai') as HTMLElement;
    const top = bubble.querySelector('.bubble-actions') as HTMLElement;
    expect(top.querySelector('.msg-speaker')?.textContent).toContain('Mara');
    expect(top.querySelector('button[title="Inspect prompt"]')).not.toBeNull();
    expect(top.querySelector('button[title="Edit"]')).not.toBeNull();
    expect(top.querySelector('button[title="Delete"]')).not.toBeNull();

    // The newest reply's controls sit in their own row under the bubble, not
    // inside it.
    const under = row.querySelector('.msg-actions.reply-actions') as HTMLElement;
    expect(under).not.toBeNull();
    expect(bubble.contains(under)).toBe(false);
    expect(under.querySelector('button[title="Regenerate"]')).not.toBeNull();
    expect(under.querySelector('button[title="Continue"]')).not.toBeNull();
  });

  it('shows both containers even without hovering (no hover-hide on wide)', () => {
    renderList([userLine, reply], true);
    // These carry msg-actions but the wide layout never starts them at opacity:0.
    const rows = container.querySelectorAll('.msg-row-desktop');
    const row = rows[1] as HTMLElement;
    const top = row.querySelector('.bubble-actions') as HTMLElement;
    const under = row.querySelector('.reply-actions') as HTMLElement;
    expect(top).not.toBeNull();
    expect(under).not.toBeNull();
    // Regenerate/Continue render regardless of hover state (they're gated on
    // isLast/busy only).
    expect(under.querySelector('button[title="Regenerate"]')).not.toBeNull();
  });

  it('phone keeps the hover row and never renders the desktop containers', () => {
    renderList([userLine, reply], false);
    expect(container.querySelector('.msg-row-desktop')).toBeNull();
    expect(container.querySelector('.msg-avatar-col')).toBeNull();
    // The phone path keeps a single .msg-actions row that holds both the tools
    // and the reply controls — the shape every other list test pins.
    const rows = container.querySelectorAll('.msg-row');
    const actions = rows[1].querySelector('.msg-actions') as HTMLElement;
    expect(actions.querySelector('button[title="Edit"]')).not.toBeNull();
    expect(actions.querySelector('button[title="Regenerate"]')).not.toBeNull();
  });
});
