// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

/** The window's usable box in viewport pixels: inside the notch, home bar,
 *  landscape notch and cutouts the device reports (styles/safe-area.css). */
export interface SafeBounds {
  left: number;
  top: number;
  right: number;
  bottom: number;
}

/** Reads the --fp-safe-* tokens as pixels. A custom property holding env()
 *  is not resolved by getComputedStyle, so a hidden probe pads by the tokens
 *  and its computed padding is read back. */
export function safeBounds(): SafeBounds {
  const probe = document.createElement('div');
  probe.style.cssText =
    'position:fixed;top:0;left:0;visibility:hidden;pointer-events:none;' +
    'padding:var(--fp-safe-top) var(--fp-safe-right) var(--fp-safe-bottom) var(--fp-safe-left)';
  document.body.appendChild(probe);
  const cs = getComputedStyle(probe);
  const px = (v: string) => parseFloat(v) || 0;
  const bounds = {
    left: px(cs.paddingLeft),
    top: px(cs.paddingTop),
    right: window.innerWidth - px(cs.paddingRight),
    bottom: window.innerHeight - px(cs.paddingBottom),
  };
  probe.remove();
  return bounds;
}

/** Top-left for a floating box of `width` x `height` that wants to open at
 *  (x, y), moved just enough to sit `margin` px inside the safe bounds. */
export function placeInSafeArea(
  x: number,
  y: number,
  width: number,
  height: number,
  margin = 8,
  bounds: SafeBounds = safeBounds(),
): { left: number; top: number } {
  const minLeft = bounds.left + margin;
  const minTop = bounds.top + margin;
  const maxLeft = bounds.right - width - margin;
  const maxTop = bounds.bottom - height - margin;
  return {
    left: Math.max(minLeft, Math.min(x, maxLeft)),
    top: Math.max(minTop, Math.min(y, maxTop)),
  };
}
