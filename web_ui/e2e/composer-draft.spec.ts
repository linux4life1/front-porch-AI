// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The composer draft survives leaving the chat and coming back — the PWA
// half of the hand-check the maintainer already ran on the Flutter app.
// A half-typed line is kept in localStorage (fpai.draft.s.<session> once
// the chat has sent a message, fpai.draft.o.<owner> while it has not),
// restored when the chat mounts again, and never replayed after a send.
// Against the real app, like every spec here: run it through the Flutter
// host (integration_test/web_ui/browser_test.dart) or point
// FPAI_BASE_URL/FPAI_USER/FPAI_PASSWORD at a running app.

import { expect, openRoute, test } from './support/fixtures';
import { sendLine, waitSendable } from './support/composer';

const box = (page: import('@playwright/test').Page) =>
  page.locator('textarea.composer-input');

const startNewChat = async (request: import('@playwright/test').APIRequestContext) => {
  const started = await request.post('/api/chat/session', { data: { action: 'new' } });
  expect(started.ok(), `start a new chat: ${started.status()}`).toBe(true);
};

/** Wait until no `fpai.draft.*` key still holds [line]. A send clears
 *  the box at once, but the storage flush behind it is the debounced
 *  half; a reopen racing that window seeds the box from pre-send
 *  storage (seen once on the phone-webkit CI runner: box empty, reopen
 *  held the sent line, retry passed). Polling the keys turns that race
 *  into a named wait instead of a confusing box-seed failure. */
const lineIsFlushed = (page: import('@playwright/test').Page, line: string) =>
  expect
    .poll(
      () =>
        page.evaluate((needle) => {
          for (let i = 0; i < localStorage.length; i++) {
            const k = localStorage.key(i)!;
            if (
              k.startsWith('fpai.draft.') &&
              localStorage.getItem(k) === needle
            )
              return false;
          }
          return true;
        }, line),
      { message: `the send flushed the draft keys (still holding "${line}")` },
    )
    .toBe(true);

test.describe('the composer draft', () => {
  // Each test gets a fresh browser context, so one test's localStorage
  // drafts cannot seed another's box; the host's chat is shared, so
  // nothing here sends a line except the send test.

  test('a half-typed line comes back after leaving the chat', async ({ page }) => {
    const draft = `half-typed ${test.info().testId}`;
    await openRoute(page, '/chat');
    await expect(box(page)).toBeVisible();
    await box(page).fill(draft);

    // Leave (the composer unmounts and must flush) and come back. `/` is the
    // library route; `/library` is not a route (the app redirects it to `/`),
    // and on a slow CI runner that redirect can land after the next
    // `openRoute('/chat')`, leaving the library instead of the chat.
    await openRoute(page, '/');
    await openRoute(page, '/chat');
    await expect(box(page), 'the half-typed line back in the box').toHaveValue(draft);

    // Put the box away empty so a later route visit starts clean.
    await box(page).fill('');
    await openRoute(page, '/');
  });

  test('a sent line is never replayed', async ({ page }) => {
    await openRoute(page, '/chat');
    await expect(box(page)).toBeVisible();
    const line = `draft gone ${test.info().testId}`;
    await sendLine(page, line);
    await expect(box(page)).toHaveValue('');
    await lineIsFlushed(page, line); // the storage flush, not just the box

    await openRoute(page, '/');
    await openRoute(page, '/chat');
    await expect(box(page), 'the sent line not to haunt the box').toHaveValue('');
  });

  test("a never-sent new chat's draft waits in the owner mailbox", async ({
    page,
    request,
  }) => {
    const draft = `first hello ${test.info().testId}`;
    // A genuinely new chat: no user message yet, so the draft keys by
    // owner, not by the session that is about to be thrown away.
    await startNewChat(request);
    await openRoute(page, '/chat');
    await expect(box(page)).toBeVisible();
    await box(page).fill(draft);
    await waitSendable(page); // keep the host quiet while we navigate

    // Abandon it unsent; start ANOTHER new chat with the same character.
    await openRoute(page, '/');
    await startNewChat(request);
    await openRoute(page, '/chat');
    await expect(
      box(page),
      'the abandoned line offered to the next new chat',
    ).toHaveValue(draft);

    // The mailbox is one letter: empty the box for whoever is next.
    await box(page).fill('');
    await openRoute(page, '/');
  });
});
