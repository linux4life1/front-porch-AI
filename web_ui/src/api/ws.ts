// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// WebSocket client for the rewritten server's single multiplexed channel
// (/api/ws). The HttpOnly session cookie authenticates the upgrade — no token
// in the URL. Reconnects with backoff so a phone waking from sleep re-syncs.

export type WsEvent = {
  event: string;
  data?: string;
  // Extra fields carried by non-token events (e.g. chargen_done id/name,
  // chargen_error error).
  id?: string | number;
  name?: string;
  error?: string;
  // `processing` event (Realism + Objective engine overlay): which engine is
  // running + the live eval stream text.
  active?: boolean;
  realism?: boolean;
  objective?: boolean;
  greeting?: boolean;
  verifying?: boolean;
  text?: string;
  // Story audiobook compile events (story_audiobook_status / _ready / _error).
  progress?: number;
  status?: string;
  generating?: boolean;
};

export class ChatSocket {
  private ws: WebSocket | null = null;
  private closed = false;
  private backoff = 500;
  private readonly onEvent: (e: WsEvent) => void;

  constructor(onEvent: (e: WsEvent) => void) {
    this.onEvent = onEvent;
  }

  connect(): void {
    this.closed = false;
    const proto = location.protocol === 'https:' ? 'wss' : 'ws';
    const url = `${proto}://${location.host}/api/ws`;
    const ws = new WebSocket(url);
    this.ws = ws;

    ws.onopen = () => {
      this.backoff = 500;
    };
    ws.onmessage = (msg) => {
      try {
        this.onEvent(JSON.parse(msg.data as string) as WsEvent);
      } catch {
        /* ignore malformed frame */
      }
    };
    ws.onclose = () => {
      this.ws = null;
      if (!this.closed) this.scheduleReconnect();
    };
    ws.onerror = () => ws.close();
  }

  private scheduleReconnect(): void {
    const delay = Math.min(this.backoff, 10000);
    this.backoff = delay * 2;
    setTimeout(() => {
      if (!this.closed) this.connect();
    }, delay);
  }

  ping(): void {
    this.ws?.send(JSON.stringify({ type: 'ping' }));
  }

  close(): void {
    this.closed = true;
    this.ws?.close();
    this.ws = null;
  }
}
