// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "Other words" on a reply (desktop parity, KoboldCpp only): the button shows
// only when the reply kept its unsure words, the modal lists them, and
// tapping a word posts the pick for THAT reply and place.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { MessageActions } from './MessageActions';
import { type Message } from './chatTypes';

const get = vi.fn();
const post = vi.fn();
vi.mock('../api/client', () => ({
  api: {
    get: (path: string) => get(path),
    post: (path: string, body: unknown) => post(path, body),
  },
}));

let container: HTMLDivElement;
let root: Root;

function render(m: Message) {
  act(() => {
    root.render(
      createElement(MessageActions, {
        m,
        isLast: true,
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

const reply: Message = { index: 4, text: 'She sat on the porch.', sender: 'Nia', isUser: false };
const places = {
  canPick: true,
  places: [{ token: ' porch', p: 0.3, leadIn: 'She sat on the', alts: [{ token: ' steps', p: 0.3 }] }],
};

describe('Other words', () => {
  beforeEach(() => {
    get.mockReset();
    post.mockReset();
    container = document.createElement('div');
    document.body.appendChild(container);
    root = createRoot(container);
  });
  afterEach(() => {
    act(() => root.unmount());
    container.remove();
  });

  it('is hidden when the reply kept no words', () => {
    render(reply);
    expect(container.querySelector('button[title="Other words"]')).toBeNull();
  });

  it('lists the words and picks one for this reply', async () => {
    get.mockResolvedValue(places);
    post.mockResolvedValue({ status: 'ok' });
    render({ ...reply, hasTokenAlts: true });

    await act(async () => {
      (container.querySelector('button[title="Other words"]') as HTMLButtonElement).click();
    });
    expect(get).toHaveBeenCalledWith('/api/chat/token-alts?index=4');
    expect(container.textContent).toContain('She sat on the porch 30%');

    const word = container.querySelector('button.tokalt-word') as HTMLButtonElement;
    expect(word.textContent).toBe('steps 30%');
    await act(async () => {
      word.click();
    });
    expect(post).toHaveBeenCalledWith('/api/chat/token-alts/pick', { index: 4, place: 0, word: ' steps' });
    expect(container.querySelector('[aria-label="Other words it weighed"]')).toBeNull();
  });

  it('an earlier reply shows why its words cannot be picked', async () => {
    get.mockResolvedValue({ ...places, canPick: false, refusal: 'Only the last reply can be rewritten from a word.' });
    render({ ...reply, hasTokenAlts: true });
    await act(async () => {
      (container.querySelector('button[title="Other words"]') as HTMLButtonElement).click();
    });
    expect(container.textContent).toContain('Only the last reply can be rewritten from a word.');
    expect((container.querySelector('button.tokalt-word') as HTMLButtonElement).disabled).toBe(true);
  });
});
