// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The "does my model support tool calling?" pill in the chat insight panel
// (drawer on phone, sidebar on desktop). Mirrors the desktop sidebar pill.

import { useEffect, useState } from 'react';
import { api } from '../api/client';

/** The current model's tool-calling verdict, as the chat state sends it. */
export type ToolSupport = {
  state: string;
  testing: boolean;
  preferText?: boolean;
  paused?: boolean;
  checked?: boolean;
  /** The answer was kept from an earlier run, not asked just now. */
  saved?: boolean;
};

/** Under a settled answer that was kept from an earlier run. */
const SAVED_DETAIL = 'Saved from an earlier test. Click to ask again.';

/**
 * "Does my model support tool calling?" pill — desktop sidebar parity.
 * Green = native tool calls work (Realism/Journal/Growth use them), amber =
 * text fallback, neutral = not tested yet. Click to retest the live model;
 * the server also retests automatically on model/backend switches.
 */
export function ToolCallingPill({ support }: { support?: ToolSupport }) {
  const [busy, setBusy] = useState(false);
  const [local, setLocal] = useState(support);
  useEffect(() => setLocal(support), [support]);
  if (!local) return null;
  const testing = busy || local.testing;
  const s = local.state;
  const skipped = s === 'supported' && !!local.preferText;
  const paused = !!local.paused;
  const saved = !!local.saved;
  const tone = testing
    ? 'busy'
    : paused || skipped
      ? 'warn'
      : s === 'supported'
        ? 'ok'
        : s === 'unsupported'
          ? 'warn'
          : 'idle';
  const label = testing
    ? 'Tool calling: testing…'
    : paused
      ? 'Tool calling: paused this run'
      : skipped
        ? 'Tool calling: supported — using JSON'
        : s === 'supported'
          ? 'Tool calling: supported'
          : s === 'unsupported'
            ? 'Tool calling: not supported'
            : 'Tool calling: not tested';
  const detail = testing
    ? 'Asking the model for a tool call'
    : paused
      ? 'Empty answers this session — click to retry'
      : skipped
        ? 'You turned native tool calls off in Generation settings'
        : s === 'supported'
          ? saved
            ? SAVED_DETAIL
            : 'Realism, Journal & Growth use native tool calls'
          : s === 'unsupported'
            ? saved
              ? SAVED_DETAIL
              : 'Using the text fallback — still works'
            : 'Click to test the current model';
  const retest = async () => {
    setBusy(true);
    try {
      setLocal(await api.post<ToolSupport>('/api/chat/tool-test', {}));
    } catch {
      /* verdict refreshes with the next chat_updated anyway */
    }
    setBusy(false);
  };
  return (
    <button
      className={`tool-pill tool-pill-${tone}`}
      onClick={retest}
      disabled={testing}
      title="Whether the current model can answer engine evaluations (Realism, Journal, Growth Rings) with native tool calls. Without it a text fallback is used — chats still work. Click to retest; retests also run when you switch models."
    >
      <span className="tool-pill-dot" />
      <span className="tool-pill-text">
        <strong>{label}</strong>
        <span className="muted small">{detail}</span>
      </span>
      <span className="tool-pill-retest">↻</span>
    </button>
  );
}
