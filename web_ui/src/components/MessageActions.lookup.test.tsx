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

function render(opts: { web?: boolean; wiki?: boolean; onRegenerate?: ReturnType<typeof vi.fn> }) {
  const onRegenerate = opts.onRegenerate ?? vi.fn();
  act(() => {
    root.render(
      createElement(MessageActions, {
        m: bot,
        isLast: true,
        busy: false,
        canSpeak: false,
        lookupWeb: opts.web ?? false,
        lookupWiki: opts.wiki ?? false,
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

function openRegen() {
  const regen = container.querySelector(
    'button[title="Regenerate"]',
  ) as HTMLButtonElement;
  act(() => {
    regen.click();
  });
}

describe('MessageActions named lookup', () => {
  beforeEach(() => {
    container = document.createElement('div');
    document.body.appendChild(container);
    root = createRoot(container);
  });
  afterEach(() => {
    act(() => root.unmount());
    container.remove();
  });

  it('hides the lookup row when web search is off and there is no wiki', () => {
    render({});
    openRegen();
    expect(container.querySelector('[data-testid="regen-critique-field"]')).not.toBeNull();
    expect(container.querySelector('[data-testid="regen-lookup-query"]')).toBeNull();
    expect(container.querySelector('[data-testid="regen-lookup-web"]')).toBeNull();
  });

  it('disables her wiki when this chat has none and sends the web words', () => {
    const onRegenerate = render({ web: true, wiki: false });
    openRegen();
    const wiki = container.querySelector(
      '[data-testid="regen-lookup-wiki"]',
    ) as HTMLButtonElement;
    expect(wiki.disabled).toBe(true);
    const input = container.querySelector(
      '[data-testid="regen-lookup-query"]',
    ) as HTMLInputElement;
    act(() => {
      const setter = Object.getOwnPropertyDescriptor(
        HTMLInputElement.prototype,
        'value',
      )?.set;
      setter?.call(input, 'Wandenreich');
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
    expect(onRegenerate).toHaveBeenCalledWith('', {
      source: 'web',
      query: 'Wandenreich',
    });
  });

  it('omits web when web search is off and a wiki is set', () => {
    render({ web: false, wiki: true });
    openRegen();
    expect(container.querySelector('[data-testid="regen-lookup-web"]')).toBeNull();
    expect(container.querySelector('[data-testid="regen-lookup-wiki"]')).not.toBeNull();
    expect(container.querySelector('[data-testid="regen-lookup-query"]')).not.toBeNull();
  });
});
