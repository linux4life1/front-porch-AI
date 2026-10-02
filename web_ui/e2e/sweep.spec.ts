// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The sweeper: visit every screen and poke everything a person can tap,
// without a per-feature script. Per screen it fails on any control that is
// covered or tap-through, a phone screen that scrolls sideways, a button whose
// tap throws or hits a failing endpoint, and a dialog that a finger cannot
// close (Close/Cancel button or a tap outside — phones have no Escape key).
// Buttons that destroy, generate, sign out or reach the internet are left
// alone (journeys cover the useful ones); every confirm() is answered "no".

import type { Page, TestInfo } from '@playwright/test';
import { expect, openRoute, test } from './support/fixtures';
import {
  brokenImages,
  clippedControls,
  horizontalOverflow,
  overlappingContent,
  overlayCount,
  untappableControls,
} from './support/probes';

const SKIP =
  /delet|remov|sign ?out|log ?out|revoke|reset|wipe|purge|clear|restart|stop|shut ?down|install|download|export|import|upload|backup|restore|disable|unlink|publish|submit|send|generat|continu|imperson|fork|swipe|regen|reprocess|revert|tailscale|pair|connect|scan|retest|spin|accept|attach|photo|mic\b|record|speak|play|save|apply|create|new|duplicat|move|start|run|write|enhanc|merge|extract|promot|join|exit|copy|share|pick a file|browse|choose file|refresh|reload|retry|try again|cancel all|pause|resume/i;
const CLOSE = /^(close|cancel|done|×|✕|✖|back|not now|dismiss|ok|got it)$/i;
const MAX_CLICKS = 70;

async function ids(page: Page) {
  const characters = await (await page.request.get('/api/characters')).json() as { id: string; name: string }[];
  const porch = characters.find((c) => c.name === 'Porch Tester') ?? characters[0];
  let story = (((await (await page.request.get('/api/stories')).json()) as { stories: { id: string; title: string }[] })
    .stories ?? []).find((s) => s.title === 'Sweep Story');
  if (!story) {
    story = (await (await page.request.post('/api/stories', { data: { title: 'Sweep Story' } })).json()) as {
      id: string;
      title: string;
    };
  }
  return { character: porch.id, story: story.id };
}

const ROUTES: ((i: { character: string; story: string }) => string)[] = [
  () => '/',
  () => '/chat',
  () => '/settings',
  () => '/account',
  () => '/remote',
  () => '/models',
  () => '/create',
  () => '/create-ai',
  () => '/create-group',
  () => '/worlds',
  () => '/worlds/from-wiki',
  () => '/stories',
  (i) => `/stories/${i.story}`,
  (i) => `/stories/${i.story}/setup`,
  (i) => `/stories/${i.story}/structure`,
  (i) => `/stories/${i.story}/read`,
  (i) => `/edit/${i.character}`,
];

async function label(page: Page, id: number): Promise<string> {
  return page.locator(`[data-sweep="${id}"]`).evaluate((el) => {
    const h = el as HTMLElement;
    return (h.getAttribute('aria-label') || h.getAttribute('title') || h.textContent || '').trim().slice(0, 60);
  });
}

/** Number the clickable, non-link controls not yet numbered. */
async function tag(page: Page, from: number): Promise<number> {
  return page.evaluate((start) => {
    let n = start;
    for (const el of Array.from(document.querySelectorAll('button, summary, [role="button"]'))) {
      if (el.hasAttribute('data-sweep') || el.closest('.drawer-backdrop, [role="dialog"]')) continue;
      el.setAttribute('data-sweep', String(n++));
    }
    return n;
  }, from);
}

/** Tap [el]; true on success, else what intercepted the tap (or ''). */
async function tap(el: ReturnType<Page['locator']>): Promise<true | string> {
  try {
    await el.click({ timeout: 4_000 });
    return true;
  } catch (e) {
    const m = /(<[^>]+>[^<]{0,40}).{0,60}intercepts pointer events/.exec(String(e));
    return m ? `covered by ${m[1]}` : '';
  }
}

/** Escape, then a tap on plain text or background away from any control. */
async function dismissPopovers(page: Page) {
  await page.keyboard.press('Escape');
  const spot = await page.evaluate(() => {
    const interactive = 'button, a, input, textarea, select, label, summary, [role], [tabindex]';
    for (let y = innerHeight - 12; y > 40; y -= 28) {
      for (let x = 12; x < innerWidth; x += 28) {
        const hit = document.elementFromPoint(x, y);
        if (hit && hit !== document.documentElement && !hit.closest(interactive)) return { x, y };
      }
    }
    return null;
  });
  if (spot) await page.mouse.click(spot.x, spot.y);
  await settle(page);
}

