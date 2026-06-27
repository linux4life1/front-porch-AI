// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Per-message action toolbar (swipe / regenerate / continue / edit / delete /
// speak). Extracted verbatim from ChatPage to keep that page under the file-size
// cap.

import { type Message } from './chatTypes';
import { SpeakButton } from './VoiceControls';

export function MessageActions({
  m,
  isLast,
  busy,
  canSpeak,
  onSwipe,
  onRegenerate,
  onContinue,
  onEdit,
  onDelete,
}: {
  m: Message;
  isLast: boolean;
  busy: boolean;
  canSpeak: boolean;
  onSwipe: (index: number, direction: number) => void;
  onRegenerate: () => void;
  onContinue: () => void;
  onEdit: () => void;
  onDelete: () => void;
}) {
  const count = m.swipeCount ?? 1;
  const idx = (m.swipeIndex ?? 0) + 1;
  const canSwipe = !m.isUser && (count > 1 || isLast);
  return (
    <div className={`msg-actions${m.isUser ? ' user' : ''}`}>
      {canSwipe && (
        <span className="swipe">
          <button className="icon-btn" title="Previous" disabled={busy}
            onClick={() => onSwipe(m.index, -1)}>◀</button>
          <span className="swipe-count">{idx}/{Math.max(count, idx)}</span>
          <button className="icon-btn" title="Next / new swipe" disabled={busy}
            onClick={() => onSwipe(m.index, 1)}>▶</button>
        </span>
      )}
      {!m.isUser && isLast && (
        <>
          <button className="icon-btn" title="Regenerate" disabled={busy} onClick={onRegenerate}>⟳</button>
          <button className="icon-btn" title="Continue" disabled={busy} onClick={onContinue}>⏩</button>
        </>
      )}
      {canSpeak && !m.isUser && m.text.trim() !== '' && <SpeakButton text={m.text} />}
      <button className="icon-btn" title="Edit" disabled={busy} onClick={onEdit}>✎</button>
      <button className="icon-btn" title="Delete" disabled={busy} onClick={onDelete}>🗑</button>
    </div>
  );
}
