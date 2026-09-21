// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The composer clears its box the instant you hit Send, so by the time the POST
// leaves the phone this module is holding the ONLY copy of what you typed. It
// therefore never rethrows: a failed send comes back as an outcome that carries
// the text plus a plain-English reason, and ChatPage puts both on screen.

import { ApiError, api } from '../api/client';

export type SendOutcome =
  | { ok: true }
  | { ok: false; text: string; message: string };

/** Plain-English reason a send failed, written for someone who has never seen a
 *  status code. Every branch ends in something the user can actually do. */
export function describeSendFailure(e: unknown): string {
  if (e instanceof ApiError) {
    if (e.status === 401 || e.status === 403) {
      return 'Your web session has expired. Sign in again on this device, then tap Try again.';
    }
    if (e.status >= 500) {
      return `Front Porch AI ran into a problem on your computer (${e.message}). Check it is still running, then tap Try again.`;
    }
    return `Front Porch AI would not accept that message: ${e.message}`;
  }
  return "Couldn't reach Front Porch AI. Check the app is still open on your computer and that this device is still on the same network, then tap Try again.";
}

/** POST one line of chat. Returns `{ok:true}` when it landed, and otherwise the
 *  untouched text so the caller can show it back to the user. */
export async function postChatSend(
  text: string,
  post: (path: string, body: unknown) => Promise<unknown> = (p, b) =>
    api.post(p, b),
  imageBase64?: string,
): Promise<SendOutcome> {
  try {
    const body: { text: string; imageBase64?: string } = { text };
    if (imageBase64) body.imageBase64 = imageBase64;
    await post('/api/chat/send', body);
    return { ok: true };
  } catch (e) {
    return { ok: false, text, message: describeSendFailure(e) };
  }
}
