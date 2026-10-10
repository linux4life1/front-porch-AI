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
  root.style.setProperty(
    '--chat-user-dialogue',
    userBubbleDialogueColor(
      c.dialogue,
      c.userBubble,
      c.userText,
      c.dialogue.toLowerCase() !== DEFAULT_CHAT_COLORS.dialogue,
    ),
  );
}

// ── Quoted speech on the user's own bubble ──────────────────────────────────
// Mirror of lib/utils/readable_dialogue_tint.dart: the dialogue tint is shared
// by both bubbles, so on a recoloured user bubble (orange quotes on green)
// it can all but vanish. Inside the user bubble the default tint keeps its hue
// and is lightened or darkened toward the user's text until it reads.

/** WCAG floor and target contrast for quoted speech on the user bubble. */
export const MIN_USER_DIALOGUE_CONTRAST = 3.0;
const TARGET_USER_DIALOGUE_CONTRAST = 4.5;

type Rgb = [number, number, number];

/** '#rrggbb' or '#aarrggbb' (the desktop's order) → 0-255 channels. */
function parseHex(hex: string): Rgb | null {
  const m = /^#?([0-9a-f]{6}|[0-9a-f]{8})$/i.exec(hex.trim());
  if (!m) return null;
  const h = m[1].length === 8 ? m[1].slice(2) : m[1];
  return [0, 2, 4].map((i) => parseInt(h.slice(i, i + 2), 16)) as Rgb;
}

function toHex([r, g, b]: Rgb): string {
  return '#' + [r, g, b].map((v) => Math.round(v).toString(16).padStart(2, '0')).join('');
}

function luminance([r, g, b]: Rgb): number {
  const lin = (v: number) => {
    const s = v / 255;
    return s <= 0.03928 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4);
  };
  return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b);
}

function ratio(a: Rgb, b: Rgb): number {
  const la = luminance(a);
  const lb = luminance(b);
  return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
}

/** WCAG contrast ratio of two hex colours, 1 to 21 (0 when unreadable input). */
export function contrastRatio(a: string, b: string): number {
  const ra = parseHex(a);
  const rb = parseHex(b);
  return ra && rb ? ratio(ra, rb) : 0;
}

function rgbToHsl([r, g, b]: Rgb): Rgb {
  const [rr, gg, bb] = [r / 255, g / 255, b / 255];
  const max = Math.max(rr, gg, bb);
  const min = Math.min(rr, gg, bb);
  const l = (max + min) / 2;
  const d = max - min;
  if (d === 0) return [0, 0, l];
  const s = d / (1 - Math.abs(2 * l - 1));
  let h: number;
  if (max === rr) h = ((gg - bb) / d) % 6;
  else if (max === gg) h = (bb - rr) / d + 2;
  else h = (rr - gg) / d + 4;
  return [(h * 60 + 360) % 360, s, l];
}

function hslToRgb([h, s, l]: Rgb): Rgb {
  const c = (1 - Math.abs(2 * l - 1)) * s;
  const x = c * (1 - Math.abs(((h / 60) % 2) - 1));
  const m = l - c / 2;
  const [r, g, b] =
    h < 60 ? [c, x, 0] : h < 120 ? [x, c, 0] : h < 180 ? [0, c, x]
      : h < 240 ? [0, x, c] : h < 300 ? [x, 0, c] : [c, 0, x];
  return [(r + m) * 255, (g + m) * 255, (b + m) * 255];
}

/**
 * The colour quoted speech is drawn in inside the user's own bubble. A colour
 * the user picked is kept; the default is kept when it reads on the bubble,
 * otherwise re-tinted (same hue) toward the user's text colour: to 4.5:1 when
 * that side can reach it, else just past 3:1, else the user's text colour.
 */
export function userBubbleDialogueColor(
  dialogue: string,
  bubble: string,
  userText: string,
  userChoseDialogue: boolean,
): string {
  if (userChoseDialogue) return dialogue;
  const d = parseHex(dialogue);
  const bg = parseHex(bubble);
  const fg = parseHex(userText);
  if (!d || !bg || !fg) return dialogue;
  if (ratio(d, bg) >= MIN_USER_DIALOGUE_CONTRAST) return dialogue;
  const lighten = luminance(fg) >= luminance(bg);
  const [h, s, l] = rgbToHsl(d);
  const steps = 50;
  let floor: string | null = null;
  for (let i = 1; i <= steps; i++) {
    const t = i / steps;
    const light = lighten ? l + (1 - l) * t : l * (1 - t);
    const tinted = hslToRgb([h, s, Math.min(1, Math.max(0, light))]);
    const r = ratio(tinted, bg);
    if (r >= TARGET_USER_DIALOGUE_CONTRAST) return toHex(tinted);
    if (r >= MIN_USER_DIALOGUE_CONTRAST && floor === null) floor = toHex(tinted);
  }
  return floor ?? userText;
}
