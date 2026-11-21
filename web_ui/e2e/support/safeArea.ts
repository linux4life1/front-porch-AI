// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A stand-in notch for the phone runs. WebKit under Playwright reports every
// env(safe-area-inset-*) as 0, so a screen that ignores the notch looks fine
// here and puts its buttons under the status bar of a real iPhone (the chat
// sidebar button on an iPhone 11). The app reads the insets only through the
// --fp-safe-* tokens (src/styles/safe-area.css), so overriding the tokens
// gives every screen and dialog a notch, a home bar and landscape cutouts at
// once — no device names, all four edges every run.

import type { Page } from '@playwright/test';
import { CONTROLS } from './probes';

/** A notch as deep as the deepest shipping iPhone's, its home bar, and side
 *  cutouts (a landscape phone's, kept narrow so the portrait test phone
 *  still has a phone's width): every edge is checked on every run. */
export const FAKE_NOTCH = { top: 59, right: 16, bottom: 34, left: 16 } as const;

/** Give every page this test opens the fake notch, from its first paint. */
export async function addFakeNotch(page: Page) {
  // html:root outranks safe-area.css's `html` rule whatever the order.
  const css =
    `html:root{--fp-safe-top:${FAKE_NOTCH.top}px;--fp-safe-right:${FAKE_NOTCH.right}px;` +
    `--fp-safe-bottom:${FAKE_NOTCH.bottom}px;--fp-safe-left:${FAKE_NOTCH.left}px}`;
  await page.addInitScript((text) => {
    const style = document.createElement('style');
    style.setAttribute('data-fake-notch', '');
    style.textContent = text;
    document.documentElement.appendChild(style);
  }, css);
}

/**
 * Visible, enabled controls inside [scope] that reach into the fake notch,
 * home bar or side cutouts: on a real phone a finger cannot tap them, or the
 * system takes the tap. Only the part of a control its scrolling containers
 * actually show counts, so a list scrolled under a toolbar is not a slip.
 */
export async function controlsInNotch(page: Page, scope = 'body'): Promise<string[]> {
  return page.evaluate(
    ({ scope, controls, inset }) => {
      const root = document.querySelector(scope);
      if (!root) return [];
      const safe = {
        left: inset.left,
        top: inset.top,
        right: innerWidth - inset.right,
        bottom: innerHeight - inset.bottom,
      };
      const out: string[] = [];
      for (const el of Array.from(root.querySelectorAll(controls))) {
        const h = el as HTMLElement;
        if ((h as HTMLButtonElement).disabled || h.closest('[hidden], [aria-hidden="true"]')) continue;
        const shut = h.closest('details:not([open])');
        if (shut && !shut.querySelector(':scope > summary')?.contains(h)) continue;
        const style = getComputedStyle(h);
        if (style.visibility === 'hidden' || style.display === 'none' || Number(style.opacity) === 0) continue;
        const r = h.getBoundingClientRect();
        let box = { left: r.left, top: r.top, right: r.right, bottom: r.bottom };
        for (let a = h.parentElement; a && a !== document.documentElement; a = a.parentElement) {
          const s = getComputedStyle(a);
          if (s.overflowX === 'visible' && s.overflowY === 'visible') continue;
          const c = a.getBoundingClientRect();
          box = {
            left: Math.max(box.left, c.left),
            top: Math.max(box.top, c.top),
            right: Math.min(box.right, c.right),
            bottom: Math.min(box.bottom, c.bottom),
          };
        }
        box = {
          left: Math.max(box.left, 0),
          top: Math.max(box.top, 0),
          right: Math.min(box.right, innerWidth),
          bottom: Math.min(box.bottom, innerHeight),
        };
        if (box.right - box.left < 2 || box.bottom - box.top < 2) continue; // not on screen
        const edges = [
          box.top < safe.top - 0.5 && 'the notch (top)',
          box.bottom > safe.bottom + 0.5 && 'the home bar (bottom)',
          box.left < safe.left - 0.5 && 'the left cutout',
          box.right > safe.right + 0.5 && 'the right cutout',
        ].filter(Boolean);
        if (!edges.length) continue;
        const label = (h.getAttribute('aria-label') || h.getAttribute('title') || h.textContent || '')
          .trim()
          .slice(0, 40);
        const cls = typeof h.className === 'string' && h.className ? `.${h.className.trim().split(/\s+/).join('.')}` : '';
        out.push(`<${h.tagName.toLowerCase()}${cls}> "${label}" sits under ${edges.join(' and ')}`);
      }
      return out;
    },
    { scope, controls: CONTROLS, inset: FAKE_NOTCH },
  );
}
