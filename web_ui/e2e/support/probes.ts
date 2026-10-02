// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// In-page checks that answer "can a person actually use this", not "is it in
// the DOM". #330 was a modal whose every button existed, looked right, and
// passed every tap through to the page underneath.

import type { Page } from '@playwright/test';

export const CONTROLS =
  'button, a[href], input:not([type="hidden"]), textarea, select, summary, [role="button"]';

/**
 * Every visible, enabled control inside [scope] whose centre — scrolled into
 * view — hit-tests to something else (covered, or tap-through). Returns one
 * line per control naming what is in the way.
 */
export async function untappableControls(page: Page, scope = 'body'): Promise<string[]> {
  return page.evaluate(
    ({ scope, controls }) => {
      const root = document.querySelector(scope);
      if (!root) return [];
      const describe = (el: Element | null) => {
        if (!el) return 'nothing';
        const h = el as HTMLElement;
        const label =
          h.getAttribute('aria-label') || h.getAttribute('title') || h.textContent?.trim().slice(0, 40) || '';
        const cls = typeof h.className === 'string' && h.className ? `.${h.className.trim().split(/\s+/).join('.')}` : '';
        return `<${h.tagName.toLowerCase()}${cls}>${label ? ` "${label}"` : ''}`;
      };
      const out: string[] = [];
      for (const el of Array.from(root.querySelectorAll(controls))) {
        const h = el as HTMLElement;
        if ((h as HTMLButtonElement).disabled || h.hidden || h.closest('[hidden], [aria-hidden="true"]')) continue;
        // Content of a collapsed <details> still reports a box in Chromium.
        const shut = h.closest('details:not([open])');
        if (shut && !shut.querySelector(':scope > summary')?.contains(h)) continue;
        const style = getComputedStyle(h);
        if (style.visibility === 'hidden' || style.display === 'none') continue;
        let r = h.getBoundingClientRect();
        if (r.width < 2 || r.height < 2) continue;
        h.scrollIntoView({ block: 'center', inline: 'center' });
        r = h.getBoundingClientRect();
        const x = r.left + r.width / 2;
        const y = r.top + r.height / 2;
        if (x < 0 || y < 0 || x > innerWidth || y > innerHeight) continue; // clipped by a scroller
        const hit = document.elementFromPoint(x, y);
        // The control itself, something inside it, or a <label> wrapping it.
        if (hit && (hit === h || h.contains(hit) || (hit.tagName === 'LABEL' && hit.contains(h)))) continue;
        if (hit && hit.closest('label')?.contains(h)) continue;
        out.push(`${describe(h)} is covered by ${describe(hit)}`);
      }
      return out;
    },
    { scope, controls: CONTROLS },
  );
}

/** On a phone the page must never scroll sideways. Names the widest culprits. */
export async function horizontalOverflow(page: Page): Promise<string[]> {
  return page.evaluate(() => {
    const vw = document.documentElement.clientWidth;
    if (document.documentElement.scrollWidth <= vw + 1) return [];
    const culprits = Array.from(document.querySelectorAll('body *'))
      .map((el) => ({ el: el as HTMLElement, right: el.getBoundingClientRect().right }))
      .filter(({ el, right }) => right > vw + 1 && getComputedStyle(el).position !== 'fixed')
      .sort((a, b) => b.right - a.right)
      .slice(0, 3)
      .map(({ el, right }) => `<${el.tagName.toLowerCase()} class="${el.className}"> reaches ${Math.round(right)}px`);
    return [`page is ${document.documentElement.scrollWidth}px wide on a ${vw}px screen: ${culprits.join('; ')}`];
  });
}

/** Overlays currently on screen, topmost last. */
export async function overlayCount(page: Page): Promise<number> {
  return page.locator('.drawer-backdrop, [role="dialog"]:not(.drawer-backdrop *)').count();
}

/**
 * Pictures on screen that failed to load and show as a broken image. Avatars
 * fall back (expression → card art) in their error handler, so a picture is
 * only broken if it still is a moment later.
 */
export async function brokenImages(page: Page): Promise<string[]> {
  const first = await brokenNow(page);
  if (!first.length) return [];
  await page.waitForTimeout(1_500);
  const second = await brokenNow(page);
  return second.filter((b) => first.includes(b));
}

async function brokenNow(page: Page): Promise<string[]> {
  return page.evaluate(() =>
    Array.from(document.images)
      .filter((img) => {
        const r = img.getBoundingClientRect();
        return img.complete && img.naturalWidth === 0 && r.width > 1 && r.height > 1 &&
          getComputedStyle(img).visibility !== 'hidden' && !img.closest('[hidden]');
      })
      .map((img) => `broken picture <img class="${img.className}" src="${new URL(img.src).pathname}">`),
  );
}

/**
 * Visible controls that stick out past the edge of the box that clips them
 * (overflow hidden/auto), so part of the label or the tap target is cut off.
 */
