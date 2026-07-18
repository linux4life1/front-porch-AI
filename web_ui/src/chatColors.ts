// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Web-local chat color customization — the WebUI mirror of the desktop's
// chat appearance colors (user bubble/text, AI bubble/text, dialogue, action).
// Stored per-device in localStorage and applied as CSS custom properties on
// :root, so they override the defaults in styles.css live (no rebuild, no server
// round-trip). The WebUI is a client with its own display prefs; this does not
// touch the desktop app's theme. No font picker (web uses the system stack).

export interface ChatColors {
  userBubble: string;
  userText: string;
  aiBubble: string;
  aiText: string;
  dialogue: string;
  action: string;
}

// Defaults mirror the desktop dark-theme defaults (ui_settings.dart).
export const DEFAULT_CHAT_COLORS: ChatColors = {
  userBubble: '#3b82f6',
  userText: '#ffffff',
  aiBubble: '#374151',
  aiText: '#ffffff',
  dialogue: '#ffd54f',
  action: '#90caf9',
};

const KEY = 'fpai.chatColors';
const VARS: Record<keyof ChatColors, string> = {
  userBubble: '--chat-user-bubble',
  userText: '--chat-user-text',
  aiBubble: '--chat-ai-bubble',
  aiText: '--chat-ai-text',
  dialogue: '--dialogue',
  action: '--action',
};

export function loadChatColors(): ChatColors {
  try {
    const raw = localStorage.getItem(KEY);
    if (raw) return { ...DEFAULT_CHAT_COLORS, ...(JSON.parse(raw) as Partial<ChatColors>) };
  } catch {
    /* corrupt/absent — fall through to defaults */
  }
  return { ...DEFAULT_CHAT_COLORS };
}

export function saveChatColors(c: ChatColors): void {
  try {
    localStorage.setItem(KEY, JSON.stringify(c));
  } catch {
    /* storage full / disabled — colors just won't persist */
  }
}

/** Push the colors onto :root as CSS custom properties (overrides styles.css). */
export function applyChatColors(c: ChatColors): void {
  const root = document.documentElement;
  (Object.keys(VARS) as (keyof ChatColors)[]).forEach((k) => {
    root.style.setProperty(VARS[k], c[k]);
  });
}
