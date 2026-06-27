// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The scrolling chat transcript: per-message bubbles (with speaker labels in a
// multi-character scene, collapsible thinking blocks, inline edit, Realism/Needs
// chips, and the per-message action toolbar) plus the live streaming bubble.
// Extracted verbatim from ChatPage to keep that page under the file-size cap;
// every action is delegated to a callback so all chat state stays in ChatPage.

import { type RefObject } from 'react';
import { MessageContent } from './MessageContent';
import { ChipsRow } from './ChipsRow';
import { MessageActions } from './MessageActions';
import { type CastMember } from './CastBar';
import { type Message } from './chatTypes';

export function ChatMessageList({
  messages,
  castById,
  multiCast,
  lastIndex,
  busy,
  streaming,
  scrollRef,
  canSpeak,
  editIndex,
  editDraft,
  onEditDraftChange,
  onCancelEdit,
  onSaveEdit,
  onBeginEdit,
  onSwipe,
  onRegenerate,
  onContinue,
  onDelete,
  onReprocess,
  onRevert,
}: {
  messages: Message[];
  castById: Map<string, CastMember>;
  multiCast: boolean;
  lastIndex: number;
  busy: boolean;
  streaming: string;
  scrollRef: RefObject<HTMLDivElement>;
  canSpeak: boolean;
  editIndex: number | null;
  editDraft: string;
  onEditDraftChange: (v: string) => void;
  onCancelEdit: () => void;
  onSaveEdit: () => void;
  onBeginEdit: (m: Message) => void;
  onSwipe: (index: number, direction: number) => void;
  onRegenerate: () => void;
  onContinue: () => void;
  onDelete: (index: number) => void;
  onReprocess: (index: number) => void;
  onRevert: (index: number) => void;
}) {
  return (
    <div className="chat-messages" ref={scrollRef}>
      {messages.map((m) => {
        const speaker = !m.isUser && m.characterId ? castById.get(m.characterId) : undefined;
        return (
          <div key={m.index} className="msg-row">
            {multiCast && speaker && <span className="msg-speaker">{speaker.name}</span>}
            {m.hasThinking && m.thinkingContent && (
              <details className="thinking">
                <summary>💭 Thoughts</summary>
                <div className="thinking-body">{m.thinkingContent}</div>
              </details>
            )}
            {editIndex === m.index ? (
              <div className="msg-edit">
                <textarea
                  value={editDraft}
                  onChange={(e) => onEditDraftChange(e.target.value)}
                  rows={4}
                  autoFocus
                />
                <div className="msg-edit-actions">
                  <button onClick={onCancelEdit}>Cancel</button>
                  <button className="primary" onClick={onSaveEdit}>Save</button>
                </div>
              </div>
            ) : (
              <>
                <div className={m.isUser ? 'bubble user' : 'bubble ai'}><MessageContent text={m.text} /></div>
                {!m.isUser && m.chips && (
                  <ChipsRow
                    chips={m.chips}
                    isLast={m.index === lastIndex}
                    busy={busy}
                    onReprocess={() => onReprocess(m.index)}
                    onRevert={() => onRevert(m.index)}
                  />
                )}
                <MessageActions
                  m={m}
                  isLast={m.index === lastIndex}
                  busy={busy}
                  canSpeak={canSpeak}
                  onSwipe={onSwipe}
                  onRegenerate={onRegenerate}
                  onContinue={onContinue}
                  onEdit={() => onBeginEdit(m)}
                  onDelete={() => onDelete(m.index)}
                />
              </>
            )}
          </div>
        );
      })}
      {streaming && (() => {
        // Separate a (possibly still-open) <think> block so reasoning streams
        // into a muted "thinking…" area and the reply shows below — mirrors how
        // the finished message renders its collapsible thinking block.
        const open = streaming.indexOf('<think>');
        let thinking = '';
        let rest = streaming;
        if (open !== -1) {
          const after = streaming.slice(open + 7);
          const close = after.indexOf('</think>');
          thinking = close === -1 ? after : after.slice(0, close);
          rest = streaming.slice(0, open) + (close === -1 ? '' : after.slice(close + 8));
        }
        return (
          <div className="bubble ai streaming" aria-live="polite">
            {thinking.trim() && (
              <div className="streaming-think">
                <span className="muted small">💭 thinking…</span>
                <div className="streaming-think-body">{thinking}</div>
              </div>
            )}
            {rest && <MessageContent text={rest} />}
          </div>
        );
      })()}
    </div>
  );
}
