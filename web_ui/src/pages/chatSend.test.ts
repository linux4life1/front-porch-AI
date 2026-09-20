// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Guard: a failed /api/chat/send must never swallow the user's typed line. The
// composer clears its box before the POST, so if this leaf lost the text (or
// rethrew into a discarded promise) the message would be gone with no error.

import { describe, expect, it } from 'vitest';
import { ApiError } from '../api/client';
import { describeSendFailure, postChatSend } from './chatSend';

describe('postChatSend', () => {
  it('posts the line and reports success', async () => {
    const calls: { path: string; body: unknown }[] = [];
    const out = await postChatSend('hello there', async (path, body) => {
      calls.push({ path, body });
      return {};
    });
    expect(out).toEqual({ ok: true });
    expect(calls).toEqual([
      { path: '/api/chat/send', body: { text: 'hello there' } },
    ]);
  });

  it('posts imageBase64 when a photo is attached', async () => {
    const calls: { path: string; body: unknown }[] = [];
    const out = await postChatSend(
      'look',
      async (path, body) => {
        calls.push({ path, body });
        return {};
      },
      'abc123',
    );
    expect(out).toEqual({ ok: true });
    expect(calls).toEqual([
      { path: '/api/chat/send', body: { text: 'look', imageBase64: 'abc123' } },
    ]);
  });

  it('hands the typed text back when the network drops', async () => {
    const out = await postChatSend('a long message I do not want to retype', () =>
      Promise.reject(new TypeError('Failed to fetch')),
    );
    expect(out.ok).toBe(false);
    if (out.ok) return;
    expect(out.text).toBe('a long message I do not want to retype');
    expect(out.message).toContain("Couldn't reach Front Porch AI");
  });

  it('hands the typed text back when the session is gone', async () => {
    const out = await postChatSend('still mine', () =>
      Promise.reject(new ApiError(401, 'unauthorized', {})),
    );
    expect(out.ok).toBe(false);
    if (out.ok) return;
    expect(out.text).toBe('still mine');
    expect(out.message).toContain('session has expired');
  });

  it('never rethrows, so a discarded promise cannot strand a rejection', async () => {
    await expect(
      postChatSend('x', () => Promise.reject(new Error('boom'))),
    ).resolves.toMatchObject({ ok: false });
  });
});

describe('describeSendFailure', () => {
  it('quotes the server reason for a rejected message', () => {
    expect(describeSendFailure(new ApiError(400, 'text is required', {}))).toContain(
      'text is required',
    );
  });

  it('points at the desktop app for a server-side fault', () => {
    const msg = describeSendFailure(new ApiError(500, 'engine offline', {}));
    expect(msg).toContain('engine offline');
    expect(msg).toContain('Try again');
  });

  it('never leaks a bare status code as the whole message', () => {
    expect(describeSendFailure(new TypeError('Load failed'))).not.toContain('Load failed');
  });
});
