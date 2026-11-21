// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Appearance choices the desktop sends (settings_theme.dart
// `appearanceWire`): which theme, the accent pick, the UI font, the corner
// scale, the chat font and the chat colours, plus the catalogs the Settings
// tab renders (theme gallery previews, accent swatches, chat font list).
//
// This file only paints and remembers. It never computes a colour or a
// palette — the host resolves those — so the two surfaces cannot drift. The
// last block is cached so a reload paints the right face and corners before
// the socket connects.

import { applyChatColors, type ChatColors } from '../chatColors';

export interface ThemeCard {
  key: string;
  label: string;
  tag: string;
  blurb: string;
  dark: Record<string, string>;
  light: Record<string, string>;
}

export interface ChatFontChoice {
  label: string;
  family: string;
}

export interface AppearanceWire {
  themeId: string;
  accent: string | null;
  accentAdjusted: boolean;
  accentSwatches: string[];
  uiFont: string;
  /** The bundled family to paint, or null for the platform's own. */
  uiFontFamily: string | null;
  corners: string;
  cornerScale: number;
  /** The chat font family ('' = the UI font). */
  chatFont: string;
  chatFontChoices: ChatFontChoice[];
  /** The colours the chat paints (a pick, else the theme's default). */
  chatColors: ChatColors;
  /** The theme's own colours, so an unpicked role follows light/dark. */
  chatColorDefaults: ChatColors;
  gallery: ThemeCard[];
}

const WIRE_KEY = 'fpai.appearance.wire';
export const APPEARANCE_EVENT = 'fpai-appearance';

/** The page's own stack, used for System and anything this build lacks. */
const BASE_STACK = "system-ui, -apple-system, 'Segoe UI', Roboto, sans-serif";

/** The families the desktop bundles, as this page paints them. */
const UI_STACKS: Record<string, string> = {
  Inter: `'Inter', ${BASE_STACK}`,
  'Atkinson Hyperlegible Next': `'Atkinson Hyperlegible Next', ${BASE_STACK}`,
  Literata: `'Literata', ${BASE_STACK}`,
};

const COLOR_KEYS: (keyof ChatColors)[] = [
  'userBubble',
  'userText',
  'aiBubble',
  'aiText',
  'dialogue',
  'action',
];

function isMap(v: unknown): v is Record<string, unknown> {
  return !!v && typeof v === 'object';
}

function parseColors(raw: unknown): ChatColors | null {
  if (!isMap(raw)) return null;
  const out = {} as ChatColors;
  for (const key of COLOR_KEYS) {
    const v = raw[key];
    if (typeof v !== 'string') return null;
    out[key] = v;
  }
  return out;
}

function parseCard(raw: unknown): ThemeCard | null {
  if (!isMap(raw)) return null;
  const { key, label, tag, blurb, dark, light } = raw;
  if (typeof key !== 'string' || typeof label !== 'string') return null;
  const strings = (m: unknown): m is Record<string, string> =>
    isMap(m) && Object.values(m).every((v) => typeof v === 'string');
  if (!strings(dark) || !strings(light)) return null;
  return {
    key,
    label,
    tag: typeof tag === 'string' ? tag : '',
    blurb: typeof blurb === 'string' ? blurb : '',
    dark,
    light,
  };
}

/**
 * A block from the desktop, or null when it is not one. The gallery and the
 * chat colours are the minimum: without them the Settings tab has nothing to
 * show, and the cards stay hidden (the additive pattern — an older host
 * sends no block, and the page's own theme keeps painting).
 */
