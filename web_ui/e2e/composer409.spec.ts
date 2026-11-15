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

  const posts: string[] = [];
  let refused = false;
  await page.route('**/api/chat/send', async (route: Route) => {
    const body = route.request().postData() ?? '';
    posts.push(body);
    if (!refused && body.includes('composer-409-probe')) {
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
  const mine = posts.filter((p) => p.includes('composer-409-probe'));
  expect(mine, `refused once then resent, saw ${JSON.stringify(mine)}`).toHaveLength(2);
  await expect(page.locator('textarea.composer-input')).toHaveValue('');
});
