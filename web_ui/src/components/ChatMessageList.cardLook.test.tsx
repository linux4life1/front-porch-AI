// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A character card's own chat font and colours (the `look` the host sends per
// message, chat_card_look.dart) paint the bubble they belong to, over the
// global Chat Appearance, as the desktop's per-character step does. A bubble
// without a look keeps the global paint; a director's note takes only the
// font. Quotes and *actions* in the user's bubble are re-derived to read on
// the card's bubble colour.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement, createRef } from 'react';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { ChatMessageList } from './ChatMessageList';
import type { Message } from './chatTypes';
import { cardLookStyle } from './cardLook';
import { userBubbleDialogueColor, DEFAULT_CHAT_COLORS } from '../chatColors';

let container: HTMLDivElement;
let root: Root;
const noop = vi.fn();

const look = { font: 'Lora', aiBubble: '#224466', aiText: '#FFEEDD', dialogue: '#AA3300', userBubble: '#FFD740' };

const messages: Message[] = [
  { index: 0, sender: 'Maren', text: 'Hello "there".', isUser: false, characterId: 'c1', look },
  { index: 1, sender: 'You', text: 'Hi.', isUser: true, look },
  { index: 2, sender: 'Bram', text: 'Evening.', isUser: false, characterId: 'c2' },
  { index: 3, sender: 'Director', text: 'Rain starts.', isUser: false, characterId: '__director__', look },
];

function renderList() {
  act(() => {
    root.render(
      createElement(ChatMessageList, {
        messages,
        castById: new Map(),
        multiCast: false,
        lastIndex: 3,
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

const bubbles = () => Array.from(container.querySelectorAll<HTMLElement>('.bubble'));

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
  document.querySelectorAll('link[id^="fpai-card-font-"]').forEach((el) => el.remove());
});

it('paints a reply in its card font and colours', () => {
  renderList();
  const reply = bubbles()[0];
  expect(reply.style.fontFamily).toContain('Lora');
  expect(reply.style.getPropertyValue('--chat-ai-bubble')).toBe('#224466');
  expect(reply.style.getPropertyValue('--chat-ai-text')).toBe('#FFEEDD');
  expect(reply.style.getPropertyValue('--dialogue')).toBe('#AA3300');
  // The user's colours are not the reply's business.
  expect(reply.style.getPropertyValue('--chat-user-bubble')).toBe('');
});

it("paints the user's bubble with the card's user side, quotes kept readable", () => {
  renderList();
  const user = bubbles()[1];
  expect(user.style.fontFamily).toContain('Lora');
  expect(user.style.getPropertyValue('--chat-user-bubble')).toBe('#FFD740');
  expect(user.style.getPropertyValue('--chat-ai-bubble')).toBe('');
  // A dialogue colour the card picked is kept as it is.
  expect(user.style.getPropertyValue('--chat-user-dialogue')).toBe('#AA3300');
});

it('leaves a bubble with no look to the global paint, and a note gets the font only', () => {
  renderList();
  const [, , other, note] = bubbles();
  expect(other.getAttribute('style') ?? '').toBe('');
  expect(note.style.fontFamily).toContain('Lora');
  expect(note.style.getPropertyValue('--chat-ai-bubble')).toBe('');
});

it("loads each card's font once", () => {
  renderList();
  const links = document.querySelectorAll('link[id^="fpai-card-font-"]');
  expect(links.length).toBe(1);
  expect((links[0] as HTMLLinkElement).href).toContain('family=Lora');
});

it('re-derives the user quote tint from the card bubble when the card leaves dialogue unset', () => {
  const s = cardLookStyle({ userBubble: '#FFD740' }, 'user') as Record<string, string>;
  const d = DEFAULT_CHAT_COLORS;
  expect(s['--chat-user-dialogue']).toBe(
    userBubbleDialogueColor(d.dialogue, '#FFD740', d.userText, false),
  );
  expect(cardLookStyle(undefined, 'ai')).toBeUndefined();
  expect(cardLookStyle({}, 'ai')).toBeUndefined();
});
