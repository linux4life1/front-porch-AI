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
  // `chargen_enhance_done` (AI Enhance): which character was enhanced and the
  // unsaved field proposal the client reviews before applying.
  characterId?: string;
  proposal?: unknown;
  // `chargen_greeting_*` (the creator's Greetings step): which greeting (0 is
  // the first message; `text` carries it), and on `_done` the saved greetings.
  index?: number;
  firstMessage?: string;
  alternateGreetings?: string[];
  // `world_wiki_done`: written lorebook cards, not saved until Preview.
  description?: string;
  climateEnabled?: boolean;
  biome?: unknown;
  recursiveScanning?: boolean;
  scanDepth?: number;
  tokenBudget?: number;
  entries?: unknown;
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
  // `chance_time` event (chaos): whether a Chance Time is now parked awaiting the
  // user's "accept your fate". `data` carries the pre-resolved event text.
  pending?: boolean;
  // `image_progress` event: the latest in-progress preview frame (data URL)
  // when the image backend streams one; `progress`/`generating` above carry
  // the percent and lifecycle.
  preview?: string;
  // `gen_status` event (truthful generation status, desktop status-bar
  // parity): live prompt-reading counts parsed from the managed KoboldCpp
  // console (`active` above carries the lifecycle), plus which background
  // pass (journal/growth) is holding the single local slot.
  phase?: string;
  // Seconds since prefill started. Shown when there is no measured count.
  elapsed?: number;
  busyWith?: string | null;
  // Backend-reported queue depth (oMLX) — stated neutrally, never attributed.
  queued?: number;
  promptCur?: number | null;
  promptTotal?: number | null;
  // Console lines arrive per BATCH; the server interpolates between them
  // (estFraction) and flags when the console confirmed completion.
  promptDone?: boolean;
  estFraction?: number | null;
  genCur?: number | null;
  genTotal?: number | null;
  // `speed_test` event (the Local model card's speed test): how it stands, in
  // the host's words. Read with speedTestOf (components/models/useSpeedTest).
  speedTest?: unknown;
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
      // A socket that was replaced or closed on purpose must not clear, or
      // reconnect over, the one that came after it.
      if (this.ws !== ws) return;
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
    const ws = this.ws;
    this.ws = null;
    if (!ws) return;
    // Leaving a page before its socket has connected: closing it now makes
    // Safari log "WebSocket is closed before the connection is established".
    // Let it finish connecting, then close it.
    if (ws.readyState === WebSocket.CONNECTING) {
      ws.onmessage = null;
      ws.onerror = null;
      ws.onopen = () => ws.close();
      return;
    }
    ws.close();
  }
}
