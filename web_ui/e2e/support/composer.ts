// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Typing a line into the chat composer the way a person does: only once the
// composer will take it, and checking that it did. See
// docs/design/known-flakes.md ("Director Mode journey: the line never sent").

import type { Page } from '@playwright/test';
import { expect } from './fixtures';

const composer = (page: Page) => page.locator('textarea.composer-input');

type ChatState = {
  isGenerating?: boolean;
  isSettlingTurn?: boolean;
  isSendWaitingOnSettle?: boolean;
  guestActivity?: { busy?: boolean };
  director?: { narrating?: boolean };
};

/**
 * The chat will take a line now, on both ends. The web twin of the Flutter
 * driver's `waitSendable()` (integration_test/support/chat_driver.dart).
 *
 * The host first: no reply, settle, joining guest or narrator beat running
 * (what `/api/chat/send` refuses with a 409). Then the page, checked last
 * because it learns the turn is over from a socket event after the host
 * does: the composer shows Send rather than Stop. While it shows Stop its
 * `isGenerating` is true and Enter keeps the line in the box unsent, by
 * design, so a test that types in that window loses its line silently.
 */
export async function waitSendable(page: Page, timeout = 60_000) {
  await expect
    .poll(
      async () => {
        const s = (await (await page.request.get('/api/chat/state')).json()) as ChatState;
        return (
          !s.isGenerating &&
          !s.isSettlingTurn &&
          !s.isSendWaitingOnSettle &&
          !s.guestActivity?.busy &&
          !s.director?.narrating
        );
      },
      { timeout, message: 'the host to finish its turn' },
    )
    .toBe(true);
  const button = page.locator('.chat-input button.primary');
  await expect(button.filter({ hasText: 'Stop' }), 'the page to show the turn is over').toHaveCount(0, { timeout });
  await expect(button.filter({ hasText: 'Send' })).toBeVisible({ timeout });
  await expect(composer(page)).toBeEditable({ timeout });
}

/**
 * Types [text] into the composer and sends it with Enter, then proves the
 * page took it: `send()` empties the box only when it hands the line on.
 *
 * Two ways a line was lost on CI, both silent until a later assertion
 * timed out: Enter while the page still thought a reply was streaming (the
 * line stays in the box), and a `fill()` that never reached the box on
 * phone WebKit (the box was empty at Enter, nothing was posted). Each
 * attempt waits until the chat is sendable, checks the box holds the line,
 * and only retries while the box still holds it, which means nothing was
 * sent, so a retry can never send the line twice.
 */
export async function sendLine(page: Page, text: string) {
  const box = composer(page);
  for (let attempt = 1; ; attempt++) {
    const last = attempt === 3;
    await waitSendable(page);
    await box.fill(text);
    try {
      await expect(box, 'the line to be in the composer').toHaveValue(text, { timeout: last ? 5_000 : 1_000 });
    } catch (e) {
      if (last) throw e;
      retried(text, attempt, 'the fill did not reach the box');
      continue;
    }
    await box.press('Enter');
    try {
      await expect(box, `the composer to take “${text}”`).toHaveValue('', { timeout: last ? 5_000 : 2_000 });
      return;
    } catch (e) {
      if (last) throw e;
      retried(text, attempt, 'Enter left the line in the box');
    }
  }
}

/** A retry is a pass, but one worth seeing on the run's page. */
function retried(text: string, attempt: number, why: string) {
  console.log(`::warning title=Composer line retried::“${text}” attempt ${attempt}: ${why}`);
}
