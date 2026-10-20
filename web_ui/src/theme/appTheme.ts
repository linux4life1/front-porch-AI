// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The app theme on the web. The desktop resolves the palette
// (lib/ui/theme/web_theme_tokens.dart) and sends its mode plus both token maps
// in the settings snapshot and on every `settings_changed`; this file only
// paints them. It never works out a colour, so the two sides cannot drift.
//
// The last map is cached so a reload paints the right colours before the
// socket connects. A device may override the desktop's mode; that choice is
// stored in this browser only.

export type ThemeMode = 'dark' | 'light';
export type ThemeChoice = 'desktop' | 'dark' | 'light' | 'system';

export interface ThemeWire {
  mode: ThemeMode;
  dark: Record<string, string>;
  light: Record<string, string>;
}

const WIRE_KEY = 'fpai.theme.wire';
const CHOICE_KEY = 'fpai.theme.choice';
const STYLE_ID = 'fpai-theme';
const CHOICES: ThemeChoice[] = ['desktop', 'dark', 'light', 'system'];

/** A wire from the desktop, or null when the payload is not one. */
export function parseThemeWire(raw: unknown): ThemeWire | null {
  if (!raw || typeof raw !== 'object') return null;
  const w = raw as Partial<ThemeWire>;
  const isMap = (m: unknown): m is Record<string, string> =>
    !!m && typeof m === 'object' && Object.values(m).every((v) => typeof v === 'string');
  if ((w.mode !== 'dark' && w.mode !== 'light') || !isMap(w.dark) || !isMap(w.light)) return null;
  return { mode: w.mode, dark: w.dark, light: w.light };
}

function read(key: string): string | null {
  try {
    return localStorage.getItem(key);
  } catch {
    return null; // storage disabled: the theme still applies, it just isn't remembered
  }
}

function write(key: string, value: string): void {
  try {
    localStorage.setItem(key, value);
  } catch {
    /* storage full or disabled */
  }
}

export function loadThemeChoice(): ThemeChoice {
  const v = read(CHOICE_KEY);
  return CHOICES.includes(v as ThemeChoice) ? (v as ThemeChoice) : 'desktop';
}

export function loadThemeWire(): ThemeWire | null {
  const raw = read(WIRE_KEY);
  if (!raw) return null;
  try {
    return parseThemeWire(JSON.parse(raw));
  } catch {
    return null;
  }
}

function systemMode(): ThemeMode {
  return typeof matchMedia === 'function' && matchMedia('(prefers-color-scheme: light)').matches
    ? 'light'
    : 'dark';
}

/** The mode this device shows for [wire] under [choice]. */
export function resolveMode(wire: ThemeWire | null, choice: ThemeChoice): ThemeMode {
  if (choice === 'dark' || choice === 'light') return choice;
  if (choice === 'system') return systemMode();
  return wire?.mode ?? 'dark';
}

/**
 * Paint [wire] in the mode [choice] picks. The tokens go in one <style> rule
 * on :root, not inline, so the per-device chat colours (inline on <html>)
 * still win over the theme's bubble defaults.
 */
export function applyTheme(wire: ThemeWire | null, choice: ThemeChoice): ThemeMode {
  // Nothing from the desktop yet: the stylesheet's own (dark) defaults.
  const mode = wire ? resolveMode(wire, choice) : 'dark';
  const root = document.documentElement;
  root.dataset.theme = mode;
  root.style.colorScheme = mode;
  const tokens = wire?.[mode];
  let style = document.getElementById(STYLE_ID) as HTMLStyleElement | null;
  if (!tokens) {
    style?.remove();
    return mode;
  }
  if (!style) {
    style = document.createElement('style');
    style.id = STYLE_ID;
    document.head.appendChild(style);
  }
  const body = Object.entries(tokens)
    .filter(([k, v]) => /^[a-z0-9-]+$/.test(k) && !/[;{}<]/.test(v))
    .map(([k, v]) => `--${k}: ${v};`)
    .join(' ');
  style.textContent = `:root { ${body} }`;
  const bar = document.querySelector('meta[name="theme-color"]');
  if (bar && tokens.surface) bar.setAttribute('content', tokens.surface);
  return mode;
}

/** Fired on window whenever a new wire arrives, for the Appearance card. */
export const THEME_EVENT = 'fpai-theme';

/** Remember and paint a wire the desktop sent. */
export function receiveThemeWire(raw: unknown): ThemeWire | null {
  const wire = parseThemeWire(raw);
  if (!wire) return null;
  write(WIRE_KEY, JSON.stringify(wire));
  applyTheme(wire, loadThemeChoice());
  window.dispatchEvent(new Event(THEME_EVENT));
  return wire;
}

export function saveThemeChoice(choice: ThemeChoice): ThemeMode {
  write(CHOICE_KEY, choice);
  return applyTheme(loadThemeWire(), choice);
}

/** Before first paint: the cached theme, in this device's choice. */
export function applyCachedTheme(): ThemeMode {
  return applyTheme(loadThemeWire(), loadThemeChoice());
}
