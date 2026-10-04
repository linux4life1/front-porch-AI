// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Every spec runs under these guards. A test fails if, at any point, the page
// threw, logged a console error, hit a missing or failing /api endpoint, or
// showed the crash screen — whether or not the spec was looking at that spot.

import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { test as base, expect, type Page } from '@playwright/test';

export type Problem = string;

/** A browser that died under the test, as Playwright reports it. */
const BROWSER_CRASH = /Target crashed|Target page, context or browser has been closed/;

/** Responses a spec expects (e.g. a deliberately wrong password). */
export type AllowFn = (url: string, status: number) => boolean;

export const CRASH_TEXT = 'Something went wrong on this screen';

/** Error statuses that are the endpoint's normal answer, each with why. */
const KNOWN: { method: string; status: number; path: RegExp; why: string }[] = [
  { method: 'GET', status: 404, path: /^\/api\/image\/expression-pack$/, why: '"no pack running" is a 404 by contract' },
  // The sandboxed test app has no OS keychain; the page shows the store as unavailable.
  { method: 'GET', status: 503, path: /^\/api\/image\/civitai\/credential$/, why: 'no keychain in the test sandbox' },
  // TTS is off in the sandbox; "Read aloud" is answered 503 by contract and
  // the reader shows the reason.
  { method: 'POST', status: 503, path: /^\/api\/stories\/[^/]+\/narrate$/, why: 'TTS is off in the test sandbox' },
];

type Hooks = { fn: AllowFn; acceptConfirms: boolean };

function watch(page: Page, problems: Problem[], allow: Hooks) {
  page.on('pageerror', (e) => problems.push(`uncaught error: ${e.message}`));
  page.on('console', (m) => {
    if (m.type() !== 'error') return;
    const text = m.text();
    // Network failures are reported (with their URL) by the response hook.
    if (/^Failed to load resource/.test(text)) return;
    problems.push(`console error: ${text}`);
  });
  page.on('response', (r) => {
    const url = r.url();
    if (!url.includes('/api/') || r.status() < 400) return;
    // Avatars fall back (expression → card art → letter) by design; a picture
    // that actually shows broken is caught by brokenImages() instead.
    if (r.request().resourceType() === 'image' && r.status() === 404) return;
    if (KNOWN.some((k) => k.method === r.request().method() && k.status === r.status() && k.path.test(new URL(url).pathname))) return;
    if (allow.fn(url, r.status())) return;
    problems.push(`HTTP ${r.status()} from ${r.request().method()} ${new URL(url).pathname}`);
  });
  page.on('requestfailed', (r) => {
    const url = r.url();
    const why = r.failure()?.errorText ?? '';
    // Navigations and unmounts cancel in-flight reads; that is not a bug.
    if (!url.includes('/api/') || /abort|cancel/i.test(why)) return;
    problems.push(`request failed: ${r.method()} ${new URL(url).pathname} (${why})`);
  });
  // Every confirm() is answered "no" unless a spec opts in, so a sweep can
  // never confirm a delete.
  page.on('dialog', (d) => void (allow.acceptConfirms ? d.accept() : d.dismiss()).catch(() => {}));
  page.on('popup', (p) => void p.close().catch(() => {}));
}

/**
 * FPAI_BUNDLE_DIR=<a `vite build --outDir` folder> serves that web bundle in
 * place of the one baked into the app — iterate on web UI changes against a
 * held app without rebuilding Flutter. /api stays on the real server.
 */
async function serveBundle(page: Page, dir: string) {
  const { readFile } = await import('node:fs/promises');
  const { extname, join, normalize } = await import('node:path');
  const types: Record<string, string> = {
    '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json',
    '.png': 'image/png', '.svg': 'image/svg+xml', '.webmanifest': 'application/manifest+json',
    '.woff2': 'font/woff2', '.mp3': 'audio/mpeg', '.ogg': 'audio/ogg',
  };
  await page.route(
    (url) => !url.pathname.startsWith('/api/'),
    async (route) => {
      const rel = normalize(decodeURIComponent(new URL(route.request().url()).pathname)).replace(/^[/\\]+/, '');
      for (const file of [join(dir, rel), join(dir, 'index.html')]) {
        try {
          const body = await readFile(file);
          return route.fulfill({ body, contentType: types[extname(file)] ?? 'application/octet-stream' });
        } catch {
          // fall through to the SPA shell
        }
      }
      return route.continue();
    },
  );
}

export const test = base.extend<{
  crashRetry: void;
  problems: Problem[];
  allowHttp: (fn: AllowFn) => void;
  acceptConfirms: (on: boolean) => void;
}>({
  // The phone project gets one retry on CI (playwright.config.ts) for one
  // reason only: WebKit on the Linux runner crashes now and then. A retry
  // after any other failure fails at once with the first try's error, and a
  // pass after a crash is put on the run's page as a warning.
  crashRetry: [
    async ({}, use, testInfo) => {
      const note = join(testInfo.project.outputDir, 'first-tries', `${testInfo.testId}.txt`);
      if (testInfo.retry > 0) {
        const first = await readFile(note, 'utf8').catch(() => '');
        if (!BROWSER_CRASH.test(first)) {
          throw new Error(`retried only after a browser crash; the first try failed with: ${first || '(no error recorded)'}`);
        }
      }
      await use();
      if (testInfo.retry === 0 && testInfo.status !== testInfo.expectedStatus) {
        await mkdir(dirname(note), { recursive: true });
        await writeFile(note, testInfo.errors.map((e) => e.message ?? '').join('\n'));
      } else if (testInfo.retry > 0 && testInfo.status === testInfo.expectedStatus) {
        const name = `${testInfo.titlePath.slice(1).join(' › ')} [${testInfo.project.name}]`;
        console.log(`::warning title=Browser crash::${name} passed on a second try after the browser crashed`);
      }
    },
    { auto: true },
  ],
  problems: [
    async ({ page }, use, testInfo) => {
      if (process.env.FPAI_BUNDLE_DIR) await serveBundle(page, process.env.FPAI_BUNDLE_DIR);
      const problems: Problem[] = [];
      const allow: Hooks = { fn: () => false, acceptConfirms: false };
      (page as Page & { __hooks?: Hooks }).__hooks = allow;
      watch(page, problems, allow);
      await use(problems);
      if (await page.getByText(CRASH_TEXT).isVisible().catch(() => false)) {
        problems.push(`crash screen visible at the end of the test (${page.url()})`);
      }
      if (problems.length) {
        await testInfo.attach('problems', { body: problems.join('\n'), contentType: 'text/plain' });
      }
      expect(problems, 'page problems while the test ran').toEqual([]);
    },
    { auto: true },
  ],
  allowHttp: async ({ page, problems: _ }, use) => {
    await use((fn) => {
      (page as Page & { __hooks?: Hooks }).__hooks!.fn = fn;
    });
  },
  acceptConfirms: async ({ page, problems: _ }, use) => {
    await use((on) => {
      (page as Page & { __hooks?: Hooks }).__hooks!.acceptConfirms = on;
    });
  },
});

export { expect };

/** Go to a hash route and wait for its first data load to finish. */
export async function openRoute(page: Page, route: string) {
  await page.goto(`/#${route}`);
  await page.waitForLoadState('networkidle', { timeout: 10_000 }).catch(() => {});
}
