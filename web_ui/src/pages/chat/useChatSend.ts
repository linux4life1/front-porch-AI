// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Send / continue / regen (and the sibling transcript mutations). `postChatSend`
// stays in chatSend.ts — this hook is the page wiring around it.

import { useCallback, useState } from 'react';
import { api } from '../../api/client';
import { type ChatThemeOverrides, type Message } from '../../components/chatTypes';
import { joinMessageEdit } from '../../components/messageEdit';
import { postChatSend } from '../chatSend';
import { describeActionFailure } from './chatActionError';

export function useChatSend(refresh: () => Promise<void>) {
  // A send that never reached the desktop: the exact text the user typed (the
  // composer already threw its copy away) plus a plain-English reason.
  const [sendError, setSendError] = useState<
    { text: string; message: string; retrying: boolean } | null
  >(null);
  // Fullscreen message editor — index + original text while the modal is open.
  const [editTarget, setEditTarget] = useState<{ index: number; text: string } | null>(null);
  // Director-redo (reprocess Needs) — only the target message index lives here;
  // the modal owns its own critique/busy/error state.
  const [reprocessIndex, setReprocessIndex] = useState<number | null>(null);

  // Cast actions and the composer share one send path (both route through
  // ChatService server-side, so behavior matches the desktop). The composer has
  // already emptied its box by the time we're called, so a failed POST must
  // hand the typed text back to the user (sendError) instead of dropping it —
  // on a phone over Tailscale a blipped uplink used to eat the message with no
  // trace at all. Never rethrows, so the `void sendMessage(...)` call sites
  // (CastBar commands, the /join picker) can't strand a rejected promise.
  const sendMessage = useCallback(async (text: string, imageBase64?: string) => {
    const t = text.trim();
    if (!t && !imageBase64) return;
    const outcome = await postChatSend(t, (p, b) => api.post(p, b), imageBase64);
    if (!outcome.ok) {
      setSendError({ text: outcome.text, message: outcome.message, retrying: false });
      return;
    }
    setSendError(null);
    // The line is in ChatService now — a failed refresh loses nothing (the WS
    // `chat_updated` burst re-renders anyway), so it must NOT offer a resend.
    await refresh().catch((e) => console.warn('[chat] refresh after send failed', e));
  }, [refresh]);

  // Resend the message the last failure handed back (one tap, no retyping).
  const retrySend = async () => {
    const failed = sendError;
    if (!failed || failed.retrying) return;
    setSendError({ ...failed, retrying: true });
    await sendMessage(failed.text);
  };

  // A transcript action the desktop refused or never received. Shown as a
  // dismissible banner; before this, the rejected tap simply did nothing.
  const [actionError, setActionError] = useState<string | null>(null);
  const failed = useCallback((what: string, e: unknown) => {
    console.warn(`[chat] ${what} failed`, e);
    setActionError(describeActionFailure(what, e));
  }, []);

  // The transcript handlers are useCallback-stable so token/processing WS
  // frames (which re-render this page many times a second during a turn)
  // never invalidate the memoized transcript rows — see TranscriptRows.
  const regenerate = useCallback(async (
    critique?: string,
    lookup?: { source: 'web' | 'wiki'; query: string },
  ) => {
    const trimmed = (critique ?? '').trim();
    const query = lookup?.query.trim() ?? '';
    const body: Record<string, string> = {};
    if (trimmed) body.critique = trimmed;
    if (query && lookup?.source === 'web') body.webQuery = query;
    if (query && lookup?.source === 'wiki') body.wikiQuery = query;
    try {
      await api.post(
        '/api/chat/regenerate',
        Object.keys(body).length ? body : undefined,
      );
      await refresh();
    } catch (e) {
      failed('regenerate that reply', e);
    }
  }, [refresh, failed]);
  const continueGen = useCallback(async () => {
    try {
      await api.post('/api/chat/continue');
      await refresh();
    } catch (e) {
      failed('continue that reply', e);
    }
  }, [refresh, failed]);
  const fork = useCallback(async (index: number) => {
    if (
      !window.confirm(
        `Create a new branch from message #${index + 1}?\n\nThe current chat will remain unchanged. A new conversation will be created with messages up to this point.`,
      )
    ) {
      return;
    }
    try {
      await api.post('/api/chat/fork', { index });
      await refresh();
    } catch (e) {
      failed('branch the chat from there', e);
    }
  }, [refresh, failed]);
  const swipe = useCallback(async (
    messageIndex: number,
    direction: number,
    critique?: string,
  ) => {
    const trimmed = (critique ?? '').trim();
    try {
      await api.post('/api/chat/swipe', {
        messageIndex,
        direction,
        ...(trimmed ? { critique: trimmed } : {}),
      });
      await refresh();
    } catch (e) {
      failed('swipe that reply', e);
    }
  }, [refresh, failed]);
  const del = useCallback(async (index: number) => {
    if (
      !window.confirm(
        "This can't be undone. Are you sure you want to delete this message?",
      )
    ) {
      return;
    }
    try {
      await api.post('/api/chat/delete', { index });
      await refresh();
    } catch (e) {
      failed('delete that message', e);
    }
  }, [refresh, failed]);
  // `text` arrives think-stripped; rejoin the reasoning so the editor shows
  // it and Save does not erase it from the stored message.
  const beginEdit = useCallback((m: Message) => {
    setEditTarget({ index: m.index, text: joinMessageEdit(m.thinkingContent ?? '', m.text) });
  }, []);
  // The editor stays open until the desktop has the new text: on failure this
  // throws a plain-English Error the modal shows above the user's draft.
  const saveEdit = async (text: string) => {
    if (!editTarget) return;
    try {
      await api.post('/api/chat/edit', { index: editTarget.index, text });
    } catch (e) {
      console.warn('[chat] edit failed', e);
      throw new Error(describeActionFailure('save your edit', e));
    }
    setEditTarget(null);
    await refresh();
  };
  const saveAuthorNote = async (note: string, strength: number) => {
    try {
      await api.post('/api/chat/author-note', { authorNote: note, strength });
      await refresh();
    } catch (e) {
      failed("save the author's note", e);
    }
  };
  const saveTheme = async (overrides: ChatThemeOverrides) => {
    try {
      await api.post('/api/chat/theme-overrides', overrides);
      await refresh();
    } catch (e) {
      failed('save the chat theme', e);
    }
  };

  // Director redo: reprocess a message's Needs deltas with a written critique
  // (throws on failure so the modal can surface the error), or revert.
  const submitReprocess = async (critique: string, onlyNeeds: string[]) => {
    if (reprocessIndex === null) return;
    // 'needs' omitted when nothing was selected — the server treats a missing
    // key as "all needs", which is also what older builds send.
    await api.post('/api/chat/reprocess-needs', {
      index: reprocessIndex,
      critique,
      ...(onlyNeeds.length > 0 ? { needs: onlyNeeds } : {}),
    });
    await refresh();
    setReprocessIndex(null);
  };
  const revertNeeds = useCallback(async (index: number) => {
    try {
      await api.post('/api/chat/revert-needs-reprocess', { index });
      await refresh();
    } catch (e) {
      failed('undo that redo', e);
    }
  }, [refresh, failed]);

  return {
    sendError,
    setSendError,
    actionError,
    setActionError,
    reportActionFailure: failed,
    editTarget,
    setEditTarget,
    reprocessIndex,
    setReprocessIndex,
    sendMessage,
    retrySend,
    regenerate,
    continueGen,
    fork,
    swipe,
    del,
    beginEdit,
    saveEdit,
    saveAuthorNote,
    saveTheme,
    submitReprocess,
    revertNeeds,
  };
}
