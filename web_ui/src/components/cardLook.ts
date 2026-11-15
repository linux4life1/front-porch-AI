// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A character card's own chat font and colours on one bubble — the web twin
// of the desktop's per-character step in UiSettings.getChatFontFamily and
// the colour getters. The host decides whose card a message wears and drops
// it while a chat theme is on (chat_card_look.dart), so a `look` that arrives
// simply wins over the global Chat Appearance (theme/appearance.ts), exactly
// as the card does on the desktop. Painted as custom properties on the
// bubble itself, so everything inside it (quotes, *actions*) follows.

import type { CSSProperties } from 'react';
import { DEFAULT_CHAT_COLORS, userBubbleDialogueColor, type ChatColors } from '../chatColors';
import { currentAppearanceWire } from '../theme/appearance';

/** `look` on a chat message: only the fields the card sets. */
export interface CardLook {
  font?: string;
  userBubble?: string;
  userText?: string;
  aiBubble?: string;
  aiText?: string;
  dialogue?: string;
  action?: string;
}

const STACK = "system-ui, -apple-system, 'Segoe UI', Roboto, sans-serif";

/** The global colours the card falls back to: the host's Chat Appearance. */
function globals(): { colors: ChatColors; defaults: ChatColors } {
  const w = currentAppearanceWire();
  return {
    colors: w?.chatColors ?? DEFAULT_CHAT_COLORS,
    defaults: w?.chatColorDefaults ?? DEFAULT_CHAT_COLORS,
  };
}

/**
 * Inline style for a bubble wearing [look]. A director's note keeps its own
 * colours and takes only the font. Undefined when the card sets nothing.
 */
export function cardLookStyle(
  look: CardLook | undefined,
  kind: 'user' | 'ai' | 'director',
): CSSProperties | undefined {
  if (!look) return undefined;
  const s: Record<string, string> = {};
  if (look.font) s.fontFamily = `'${look.font}', ${STACK}`;
  if (kind === 'ai') {
    if (look.aiBubble) s['--chat-ai-bubble'] = look.aiBubble;
    if (look.aiText) s['--chat-ai-text'] = look.aiText;
    if (look.dialogue) s['--dialogue'] = look.dialogue;
    if (look.action) s['--action'] = look.action;
  } else if (kind === 'user') {
    if (look.userBubble) s['--chat-user-bubble'] = look.userBubble;
    if (look.userText) s['--chat-user-text'] = look.userText;
    // Quotes and *actions* inside the user's bubble must read on it
    // (desktop userBubbleDialogueColorFor / userBubbleActionColorFor), so a
    // card that changes any of their inputs re-derives both.
    if (look.userBubble || look.userText || look.dialogue || look.action) {
      const { colors: g, defaults: d } = globals();
      const bubble = look.userBubble ?? g.userBubble;
      const text = look.userText ?? g.userText;
      const dialogue = look.dialogue ?? g.dialogue;
      const action = look.action ?? g.action;
      const chosen = (own: string | undefined, gv: string, dv: string) =>
        !!own || gv.toLowerCase() !== dv.toLowerCase();
      s['--chat-user-dialogue'] = userBubbleDialogueColor(
        dialogue, bubble, text, chosen(look.dialogue, g.dialogue, d.dialogue),
      );
      s['--chat-user-action'] = userBubbleDialogueColor(
        action, bubble, text, chosen(look.action, g.action, d.action),
      );
    }
  }
  return Object.keys(s).length ? (s as CSSProperties) : undefined;
}

/** Loads each card's Google font once (the desktop draws card fonts with
 *  google_fonts; the global chat font loads the same way in appearance.ts). */
export function loadCardFonts(families: Iterable<string>): void {
  for (const family of new Set(families)) {
    const id = `fpai-card-font-${family.replace(/[^a-z0-9]+/gi, '-').toLowerCase()}`;
    if (document.getElementById(id)) continue;
    const el = document.createElement('link');
    el.id = id;
    el.rel = 'stylesheet';
    el.href = `https://fonts.googleapis.com/css2?family=${encodeURIComponent(family).replace(
      /%20/g,
      '+',
    )}&display=swap`;
    document.head.appendChild(el);
  }
}
