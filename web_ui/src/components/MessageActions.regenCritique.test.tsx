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
      container.querySelector('textarea[data-testid="regen-critique-field"]'),
    ).toBeNull();
    const regen = container.querySelector(
      'button[title="Regenerate"]',
    ) as HTMLButtonElement;
    act(() => {
      regen.click();
    });
    const input = container.querySelector(
      'textarea[data-testid="regen-critique-field"]',
    ) as HTMLTextAreaElement | null;
    expect(input).not.toBeNull();
    expect(input!.placeholder).toBe('why this take was wrong — optional');
    expect(input!.tagName).toBe('TEXTAREA');
    expect(Number(input!.rows)).toBeGreaterThanOrEqual(3);
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
      'textarea[data-testid="regen-critique-field"]',
    ) as HTMLTextAreaElement;
    act(() => {
      const setter = Object.getOwnPropertyDescriptor(
        HTMLTextAreaElement.prototype,
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

  it('keeps a long critique in a wrapping textarea, not a single-line input', () => {
    render();
    const regen = container.querySelector(
      'button[title="Regenerate"]',
    ) as HTMLButtonElement;
    act(() => {
      regen.click();
    });
    const field = container.querySelector(
      '[data-testid="regen-critique-field"]',
    ) as HTMLTextAreaElement;
    expect(field.tagName).toBe('TEXTAREA');
    expect(
      container.querySelector('input[data-testid="regen-critique-field"]'),
    ).toBeNull();
    const long =
      'This take was wrong because it lectured for a full page instead of answering, then repeated the lecture.';
    act(() => {
      const setter = Object.getOwnPropertyDescriptor(
        HTMLTextAreaElement.prototype,
        'value',
      )?.set;
      setter?.call(field, long);
      field.dispatchEvent(new Event('input', { bubbles: true }));
    });
    expect(field.value).toBe(long);
    expect(field.scrollWidth).toBeLessThanOrEqual(field.clientWidth + 1);
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
      container.querySelector('textarea[data-testid="regen-critique-field"]'),
    ).toBeNull();
  });
});