export function parseAppearanceWire(raw: unknown): AppearanceWire | null {
  if (!isMap(raw)) return null;
  const { themeId, gallery } = raw;
  const colors = parseColors(raw.chatColors);
  const defaults = parseColors(raw.chatColorDefaults);
  if (typeof themeId !== 'string' || !Array.isArray(gallery) || !colors || !defaults) return null;
  const cards = gallery.map(parseCard);
  if (cards.some((c) => c === null)) return null;
  const swatches = Array.isArray(raw.accentSwatches)
    ? raw.accentSwatches.filter((v): v is string => typeof v === 'string')
    : [];
  const choices: ChatFontChoice[] = Array.isArray(raw.chatFontChoices)
    ? raw.chatFontChoices.flatMap((c) =>
        isMap(c) && typeof c.label === 'string' && typeof c.family === 'string'
          ? [{ label: c.label, family: c.family }]
          : [],
      )
    : [];
  return {
    themeId,
    accent: typeof raw.accent === 'string' ? raw.accent : null,
    accentAdjusted: raw.accentAdjusted === true,
    accentSwatches: swatches,
    uiFont: typeof raw.uiFont === 'string' ? raw.uiFont : '',
    uiFontFamily: typeof raw.uiFontFamily === 'string' ? raw.uiFontFamily : null,
    corners: typeof raw.corners === 'string' ? raw.corners : '',
    cornerScale:
      typeof raw.cornerScale === 'number' && Number.isFinite(raw.cornerScale)
        ? raw.cornerScale
        : 1,
    chatFont: typeof raw.chatFont === 'string' ? raw.chatFont : '',
    chatFontChoices: choices,
    chatColors: colors,
    chatColorDefaults: defaults,
    gallery: cards as ThemeCard[],
  };
}

/** Loads a Google Fonts stylesheet for a chosen chat face, once per family. */
function loadChatFont(family: string): void {
  const id = 'fpai-chat-font';
  const href = `https://fonts.googleapis.com/css2?family=${encodeURIComponent(family).replace(
    /%20/g,
    '+',
  )}&display=swap`;
  const link = document.getElementById(id) as HTMLLinkElement | null;
  if (link) {
    if (link.href === href) return;
    link.href = href;
    return;
  }
  const el = document.createElement('link');
  el.id = id;
  el.rel = 'stylesheet';
  el.href = href;
  document.head.appendChild(el);
}

/** Paints the appearance choices the desktop sent. */
export function applyAppearance(w: AppearanceWire): void {
  const root = document.documentElement;
  const stack = (w.uiFontFamily && UI_STACKS[w.uiFontFamily]) || BASE_STACK;
  root.style.setProperty('--ui-font', stack);
  root.style.setProperty('--radius-scale', String(w.cornerScale));
  if (w.chatFont) {
    root.style.setProperty('--chat-font', `'${w.chatFont}', ${BASE_STACK}`);
    loadChatFont(w.chatFont);
  } else {
    root.style.removeProperty('--chat-font');
  }
  applyChatColors(w.chatColors, w.chatColorDefaults);
}

function read(key: string): string | null {
  try {
    return localStorage.getItem(key);
  } catch {
    return null;
  }
}

function write(key: string, value: string): void {
  try {
    localStorage.setItem(key, value);
  } catch {
    /* storage full or disabled */
  }
}

let heard: AppearanceWire | null = null;

/** The desktop's latest block: heard on this page, else the cached one. */
export function currentAppearanceWire(): AppearanceWire | null {
  if (heard) return heard;
  const raw = read(WIRE_KEY);
  if (!raw) return null;
  try {
    return parseAppearanceWire(JSON.parse(raw));
  } catch {
    return null;
  }
}

/** Remember and paint a block the desktop sent. */
export function receiveAppearanceWire(raw: unknown): AppearanceWire | null {
  const wire = parseAppearanceWire(raw);
  if (!wire) return null;
  heard = wire;
  write(WIRE_KEY, JSON.stringify(wire));
  applyAppearance(wire);
  window.dispatchEvent(new Event(APPEARANCE_EVENT));
  return wire;
}

/** Before first paint: the cached appearance, so nothing flashes. */
export function applyCachedAppearance(): void {
  const wire = currentAppearanceWire();
  if (wire) applyAppearance(wire);
}