async function settle(page: Page) {
  await page.waitForLoadState('networkidle', { timeout: 2_500 }).catch(() => {});
  await page.waitForTimeout(150);
}

/** Check the topmost overlay, then close it the way a finger would. */
async function checkAndCloseOverlay(
  page: Page,
  opener: string,
  where: string,
  problems: string[],
): Promise<boolean> {
  await page.evaluate(() => {
    document.querySelectorAll('[data-sweep-overlay]').forEach((e) => e.removeAttribute('data-sweep-overlay'));
    const all = document.querySelectorAll('.drawer-backdrop, [role="dialog"]');
    all[all.length - 1]?.setAttribute('data-sweep-overlay', '');
  });
  for (const p of await untappableControls(page, '[data-sweep-overlay]')) {
    problems.push(`${where}: in the dialog opened by "${opener}", ${p}`);
  }
  const before = await overlayCount(page);
  const overlay = page.locator('[data-sweep-overlay]');
  const closer = overlay.getByRole('button', { name: CLOSE }).first();
  if (await closer.isVisible().catch(() => false)) {
    await closer.click({ timeout: 3_000 }).catch(() => {});
    await settle(page);
  }
  if ((await overlayCount(page)) >= before) {
    // Tap the backdrop where nothing of the dialog sits (side drawers fill
    // one edge, centred dialogs the middle).
    const spot = await page.evaluate(() => {
      const o = document.querySelector('[data-sweep-overlay]');
      if (!o) return null;
      const r = o.getBoundingClientRect();
      for (let y = r.top + 8; y < r.bottom; y += 24) {
        for (let x = r.left + 8; x < r.right; x += 24) {
          if (document.elementFromPoint(x, y) === o) return { x, y };
        }
      }
      return null;
    });
    if (spot) {
      await page.mouse.click(spot.x, spot.y);
      await settle(page);
    }
  }
  if ((await overlayCount(page)) >= before) {
    problems.push(`${where}: the dialog opened by "${opener}" has no Close/Cancel and ignores a tap outside`);
    return false;
  }
  return true;
}

async function sweep(page: Page, route: string, info: TestInfo): Promise<string[]> {
  const found: string[] = [];
  await openRoute(page, route);
  await expect(page.locator('#root')).not.toBeEmpty();

  for (const p of await untappableControls(page)) found.push(`${route}: ${p}`);
  for (const p of await brokenImages(page)) found.push(`${route}: ${p}`);
  for (const p of await clippedControls(page)) found.push(`${route}: ${p}`);
  for (const p of await overlappingContent(page)) found.push(`${route}: ${p}`);
  if (info.project.name.startsWith('phone')) {
    for (const p of await horizontalOverflow(page)) found.push(`${route}: ${p}`);
  }

  let next = await tag(page, 0);
  let clicks = 0;
  for (let id = 0; id < next && clicks < MAX_CLICKS; id++) {
    const el = page.locator(`[data-sweep="${id}"]`);
    if (!(await el.count()) || !(await el.isVisible()) || !(await el.isEnabled())) continue;
    const name = await label(page, id);
    if (!name || SKIP.test(name)) continue;
    clicks++;
    const url = page.url();
    const overlays = await overlayCount(page);
    if ((await tap(el)) !== true) {
      // Something the previous tap opened (a menu, a popover) may be in the
      // way. Dismiss it as a person would, then try once more.
      await dismissPopovers(page);
      const blocker = await tap(el);
      if (blocker !== true) {
        found.push(`${route}: "${name}" cannot be tapped — ${blocker || 'timed out'}`);
        await openRoute(page, route);
        next = await tag(page, 0);
        continue;
      }
    }
    await settle(page);
    if (page.url() !== url) {
      await openRoute(page, route);
      next = await tag(page, 0);
      continue;
    }
    if ((await overlayCount(page)) > overlays && !(await checkAndCloseOverlay(page, name, route, found))) {
      await openRoute(page, route); // stuck open: start the screen over
      next = await tag(page, 0);
      continue;
    }
    next = await tag(page, next);
  }
  return found;
}

test.describe('sweep', () => {
  for (const [n, route] of ROUTES.entries()) {
    test(`screen ${n + 1}: every control works`, async ({ page }, info) => {
      const r = route(await ids(page));
      test.info().annotations.push({ type: 'route', description: r });
      const found = await sweep(page, r, info);
      expect(found, `usability problems on ${r}`).toEqual([]);
    });
  }
});
