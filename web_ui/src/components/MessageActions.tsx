// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Per-message action toolbar (swipe / regenerate / continue / edit / fork /
// delete / speak). Extracted from ChatPage to keep that page under the file-size
// cap.

import { FormEvent, useState } from 'react';
import { api } from '../api/client';
import { type Message } from './chatTypes';
import { SpeakButton } from './VoiceControls';
import { VariantPickerModal } from './VariantPickerModal';

export function MessageActions({
  m,
  isLast,
  busy,
  canSpeak,
  greetCount = 1,
  greetingIndex = 0,
  userHasReplied = false,
  onSwipe,
  onRegenerate,
  onContinue,
  onFork,
  onEdit,
  onDelete,
  onVariantPicked,
}: {
  m: Message;
  isLast: boolean;
  busy: boolean;
  canSpeak: boolean;
  greetCount?: number;
  greetingIndex?: number;
  userHasReplied?: boolean;
  onSwipe: (index: number, direction: number, critique?: string) => void;
  onRegenerate: (critique?: string) => void;
  onContinue: () => void;
  onFork: () => void;
  onEdit: () => void;
  onDelete: () => void;
  onVariantPicked?: () => void;
}) {
  const count = m.swipeCount ?? 1;
  const idx = (m.swipeIndex ?? 0) + 1;
  const [picker, setPicker] = useState(false);
  const [critiqueOpen, setCritiqueOpen] = useState(false);
  const [draft, setDraft] = useState('');
  // Generated-image messages carry no regenerable text — hide the text-gen
  // actions for them (desktop bubble parity).
  const isImage = !!m.image;
  const hasSwipeVariants = !m.isUser && !isImage && count > 1;
  // Pre-existing regen swipes on the opening message are variants, not
  // card greets — same rule as desktop usesGreetingPicker.
  const isGreet =
    !m.isUser &&
    m.index === 0 &&
    greetCount > 1 &&
    !hasSwipeVariants &&
    !userHasReplied;
  const canSwipe =
    !m.isUser &&
    !isImage &&
    (hasSwipeVariants || isGreet || (isLast && m.index !== 0));
  const showPicker = isGreet || hasSwipeVariants;
  const cycleGreet = (dir: number) => {
    const next = (greetingIndex + dir + greetCount) % greetCount;
    void api
      .post('/api/chat/select-variant', { messageIndex: 0, variantIndex: next })
      .then(() => onVariantPicked?.());
  };
  const openCritique = () => {
    setDraft('');
    setCritiqueOpen(true);
  };
  const closeCritique = () => setCritiqueOpen(false);
  const confirmCritique = (e?: FormEvent) => {
    e?.preventDefault();
    setCritiqueOpen(false);
    onRegenerate(draft);
  };
  return (
    <>
      <div className={`msg-actions${m.isUser ? ' user' : ''}`}>
      {canSwipe && (
        <span className="swipe">
          <button className="icon-btn" title="Previous" disabled={busy}
            onClick={() => isGreet ? cycleGreet(-1) : onSwipe(m.index, -1)}>◀</button>
          <span className="swipe-count">
            {isGreet ? `${greetingIndex + 1}/${greetCount}` : `${idx}/${Math.max(count, idx)}`}
          </span>
          <button className="icon-btn" title={isGreet ? 'Next greet' : 'Next / new swipe'} disabled={busy}
            onClick={() => isGreet ? cycleGreet(1) : onSwipe(m.index, 1)}>▶</button>
        </span>
      )}
      {showPicker && (
        <button
          className="icon-btn"
          title={isGreet ? 'Select greet' : 'Select variant'}
          disabled={busy}
          onClick={() => setPicker(true)}
        >
          ☰
        </button>
      )}
      {!m.isUser && !isImage && isLast && m.index !== 0 && (
        <>
          <button className="icon-btn" title="Regenerate" disabled={busy} onClick={openCritique}>⟳</button>
          <button className="icon-btn" title="Continue" disabled={busy} onClick={onContinue}>⏩</button>
        </>
      )}
      {!m.isUser && !isImage && isLast && m.index === 0 && (
        <button className="icon-btn" title="Continue" disabled={busy} onClick={onContinue}>⏩</button>
      )}
      {/* When the last message is the user's (e.g. the AI reply was deleted),
          offer a Generate-reply button — same backend regenerate() call, which
          now generates a fresh response from the trailing prompt. Desktop parity
          for #85. */}
      {m.isUser && isLast && (
        <button className="icon-btn" title="Generate reply" disabled={busy} onClick={() => onRegenerate()}>⟳</button>
      )}
      {canSpeak && !m.isUser && m.text.trim() !== '' && <SpeakButton text={m.text} />}
      {m.sender !== 'System' && (
        <button className="icon-btn" title="Fork from here" disabled={busy} onClick={onFork}>⑂</button>
      )}
      <button className="icon-btn" title="Edit" disabled={busy} onClick={onEdit}>✎</button>
      <button className="icon-btn" title="Delete" disabled={busy} onClick={onDelete}>🗑</button>
      </div>
      {picker && (
        <VariantPickerModal
          messageIndex={m.index}
          onClose={() => setPicker(false)}
          onPicked={() => {
            setPicker(false);
            onVariantPicked?.();
          }}
        />
      )}
      {critiqueOpen && (
        <div className="drawer-backdrop center" onClick={closeCritique}>
          <form
            className="modal regen-critique-modal"
            data-testid="regen-critique-dialog"
            onClick={(e) => e.stopPropagation()}
            onSubmit={confirmCritique}
          >
            <div className="drawer-head">
              <span>Regenerate</span>
              <button type="button" className="link-btn" onClick={closeCritique} aria-label="Close">
                ×
              </button>
            </div>
            <p className="muted small">Optional note for this swipe. Leave blank to just try again.</p>
            <input
              className="regen-critique"
              data-testid="regen-critique-field"
              type="text"
              maxLength={500}
              autoFocus
              value={draft}
              onChange={(e) => setDraft(e.target.value)}
              placeholder="why this take was wrong — optional"
            />
            <div className="regen-critique-actions">
              <button type="button" className="link-btn" onClick={closeCritique}>Cancel</button>
              <button type="submit">Regenerate</button>
            </div>
          </form>
        </div>
      )}
    </>
  );
}
