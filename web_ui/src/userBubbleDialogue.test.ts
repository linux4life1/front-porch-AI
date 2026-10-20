// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Quoted speech in the user's own bubble must read on that bubble (desktop
// twin: test/ui/chat_components/user_bubble_dialogue_contrast_test.dart).
// The pure colour rule, then the two places that publish it as
// --chat-user-dialogue: the per-device Chat colors and a per-chat theme.

import { describe, it, expect, beforeEach } from 'vitest';
import {
  DEFAULT_CHAT_COLORS,
  MIN_USER_DIALOGUE_CONTRAST,
  applyChatColors,
  contrastRatio,
  userBubbleDialogueColor,
} from './chatColors';
import { resolveThemeColors } from './components/ChatThemeSettings';

const EMERALD = '#10b981';
const DARK_INK = '#1f1f1f';
const ORANGE = '#b45309';

beforeEach(() => {
  document.documentElement.removeAttribute('style');
});

describe('userBubbleDialogueColor', () => {
  it('re-tints the default orange to read on a green bubble, darker like the text', () => {
    expect(contrastRatio(ORANGE, EMERALD)).toBeLessThan(MIN_USER_DIALOGUE_CONTRAST);
    const tint = userBubbleDialogueColor(ORANGE, EMERALD, DARK_INK, false);
    expect(contrastRatio(tint, EMERALD)).toBeGreaterThanOrEqual(MIN_USER_DIALOGUE_CONTRAST);
    expect(tint).not.toBe(ORANGE);
  });

  it('keeps a dialogue colour the user picked', () => {
    expect(userBubbleDialogueColor('#e65100', EMERALD, DARK_INK, true)).toBe('#e65100');
  });

  it('keeps the default when it already reads on the bubble', () => {
    expect(userBubbleDialogueColor('#ffffff', '#000000', '#ffffff', false)).toBe('#ffffff');
  });
});

describe('--chat-user-dialogue', () => {
  it('Chat colors publish a readable user-bubble tint for the default dialogue', () => {
    applyChatColors({ ...DEFAULT_CHAT_COLORS, userBubble: EMERALD, userText: DARK_INK, dialogue: ORANGE });
    const v = document.documentElement.style.getPropertyValue('--chat-user-dialogue');
    // ORANGE is not the web default, so it counts as the user's pick: kept.
    expect(v).toBe(ORANGE);

    applyChatColors({ ...DEFAULT_CHAT_COLORS, userBubble: EMERALD, userText: DARK_INK });
    const d = document.documentElement.style.getPropertyValue('--chat-user-dialogue');
    expect(contrastRatio(d, EMERALD)).toBeGreaterThanOrEqual(MIN_USER_DIALOGUE_CONTRAST);
    // The AI bubble's tint is untouched: still at its default, so it is left
    // to the theme the desktop sends rather than pinned to the dark yellow.
    expect(document.documentElement.style.getPropertyValue('--dialogue')).toBe('');
  });

  it('a chat theme with a recoloured user bubble re-tints the preset dialogue', () => {
    // Sakura's preset dialogue (#ad1457) on a user bubble recoloured dark.
    const vars = resolveThemeColors({ themeId: 'sakura', userBubbleColor: '4a0e2a', userTextColor: 'ffffff' });
    expect(vars['--dialogue']).toBe('#ad1457');
    expect(contrastRatio(vars['--chat-user-dialogue'], '#4a0e2a')).toBeGreaterThanOrEqual(MIN_USER_DIALOGUE_CONTRAST);

    const picked = resolveThemeColors({ themeId: 'sakura', userBubbleColor: '4a0e2a', dialogueColor: 'ad1457' });
    expect(picked['--chat-user-dialogue']).toBe('#ad1457');
  });
});

describe('--chat-user-action', () => {
  it('re-tints the default action blue to read on the user bubble, and keeps a pick', () => {
    applyChatColors({ ...DEFAULT_CHAT_COLORS });
    const tint = document.documentElement.style.getPropertyValue('--chat-user-action');
    expect(contrastRatio(tint, DEFAULT_CHAT_COLORS.userBubble)).toBeGreaterThanOrEqual(MIN_USER_DIALOGUE_CONTRAST);
    expect(contrastRatio(DEFAULT_CHAT_COLORS.action, DEFAULT_CHAT_COLORS.userBubble)).toBeLessThan(MIN_USER_DIALOGUE_CONTRAST);

    applyChatColors({ ...DEFAULT_CHAT_COLORS, action: '#123456' });
    expect(document.documentElement.style.getPropertyValue('--chat-user-action')).toBe('#123456');

    const themed = resolveThemeColors({ themeId: 'sakura', userBubbleColor: '4a0e2a', userTextColor: 'ffffff' });
    expect(contrastRatio(themed['--chat-user-action'], '#4a0e2a')).toBeGreaterThanOrEqual(MIN_USER_DIALOGUE_CONTRAST);
  });
});
