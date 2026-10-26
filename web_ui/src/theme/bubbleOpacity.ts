// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Bubble opacity: the desktop's own setting (UiSettings.bubbleOpacity), read
// from the settings snapshot and every `settings_changed`. With nothing
// stored the desktop sends 1 while the Ambient scene is off and 0.25 while it
// paints, so the weather shows through. Only the bubble fill fades (the
// `--chat-bubble-alpha` variable the bubble CSS mixes in), never the text.

export const BUBBLE_OPACITY_MIN = 0.1;
export const BUBBLE_OPACITY_MAX = 1;

/** A finite number held to the desktop slider's range, else null. */
export function asBubbleOpacity(v: unknown): number | null {
  if (typeof v !== 'number' || !Number.isFinite(v)) return null;
  return Math.min(BUBBLE_OPACITY_MAX, Math.max(BUBBLE_OPACITY_MIN, v));
}

/** Paints [v] onto the page's bubbles; anything but a number leaves them as they are. */
export function applyBubbleOpacity(v: unknown): void {
  const alpha = asBubbleOpacity(v);
  if (alpha === null) return;
  document.documentElement.style.setProperty('--chat-bubble-alpha', String(alpha));
}