export async function clippedControls(page: Page, controls = CONTROLS): Promise<string[]> {
  return page.evaluate((controls) => {
    const out: string[] = [];
    const sideways = new Set<Element>();
    for (const el of Array.from(document.querySelectorAll(controls))) {
      const h = el as HTMLElement;
      const r = h.getBoundingClientRect();
      if (r.width < 2 || r.height < 2 || h.closest('[hidden], details:not([open]) > :not(summary)')) continue;
      for (let a = h.parentElement; a && a !== document.body; a = a.parentElement) {
        const ox = getComputedStyle(a).overflowX;
        if (ox === 'visible') continue;
        const box = a.getBoundingClientRect();
        if ((ox === 'auto' || ox === 'scroll') && a.scrollWidth > a.clientWidth + 1) {
          // A short strip (chips, tabs) scrolls sideways on purpose. A tall
          // panel that does is a sidebar whose content is too wide.
          if (a.clientHeight > 150 && !sideways.has(a)) {
            sideways.add(a);
            const widest = Array.from(a.querySelectorAll('*'))
              .map((e) => ({ e, w: e.getBoundingClientRect().right }))
              .sort((x, y) => y.w - x.w)[0]?.e;
            const what = (widest?.getAttribute('aria-label') || widest?.textContent || '').trim().slice(0, 50);
            out.push(`<${a.tagName.toLowerCase()} class="${a.className}"> scrolls sideways — "${what}" is too wide for it`);
          }
          break;
        }
        if (r.right > box.right + 1 || r.left < box.left - 1) {
          const label = (h.getAttribute('aria-label') || h.textContent || '').trim().slice(0, 50);
          out.push(`"${label}" is cut off by its container <${a.tagName.toLowerCase()} class="${a.className}">`);
        }
        break;
      }
    }
    return out;
  }, controls);
}

/**
 * Text and controls drawn on top of each other — a squeezed header where a
 * title and a button share the same pixels. Each centre may still hit-test
 * fine, so untappableControls() alone misses it.
 */
export async function overlappingContent(page: Page): Promise<string[]> {
  return page.evaluate((controls) => {
    const visible = (el: Element) => {
      if (el.closest('[hidden], [aria-hidden="true"], details:not([open]) > :not(summary)')) return false;
      const s = getComputedStyle(el);
      return s.visibility !== 'hidden' && s.display !== 'none' && Number(s.opacity) > 0.05;
    };
    const hasOwnText = (el: Element) =>
      Array.from(el.childNodes).some((n) => n.nodeType === Node.TEXT_NODE && (n.textContent ?? '').trim().length > 1);
    // Pinned bars (fixed / sticky) cover scrolled content by design.
    const pinned = (el: Element) => {
      for (let a: Element | null = el; a; a = a.parentElement) {
        const pos = getComputedStyle(a).position;
        if (pos === 'fixed' || pos === 'sticky') return true;
      }
      return false;
    };
    window.scrollTo(0, 0);
    const atoms: { el: Element; r: DOMRect }[] = [];
    for (const el of Array.from(document.querySelectorAll(`${controls}, body *`))) {
      const isControl = el.matches(controls);
      if (!(isControl || hasOwnText(el)) || !visible(el) || pinned(el)) continue;
      // A wrapped inline run reports one box spanning every line it touches.
      if (!isControl && getComputedStyle(el).display === 'inline') continue;
      // Only the part actually on screen: scroll boxes clip what they scroll.
      const r = DOMRect.fromRect(el.getBoundingClientRect());
      for (let a = el.parentElement; a && a !== document.body; a = a.parentElement) {
        const st = getComputedStyle(a);
        if (st.overflowX === 'visible' && st.overflowY === 'visible') continue;
        const c = a.getBoundingClientRect();
        const left = Math.max(r.left, c.left), top = Math.max(r.top, c.top);
        r.width = Math.max(0, Math.min(r.right, c.right) - left);
        r.height = Math.max(0, Math.min(r.bottom, c.bottom) - top);
        r.x = left;
        r.y = top;
      }
      if (r.width >= 4 && r.height >= 4) atoms.push({ el, r });
    }
    const name = (el: Element) =>
      `"${((el as HTMLElement).getAttribute('aria-label') || el.textContent || '').trim().slice(0, 30)}"`;
    const out: string[] = [];
    for (let i = 0; i < atoms.length; i++) {
      for (let j = i + 1; j < atoms.length; j++) {
        const a = atoms[i], b = atoms[j];
        if (a.el.contains(b.el) || b.el.contains(a.el)) continue;
        const w = Math.min(a.r.right, b.r.right) - Math.max(a.r.left, b.r.left);
        const h = Math.min(a.r.bottom, b.r.bottom) - Math.max(a.r.top, b.r.top);
        if (w <= 2 || h <= 2) continue;
        const smaller = Math.min(a.r.width * a.r.height, b.r.width * b.r.height);
        if ((w * h) / smaller <= 0.3) continue;
        // A small control placed on a big one (a card's corner menu) is a
        // layout choice when it sits wholly inside and on top.
        const [small, big] = a.r.width * a.r.height < b.r.width * b.r.height ? [a, b] : [b, a];
        const inside =
          small.r.left >= big.r.left && small.r.right <= big.r.right &&
          small.r.top >= big.r.top && small.r.bottom <= big.r.bottom;
        const top = document.elementFromPoint(small.r.left + small.r.width / 2, small.r.top + small.r.height / 2);
        if (inside && top && small.el.contains(top)) continue;
        out.push(`${name(a.el)} and ${name(b.el)} are drawn on top of each other`);
      }
    }
    return out.slice(0, 10);
  }, CONTROLS);
}
