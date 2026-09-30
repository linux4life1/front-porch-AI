// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { MessageActions } from './MessageActions';
import { type Message } from './chatTypes';

let container: HTMLDivElement;
let root: Root;

const earlier: Message = {
  index: 1,
  text: '',
  sender: 'Iris',
  isUser: false,
};

function render(isLast: boolean) {
  const onDelete = vi.fn();
  act(() => {
    root.render(
      createElement(MessageActions, {
        m: { ...earlier, index: isLast ? 2 : 1 },
        isLast,
        busy: true,
        canSpeak: false,
        onSwipe: vi.fn(),
        onRegenerate: vi.fn(),
        onContinue: vi.fn(),
        onFork: vi.fn(),
        onEdit: vi.fn(),
        onDelete,
      }),
    );
  });
  return onDelete;
}

describe('delete while another reply is generating', () => {
  beforeEach(() => {
    container = document.createElement('div');
    document.body.appendChild(container);
    root = createRoot(container);
  });
  afterEach(() => {
    act(() => root.unmount());
    container.remove();
  });

  it('keeps delete on an earlier message', () => {
    const onDelete = render(false);
    const button = container.querySelector('button[title="Delete"]') as HTMLButtonElement;
    expect(button.disabled).toBe(false);
    act(() => button.click());
    expect(onDelete).toHaveBeenCalledOnce();
  });

  it('keeps the live reply locked', () => {
    render(true);
    const button = container.querySelector('button[title="Delete"]') as HTMLButtonElement;
    expect(button.disabled).toBe(true);
  });
});
