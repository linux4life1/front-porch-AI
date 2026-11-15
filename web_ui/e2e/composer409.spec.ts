// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// `sendLine` must treat a 409 the way the host tells clients to: resend.
// The refusal (busyReason in send_gates.dart, "Send it again once it
// finishes.") arrives after the page cleared the composer optimistically,
// so a harness that only watches the box loses the line — CI lost the
// buried-host journey's `/join` exactly that way (known-flakes.md).
// Both POSTs are mocked here: nothing mutates the shared server, and the
// probe pins the retry contract itself, not the send pipeline (every
// other journey exercises that).

import type { Route } from '@playwright/test';

import { expect, openRoute, test } from './support/fixtures';
import { sendLine } from './support/composer';

const LINE = 'composer-409-probe line';

// The PWA's service worker (workbox) fronts this page once installed, and
// on webkit a controlled page's fetch never meets page/context.route — the
// probe watched zero hits while the real host answered the line (seen on
// CI phone-webkit and reproduced locally against the live host). Blocking
// workers for THIS test makes both browsers take the same intercepted
// path; every other journey runs with the app's real worker policy.
test.use({ serviceWorkers: 'block' });

test('sendLine resends the line a 409 refused', async ({ page, allowHttp }) => {
  // The 409 is the point of the test; the watcher must not log it as a
  // page problem (same allowance fixture as the 401-login journey).
  allowHttp((url, status) => status === 409 && /\/api\/chat\/send/.test(url));
  await openRoute(page, '/');
  await page
    .locator('.lib-card', { hasText: 'Second Guest' })
    .locator('.lib-open')
    .click();
  await expect(page.locator('.chat-view')).toBeVisible();

  // First POST of the probe line gets the host's prescribed 409; later
  // ones succeed. Both are fulfilled, so nothing reaches the server.
  const attempts: string[] = [];
  let refused = false;
  await page.route('**/api/chat/send', async (route: Route) => {
    const body = route.request().postData() ?? '';
    attempts.push(body);
    if (!refused && body.includes(LINE)) {
      refused = true;
      await route.fulfill({
        status: 409,
        contentType: 'application/json',
        body: JSON.stringify({
          error: 'A reply is still being written. Send it again once it finishes.',
        }),
      });
      return;
    }
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ status: 'queued' }),
    });
  });

  await sendLine(page, LINE);

  // Exactly one refusal, exactly one resend, and the box finally took it.
  // Without the 409 branch in sendLine this sees one POST: the page clears
  // the box optimistically, so the old box-only check would call the lost
  // line a success.
  expect(refused, 'the first POST was refused once').toBe(true);
  const mine = attempts.filter((p) => p.includes(LINE));
  expect(mine, `refused once then resent, saw ${JSON.stringify(mine)}`).toHaveLength(2);
  await expect(page.locator('textarea.composer-input')).toHaveValue('');
});
