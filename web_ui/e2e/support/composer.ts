// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Typing a line into the chat composer the way a person does: only once the
// composer will take it, and checking that it did. See
// docs/design/known-flakes.md ("Director Mode journey: the line never sent").

import type { Page } from "@playwright/test";
import { expect } from "./fixtures";

const composer = (page: Page) => page.locator("textarea.composer-input");

type ChatState = {
  isGenerating?: boolean;
  isSettlingTurn?: boolean;
  isSendWaitingOnSettle?: boolean;
  isLoadingSession?: boolean;
  guestActivity?: { busy?: boolean };
  director?: { narrating?: boolean };
};

/** Every reason the host would still refuse a line, by name, for the timeout. */
function busyReasons(s: ChatState): string[] {
  const reasons: string[] = [];
  if (s.isGenerating) reasons.push("generating");
  if (s.isSettlingTurn) reasons.push("settling the turn");
  if (s.isSendWaitingOnSettle) reasons.push("a send waiting on the settle");
  if (s.isLoadingSession) reasons.push("opening the chat");
  if (s.guestActivity?.busy) reasons.push("a guest busy");
  if (s.director?.narrating) reasons.push("narrating");
  return reasons;
}

/**
 * The chat will take a line now, on both ends. The web twin of the Flutter
 * driver's `waitSendable()` (integration_test/support/chat_driver.dart).
 *
 * The host first: no reply, settle, chat still opening, busy guest or
 * narrator beat, the refusals `/api/chat/state` exposes (a guest entrance
 * in flight is refused too but is not in the snapshot; it would surface as
 * a 409 the fixtures record). Then the page, checked last
 * because it learns the turn is over from a socket event after the host
 * does: the composer shows Send rather than Stop. While it shows Stop its
 * `isGenerating` is true and Enter keeps the line in the box unsent, by
 * design, so a test that types in that window loses its line silently.
 */
export async function waitSendable(page: Page, timeout = 60_000) {
  await expect
    .poll(
      async () => {
        const s = (await (
          await page.request.get("/api/chat/state")
        ).json()) as ChatState;
        return busyReasons(s);
      },
      {
        timeout,
        message:
          "the host to finish its turn (the list is what it is still doing)",
      },
    )
    .toEqual([]);
  const button = page.locator(".chat-input button.primary");
  await expect(
    button.filter({ hasText: "Stop" }),
    "the page to show the turn is over",
  ).toHaveCount(0, { timeout });
  await expect(button.filter({ hasText: "Send" })).toBeVisible({ timeout });
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
      await expect(box, "the line to be in the composer").toHaveValue(text, {
        timeout: last ? 5_000 : 1_000,
      });
    } catch (e) {
      if (last) throw e;
      retried(
        text,
        attempt,
        "the fill did not reach the box",
        await box.inputValue(),
      );
      continue;
    }
    await box.press("Enter");
    try {
      await expect(box, `the composer to take “${text}”`).toHaveValue("", {
        timeout: last ? 5_000 : 2_000,
      });
      return;
    } catch (e) {
      if (last) throw e;
      retried(
        text,
        attempt,
        "Enter left the line in the box",
        await box.inputValue(),
      );
    }
  }
}

/**
 * A retry is a pass, but one worth seeing on the run's page, with what the
 * box held: the evidence that says whether a lost fill was WebKit dropping
 * the text or the app changing it.
 */
function retried(text: string, attempt: number, why: string, held: string) {
  console.log(
    `::warning title=Composer line retried::“${text}” attempt ${attempt}: ${why}; the box held “${held}”`,
  );
}
