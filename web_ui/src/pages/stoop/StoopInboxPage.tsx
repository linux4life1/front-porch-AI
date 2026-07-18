// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Stoop inbox — the user's thread with the moderation team. Messages arrive
// live over the relay socket (with the mod typing indicator); opening the
// page clears the unread badge and marks the thread read, exactly like the
// desktop inbox.

import { useEffect, useRef, useState } from 'react';
import { stoop, stoopErrorText } from '../../stoop/stoopApi';
import { useStoop } from '../../stoop/StoopContext';
import type { StoopMessage } from '../../stoop/stoopTypes';

export function StoopInboxPage() {
  const { setInboxOpen, subscribe, sendTyping } = useStoop();
  const [messages, setMessages] = useState<StoopMessage[]>([]);
  const [draft, setDraft] = useState('');
  const [modTyping, setModTyping] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const endRef = useRef<HTMLDivElement | null>(null);
  const typingTimer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);

  useEffect(() => {
    setInboxOpen(true);
    stoop
      .messages()
      .then((r) => setMessages(r.items))
      .catch((e) => setError(stoopErrorText(e)));
    const unsub = subscribe((e) => {
      if (e.type === 'message') {
        setMessages((prev) =>
          prev.some((m) => m.id === e.message.id) ? prev : [...prev, e.message],
        );
        setModTyping(false);
      } else if (e.type === 'typing' && e.fromMod) {
        setModTyping(e.isTyping);
      }
    });
    return () => {
      unsub();
      setInboxOpen(false);
    };
  }, [setInboxOpen, subscribe]);

  useEffect(() => {
    endRef.current?.scrollIntoView({ block: 'end' });
  }, [messages.length, modTyping]);

  const onDraft = (value: string) => {
    setDraft(value);
    sendTyping(true);
    if (typingTimer.current) clearTimeout(typingTimer.current);
    typingTimer.current = setTimeout(() => sendTyping(false), 2000);
  };

  const send = async () => {
    const body = draft.trim();
    if (!body || busy) return;
    setBusy(true);
    setError('');
    try {
      const sent = await stoop.sendMessage(body);
      setMessages((prev) =>
        prev.some((m) => m.id === sent.id) ? prev : [...prev, sent],
      );
      setDraft('');
      sendTyping(false);
    } catch (e) {
      setError(stoopErrorText(e));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="stoop-inbox">
      <p className="muted">
        Your private thread with The Stoop's moderation team — replies about your
        uploads and reports land here.
      </p>
      <div className="stoop-thread">
        {messages.map((m) => (
          <div key={m.id} className={m.fromMod ? 'stoop-msg mod' : 'stoop-msg me'}>
            {m.character && <span className="stoop-msg-card">re: {m.character.name}</span>}
            <p>{m.body}</p>
            <span className="stoop-msg-time muted">
              {new Date(m.createdAt).toLocaleString()}
            </span>
          </div>
        ))}
        {modTyping && <div className="stoop-msg mod stoop-typing">…</div>}
        {messages.length === 0 && !error && (
          <p className="muted">No messages yet.</p>
        )}
        <div ref={endRef} />
      </div>
      {error && <p className="error">{error}</p>}
      <div className="stoop-composer">
        <textarea
          rows={2}
          placeholder="Write a message…"
          value={draft}
          onChange={(e) => onDraft(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter' && !e.shiftKey) {
              e.preventDefault();
              void send();
            }
          }}
        />
        <button className="primary" disabled={busy || !draft.trim()} onClick={send}>
          Send
        </button>
      </div>
    </div>
  );
}
