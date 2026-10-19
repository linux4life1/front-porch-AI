// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Inspect prompt on a reply (desktop parity): the button shows only when the
// reply kept its prompt, and opens the Context Budget for THAT reply
// (`?index=`), labelled "This reply", with no Refresh.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { MessageActions } from './MessageActions';
import { type Message } from './chatTypes';

const get = vi.fn();
vi.mock('../api/client', () => ({
  api: { get: (path: string) => get(path), post: () => Promise.resolve({}) },
}));

let container: HTMLDivElement;
let root: Root;

function render(m: Message) {
  act(() => {
    root.render(
      createElement(MessageActions, {
        m,
        isLast: false,
        busy: false,
        canSpeak: false,
        onSwipe: vi.fn(),
        onRegenerate: vi.fn(),
        onContinue: vi.fn(),
        onFork: vi.fn(),
        onEdit: vi.fn(),
        onDelete: vi.fn(),
      }),
    );
  });
}

const reply: Message = { index: 3, text: 'She hands you a peach.', sender: 'Carmen', isUser: false };

describe('Inspect prompt', () => {
  beforeEach(() => {
    get.mockReset();
    container = document.createElement('div');
    document.body.appendChild(container);
    root = createRoot(container);
  });
  afterEach(() => {
    act(() => root.unmount());
    container.remove();
  });

  it('is hidden when the reply kept no prompt', () => {
    render(reply);
    expect(container.querySelector('button[title="Inspect prompt"]')).toBeNull();
  });

  it("opens that reply's prompt", async () => {
    get.mockResolvedValue({
      contextLimit: 4096,
      source: 'reply',
      textPruned: true,
      sections: [{ label: 'Chat History', tokens: 120, text: '' }],
    });
    render({ ...reply, hasContext: true });

    const button = container.querySelector('button[title="Inspect prompt"]') as HTMLButtonElement;
    await act(async () => {
      button.click();
    });

    expect(get).toHaveBeenCalledWith('/api/chat/context-budget?index=3');
    const text = container.textContent ?? '';
    expect(text).toContain('This reply');
    expect(text).toContain('Total: 120 / 4096 tokens');
    expect(text).toContain('Only the token counts are kept for older replies.');
    expect(container.querySelector('button[title="Refresh estimate from this chat"]')).toBeNull();
  });

  it('says how many older messages the reply left out, outside the total', async () => {
    get.mockResolvedValue({
      contextLimit: 8192,
      source: 'reply',
      droppedMessages: 48,
      sections: [{ label: 'Chat History', tokens: 7000, text: 'Nia: hi' }],
    });
    render({ ...reply, hasContext: true });

    const button = container.querySelector('button[title="Inspect prompt"]') as HTMLButtonElement;
    await act(async () => {
      button.click();
    });

    const text = container.textContent ?? '';
    expect(text).toContain('48 older messages not sent — trimmed to fit the context.');
    expect(text).toContain('Total: 7000 / 8192 tokens');
  });
});
