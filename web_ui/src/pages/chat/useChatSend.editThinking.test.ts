// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The desktop sends `text` think-stripped and the reasoning in
// `thinkingContent`. The PWA editor opened on `text` alone, so its Thinking
// section was empty and Save wrote the message back without its reasoning.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement, useEffect } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { Message } from '../../components/chatTypes';
import { splitMessageForEdit } from '../../components/messageEdit';

const post = vi.fn(async () => ({}));

vi.mock('../../api/client', () => ({
  api: {
    post: (...args: unknown[]) => post(...args),
  },
}));

const { useChatSend } = await import('./useChatSend');

type Hook = ReturnType<typeof useChatSend>;

let container: HTMLDivElement;
let root: Root;
let hook!: Hook;

function Probe() {
  const h = useChatSend(async () => {});
  useEffect(() => {
    hook = h;
  });
  return null;
}

const reply = {
  index: 4,
  sender: 'Ada',
  isUser: false,
  text: 'She smiles at you.',
  hasThinking: true,
  thinkingContent: 'They seem tired; be gentle.',
} as Message;

describe('useChatSend edit keeps reasoning', () => {
  beforeEach(() => {
    container = document.createElement('div');
    document.body.appendChild(container);
    root = createRoot(container);
    post.mockClear();
    act(() => root.render(createElement(Probe)));
  });
  afterEach(() => {
    act(() => root.unmount());
    container.remove();
  });

  it('opens the editor with the reasoning in its Thinking section', () => {
    act(() => hook.beginEdit(reply));
    const parts = splitMessageForEdit(hook.editTarget!.text);
    expect(parts.thinking).toBe('They seem tired; be gentle.');
    expect(parts.body).toBe('She smiles at you.');
  });

  it('saving an untouched edit does not erase the reasoning', async () => {
    act(() => hook.beginEdit(reply));
    const text = hook.editTarget!.text;
    await act(async () => {
      await hook.saveEdit(text);
    });
    expect(post).toHaveBeenCalledWith('/api/chat/edit', {
      index: 4,
      text: '<think>\nThey seem tired; be gentle.\n</think>\nShe smiles at you.',
    });
  });

  it('a message with no reasoning opens as plain text', () => {
    act(() => hook.beginEdit({ ...reply, hasThinking: false, thinkingContent: undefined }));
    expect(hook.editTarget!.text).toBe('She smiles at you.');
  });
});
