// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Unit tests for web-local chat color load/save/apply. jsdom provides
// localStorage + document; synthetic hex values only.

import { describe, it, expect, beforeEach } from 'vitest';
import { DEFAULT_CHAT_COLORS, loadChatColors, saveChatColors, applyChatColors } from './chatColors';

beforeEach(() => {
  localStorage.clear();
  document.documentElement.removeAttribute('style');
});

describe('chatColors', () => {
  it('returns the defaults when nothing is saved', () => {
    expect(loadChatColors()).toEqual(DEFAULT_CHAT_COLORS);
  });

  it('persists custom colors and merges them over the defaults', () => {
    saveChatColors({ ...DEFAULT_CHAT_COLORS, dialogue: '#ff0000' });
    expect(loadChatColors().dialogue).toBe('#ff0000');
    expect(loadChatColors().action).toBe(DEFAULT_CHAT_COLORS.action);
  });

  it('falls back to defaults on corrupt storage', () => {
    localStorage.setItem('fpai.chatColors', '{not valid json');
    expect(loadChatColors()).toEqual(DEFAULT_CHAT_COLORS);
  });

  it('applies colors as CSS custom properties on :root', () => {
    applyChatColors({ ...DEFAULT_CHAT_COLORS, userBubble: '#123456', dialogue: '#abcdef' });
    const root = document.documentElement;
    expect(root.style.getPropertyValue('--chat-user-bubble')).toBe('#123456');
    expect(root.style.getPropertyValue('--dialogue')).toBe('#abcdef');
  });
});
