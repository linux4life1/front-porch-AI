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

const bot: Message = {
  index: 1,
  text: 'He stands at the window.',
  sender: 'Mara',
  isUser: false,
  swipeIndex: 0,
  swipeCount: 1,
};

function render(onRegenerate = vi.fn()) {
  act(() => {
    root.render(
      createElement(MessageActions, {
        m: bot,
        isLast: true,
        busy: false,
        canSpeak: false,
        onSwipe: vi.fn(),
        onRegenerate,
        onContinue: vi.fn(),
        onFork: vi.fn(),
        onEdit: vi.fn(),
        onDelete: vi.fn(),
      }),
    );
  });
  return onRegenerate;
}

describe('MessageActions regen critique', () => {
  beforeEach(() => {
    container = document.createElement('div');
    document.body.appendChild(container);
    root = createRoot(container);
  });
  afterEach(() => {
    act(() => root.unmount());
    container.remove();
  });

  it('hides the field until Regen is clicked', () => {
    render();
    expect(
      container.querySelector('input[data-testid="regen-critique-field"]'),
    ).toBeNull();
    const regen = container.querySelector(
      'button[title="Regenerate"]',
    ) as HTMLButtonElement;
    act(() => {
      regen.click();
    });
    const input = container.querySelector(
      'input[data-testid="regen-critique-field"]',
    ) as HTMLInputElement | null;
    expect(input).not.toBeNull();
    expect(input!.placeholder).toBe('why this take was wrong — optional');
  });

  it('passes the typed reason to regenerate', () => {
    const onRegenerate = render();
    const regen = container.querySelector(
      'button[title="Regenerate"]',
    ) as HTMLButtonElement;
    act(() => {
      regen.click();
    });
    const input = container.querySelector(
      'input[data-testid="regen-critique-field"]',
    ) as HTMLInputElement;
    act(() => {
      const setter = Object.getOwnPropertyDescriptor(
        HTMLInputElement.prototype,
        'value',
      )?.set;
      setter?.call(input, 'too much lecture');
      input.dispatchEvent(new Event('input', { bubbles: true }));
    });
    const form = container.querySelector(
      '[data-testid="regen-critique-dialog"]',
    ) as HTMLFormElement;
    act(() => {
      form.dispatchEvent(
        new Event('submit', { bubbles: true, cancelable: true }),
      );
    });
    expect(onRegenerate).toHaveBeenCalledWith('too much lecture');
  });

  it('cancel does not regenerate', () => {
    const onRegenerate = render();
    const regen = container.querySelector(
      'button[title="Regenerate"]',
    ) as HTMLButtonElement;
    act(() => {
      regen.click();
    });
    const cancel = Array.from(container.querySelectorAll('button')).find(
      (b) => b.textContent === 'Cancel',
    ) as HTMLButtonElement;
    act(() => {
      cancel.click();
    });
    expect(onRegenerate).not.toHaveBeenCalled();
    expect(
      container.querySelector('input[data-testid="regen-critique-field"]'),
    ).toBeNull();
  });
});
