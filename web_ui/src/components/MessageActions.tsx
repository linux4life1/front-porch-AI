// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Per-message action toolbar (swipe / regenerate / continue / edit / fork /
// delete / speak). Extracted from ChatPage to keep that page under the file-size
// cap.

import { FormEvent, KeyboardEvent, useState } from 'react';
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
  lookupWeb = false,
  lookupWiki = false,
  onContinue,
  onFork,
  onEdit,
  onDelete,
  onVariantPicked,
  onActionFailed,
}: {
  m: Message;
  isLast: boolean;
  busy: boolean;
  canSpeak: boolean;
  greetCount?: number;
  greetingIndex?: number;
  userHasReplied?: boolean;
  onSwipe: (index: number, direction: number, critique?: string) => void;
  onRegenerate: (
    critique?: string,
    lookup?: { source: 'web' | 'wiki'; query: string },
  ) => void;
  /** Porch Life web search is on. Hidden entirely when false. */
  lookupWeb?: boolean;
  /** This chat has a wiki. Shown disabled when web is on and this is false. */
  lookupWiki?: boolean;
  onContinue: () => void;
  onFork: () => void;
  onEdit: () => void;
  onDelete: () => void;
  onVariantPicked?: () => void;
  onActionFailed?: (what: string, e: unknown) => void;
}) {
  const count = m.swipeCount ?? 1;
  const idx = (m.swipeIndex ?? 0) + 1;
  const [picker, setPicker] = useState(false);
  const [critiqueOpen, setCritiqueOpen] = useState(false);
  const [draft, setDraft] = useState('');
  const [lookupQuery, setLookupQuery] = useState('');
  const [lookupIsWiki, setLookupIsWiki] = useState(false);
  const showLookup = lookupWeb || lookupWiki;
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
      .then(() => onVariantPicked?.())
      .catch((e) => onActionFailed?.('switch greetings', e));
  };
  const openCritique = () => {
    setDraft('');
    setLookupQuery('');
    setLookupIsWiki(!lookupWeb && lookupWiki);
    setCritiqueOpen(true);
  };
  const closeCritique = () => setCritiqueOpen(false);
  const confirmCritique = (e?: FormEvent) => {
    e?.preventDefault();
    const query = lookupQuery.trim();
    setCritiqueOpen(false);
    if (query && lookupIsWiki && lookupWiki) {
      onRegenerate(draft, { source: 'wiki', query });
      return;
    }
    if (query && !lookupIsWiki && lookupWeb) {
      onRegenerate(draft, { source: 'web', query });
      return;
    }
    onRegenerate(draft);
  };
  // Plain Enter stays a new line in the note; Ctrl/⌘+Enter regenerates
  // (desktop dialog parity). Numpad Enter also reports key 'Enter'.
  const critiqueKey = (e: KeyboardEvent<HTMLFormElement>) => {
    if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) {
      e.preventDefault();
      confirmCritique();
    }
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
      <button className="icon-btn" title="Delete" disabled={busy && isLast} onClick={onDelete}>🗑</button>
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
            onKeyDown={critiqueKey}
          >
            <div className="drawer-head">
              <span>Regenerate</span>
              <button type="button" className="link-btn" onClick={closeCritique} aria-label="Close">
                ×
              </button>
            </div>
            <p className="muted small">Optional note for this swipe. Leave blank to just try again.</p>
            <textarea
              className="regen-critique"
              data-testid="regen-critique-field"
              rows={3}
              maxLength={500}
              autoFocus
              value={draft}
              onChange={(e) => setDraft(e.target.value)}
              placeholder="why this take was wrong — optional"
            />
            {showLookup && (
              <div className="regen-lookup">
                {lookupWeb ? (
                  <div className="regen-lookup-toggle" role="group" aria-label="Where to look">
                    <button
                      type="button"
                      data-testid="regen-lookup-web"
                      aria-pressed={!lookupIsWiki}
                      onClick={() => setLookupIsWiki(false)}
                    >
                      Web
                    </button>
                    <button
                      type="button"
                      data-testid="regen-lookup-wiki"
                      aria-pressed={lookupIsWiki && lookupWiki}
                      disabled={!lookupWiki}
                      onClick={() => lookupWiki && setLookupIsWiki(true)}
                    >
                      Wiki
                    </button>
                  </div>
                ) : (
                  <span className="muted small" data-testid="regen-lookup-wiki">Wiki</span>
                )}
                <input
                  className="regen-lookup-query"
                  data-testid="regen-lookup-query"
                  maxLength={256}
                  value={lookupQuery}
                  onChange={(e) => setLookupQuery(e.target.value)}
                  placeholder="the exact words to look up — optional"
                />
              </div>
            )}
            <div className="regen-critique-actions">
              <span className="muted small regen-critique-chord">⌘/Ctrl+Enter</span>
              <button type="button" className="link-btn" onClick={closeCritique}>Cancel</button>
              <button type="submit">Regenerate</button>
            </div>
          </form>
        </div>
      )}
    </>
  );
}
