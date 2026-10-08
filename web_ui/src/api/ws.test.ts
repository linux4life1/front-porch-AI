// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { ChatSocket } from './ws';

/** The browser socket's lifecycle, driven by hand: what ChatSocket does to it is what is asserted. */
class FakeSocket {
  static CONNECTING = 0;
  static OPEN = 1;
  static made: FakeSocket[] = [];
  readyState = FakeSocket.CONNECTING;
  closeCalls = 0;
  onopen: (() => void) | null = null;
  onmessage: ((m: { data: string }) => void) | null = null;
  onclose: (() => void) | null = null;
  onerror: (() => void) | null = null;
  constructor(public url: string) { FakeSocket.made.push(this); }
  open() { this.readyState = FakeSocket.OPEN; this.onopen?.(); }
  close() { this.closeCalls++; this.readyState = 3; this.onclose?.(); }
  send() {}
}

describe('ChatSocket', () => {
  beforeEach(() => {
    FakeSocket.made = [];
    vi.stubGlobal('WebSocket', FakeSocket);
    vi.useFakeTimers();
  });
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.useRealTimers();
  });

  it('does not close a socket that is still connecting; it closes once it opens', () => {
    const socket = new ChatSocket(() => {});
    socket.connect();
    const ws = FakeSocket.made[0];

    socket.close();
    expect(ws.closeCalls).toBe(0);

    ws.open();
    expect(ws.closeCalls).toBe(1);
    vi.runAllTimers();
    expect(FakeSocket.made).toHaveLength(1);
  });

  it('closes an open socket straight away and does not reconnect', () => {
    const socket = new ChatSocket(() => {});
    socket.connect();
    const ws = FakeSocket.made[0];
    ws.open();

    socket.close();
    expect(ws.closeCalls).toBe(1);
    vi.runAllTimers();
    expect(FakeSocket.made).toHaveLength(1);
  });

  it('a socket closed on the way out does not disturb the one opened after it', () => {
    const socket = new ChatSocket(() => {});
    socket.connect();
    const first = FakeSocket.made[0];
    socket.close();
    socket.connect();
    const second = FakeSocket.made[1];
    second.open();

    first.open(); // the deferred close of the first lands now
    vi.runAllTimers();
    expect(first.closeCalls).toBe(1);
    expect(second.closeCalls).toBe(0);
    expect(FakeSocket.made).toHaveLength(2);
  });

  it('an unexpected drop reconnects', () => {
    const socket = new ChatSocket(() => {});
    socket.connect();
    const ws = FakeSocket.made[0];
    ws.open();
    ws.close();
    vi.runAllTimers();
    expect(FakeSocket.made).toHaveLength(2);
  });
});
