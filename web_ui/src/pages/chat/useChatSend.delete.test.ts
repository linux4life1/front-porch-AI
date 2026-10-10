// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Desktop confirms before deleting a bubble. The PWA posted immediately, then
// asked through the browser's stock window.confirm; it now asks in the page's
// warm confirm (the desktop's Delete Message / Fork Conversation dialogs) and
// posts only after the user taps the confirm button.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement, useEffect } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const post = vi.fn(async () => ({}));

vi.mock('../../api/client', () => ({
  api: {
    post: (...args: unknown[]) => post(...args),
    get: vi.fn(async () => ({})),
  },
}));

const { useChatSend } = await import('./useChatSend');
const { ChatOverlays } = await import('./ChatOverlays');

let container: HTMLDivElement;
let root: Root;
let actions!: { del: (index: number) => void; fork: (index: number) => void };

// The page's real wiring: useChatSend's pending confirm rendered by ChatOverlays.
function Page() {
  const send = useChatSend(async () => {});
  useEffect(() => {
    actions = { del: send.del, fork: send.fork };
  }, [send.del, send.fork]);
  return createElement(ChatOverlays, {
    showPicker: false,
    onPick: () => {},
    onClosePicker: () => {},
    editTarget: null,
    onCancelEdit: () => {},
    onSaveEdit: async () => {},
    showPersona: false,
    onClosePersona: () => {},
    onPersonaChanged: () => {},
    reprocessIndex: null,
    messages: [],
    onSubmitReprocess: async () => {},
    onSubmitReprocessFeelings: async () => {},
    onCloseReprocess: () => {},
    chance: null,
    onReveal: () => {},
    onAccept: () => {},
    pendingConfirm: send.pendingConfirm,
    onConfirmPending: send.confirmPending,
    onCancelPending: send.cancelPending,
  });
}

const dialog = () => container.querySelector('.drawer-backdrop .modal');
const button = (label: string) =>
  Array.from(dialog()?.querySelectorAll('button') ?? []).find((b) => b.textContent === label);

async function tap(label: string) {
  const b = button(label);
  expect(b, `"${label}" button`).toBeTruthy();
  await act(async () => {
    b!.click();
  });
}

describe('useChatSend delete / fork confirm', () => {
  beforeEach(() => {
    container = document.createElement('div');
    document.body.appendChild(container);
    root = createRoot(container);
    post.mockClear();
    act(() => root.render(createElement(Page)));
  });
  afterEach(() => {
    act(() => root.unmount());
    container.remove();
  });

  it('asks in the page, never the browser, and Cancel deletes nothing', async () => {
    const native = vi.spyOn(window, 'confirm');
    act(() => actions.del(3));
    expect(dialog()?.textContent).toContain('Delete Message');
    expect(dialog()?.textContent).toMatch(/can't be undone/i);
    expect(native).not.toHaveBeenCalled();
    expect(post).not.toHaveBeenCalled();

    await tap('Cancel');
    expect(dialog()).toBeNull();
    expect(post).not.toHaveBeenCalled();
    native.mockRestore();
  });

  it('posts the delete only after Delete is tapped', async () => {
    act(() => actions.del(3));
    await tap('Delete');
    expect(post).toHaveBeenCalledWith('/api/chat/delete', { index: 3 });
    expect(dialog()).toBeNull();
  });

  it('Fork asks the same way and branches after Fork is tapped', async () => {
    act(() => actions.fork(1));
    expect(dialog()?.textContent).toContain('Fork Conversation');
    expect(dialog()?.textContent).toContain('message #2');
    expect(post).not.toHaveBeenCalled();
    await tap('Fork');
    expect(post).toHaveBeenCalledWith('/api/chat/fork', { index: 1 });
  });
});
