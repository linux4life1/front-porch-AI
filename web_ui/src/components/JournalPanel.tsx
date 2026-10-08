// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Journal diary timeline — web mirror of the desktop Journal dialog
// (audit P2.12). Cards with pin/edit/retire, plant, check-now, and the
// review-first banner. Group-aware via focused participant id.

import { useCallback, useEffect, useState } from 'react';
import { api } from '../api/client';
import { JournalReviewModal } from './JournalReviewModal';
import { ExpandableText } from './ExpandableText';

export interface JournalCard {
  id: string;
  content: string;
  category: string;
  feeling?: string | null;
  intensity?: string | null;
  pinned: boolean;
  heat: number;
  storyDay?: number | null;
  receipts: number[];
}
interface JournalData {
  name: string;
  ownerId: string;
  passRunning: boolean;
  reviewPending?: number;
  cards: JournalCard[];
}

const CATEGORIES = ['about_user', 'about_us', 'moment', 'promise'];

function CardEditor({
  title,
  initialText = '',
  initialCategory = 'moment',
  initialFeeling = '',
  showCategory = true,
  onSave,
  onClose,
}: {
  title: string;
  initialText?: string;
  initialCategory?: string;
  initialFeeling?: string;
  showCategory?: boolean;
  onSave: (text: string, category: string, feeling: string) => void;
  onClose: () => void;
}) {
  const [text, setText] = useState(initialText);
  const [category, setCategory] = useState(
    CATEGORIES.includes(initialCategory) ? initialCategory : 'moment',
  );
  const [feeling, setFeeling] = useState(initialFeeling);
  return (
    <div className="drawer-backdrop center" onClick={onClose}>
      <div className="modal growth-editor" onClick={(e) => e.stopPropagation()}>
        <div className="drawer-head">
          <span>{title}</span>
          <button className="link-btn" onClick={onClose}>Close</button>
        </div>
        <textarea
          rows={3}
          autoFocus
          maxLength={400}
          placeholder='One memory in their words — "I left my keys on the hall table."'
          value={text}
          onChange={(e) => setText(e.target.value)}
        />
        {showCategory && (
          <div className="growth-cat-row">
            {CATEGORIES.map((c) => (
              <button
                key={c}
                className={`growth-chip selectable cat-${c}${category === c ? ' selected' : ''}`}
                onClick={() => setCategory(c)}
              >
                {c.replace('_', ' ')}
              </button>
            ))}
          </div>
        )}
        <label className="field" style={{ marginTop: 8 }}>
          <span className="muted small">Feeling (optional)</span>
          <input
            value={feeling}
            onChange={(e) => setFeeling(e.target.value)}
            placeholder="warm, wistful, proud…"
          />
        </label>
        <div className="modal-actions">
          <button onClick={onClose}>Cancel</button>
          <button
            className="primary"
            disabled={!text.trim()}
            onClick={() => onSave(text.trim(), category, feeling.trim())}
          >
            Save
          </button>
        </div>
      </div>
    </div>
  );
}

export function JournalPanel({
  focusedId,
  reloadKey,
}: {
  focusedId?: string | null;
  reloadKey: number;
}) {
  const [d, setD] = useState<JournalData | null>(null);
  const [showReview, setShowReview] = useState(false);
  const [editor, setEditor] = useState<
    | { mode: 'plant' }
    | { mode: 'edit'; card: JournalCard }
    | null
  >(null);

  const q = focusedId ? `?participant=${encodeURIComponent(focusedId)}` : '';

  const load = useCallback(async () => {
    try {
      setD(await api.get<JournalData>(`/api/chat/tools/journal${q}`));
    } catch {
      /* no active chat */
    }
  }, [q]);

  useEffect(() => {
    void load();
  }, [load, reloadKey]);

  const act = (action: string, body: Record<string, unknown> = {}) =>
    void api
      .post<JournalData>(`/api/chat/tools/journal${q}`, { action, ...body })
      .then(setD)
      .catch(() => {});

  if (!d || !d.ownerId) return null;

  const cardRow = (c: JournalCard) => (
    <div key={c.id} className="growth-ring">
      <div className="growth-ring-top">
        <span className={`growth-chip cat-${c.category}`}>
          {c.category.replace('_', ' ')}
        </span>
        {c.pinned && <span className="growth-pin" title="Pinned — never fades">📌</span>}
        {c.feeling && <span className="muted small">{c.feeling}</span>}
        <span className="grow" />
        <button
          className="icon-btn"
          title={c.pinned ? 'Unpin' : 'Pin (never fades)'}
          onClick={() => act('pin', { cardId: c.id })}
        >
          {c.pinned ? '📍' : '📌'}
        </button>
        <button
          className="icon-btn"
          title="Edit wording"
          onClick={() => setEditor({ mode: 'edit', card: c })}
        >
          ✏️
        </button>
        <button
          className="icon-btn"
          title="Retire this memory"
          onClick={() =>
            window.confirm('Retire this memory from the journal? The conversation is untouched.') &&
            act('retire', { cardId: c.id })
          }
        >
          🗑️
        </button>
      </div>
      <ExpandableText text={c.content} lines={4} className="growth-ring-text" />
      <div className="growth-ring-meta">
        {c.storyDay != null && (
          <span className="muted small">Day {c.storyDay}</span>
        )}
        {c.receipts.slice(0, 3).map((p) => (
          <span key={p} className="growth-receipt" title={`From message #${p + 1}`}>#{p + 1}</span>
        ))}
        {c.receipts.length > 3 && (
          <span className="muted small">+{c.receipts.length - 3}</span>
        )}
      </div>
    </div>
  );

  return (
    <div className="growth-panel">
      {(d.reviewPending ?? 0) > 0 && (
        <button className="growth-review-banner" onClick={() => setShowReview(true)}>
          📖 <strong>Journal updates ready</strong> — {d.reviewPending} proposal(s) waiting. Tap to review.
        </button>
      )}
      {d.cards.length === 0 && (
        <p className="muted small">
          {d.name}&apos;s journal is empty — plant a memory, or wait for the next pass.
        </p>
      )}
      {d.cards.map(cardRow)}
      <div className="tool-row growth-actions">
        <button className="small" disabled={d.passRunning} onClick={() => act('check')}>
          {d.passRunning ? 'Checking…' : 'Check now'}
        </button>
        <button className="small" onClick={() => setEditor({ mode: 'plant' })}>
          Plant a memory
        </button>
      </div>
      {editor?.mode === 'plant' && (
        <CardEditor
          title={`Plant a memory in ${d.name}'s journal`}
          onClose={() => setEditor(null)}
          onSave={(text, category, feeling) => {
            act('plant', { text, category, feeling: feeling || undefined });
            setEditor(null);
          }}
        />
      )}
      {editor?.mode === 'edit' && (
        <CardEditor
          title="Edit memory"
          initialText={editor.card.content}
          initialCategory={editor.card.category}
          initialFeeling={editor.card.feeling ?? ''}
          showCategory={false}
          onClose={() => setEditor(null)}
          onSave={(text, _category, feeling) => {
            act('edit', {
              cardId: editor.card.id,
              text,
              feeling: feeling || undefined,
            });
            setEditor(null);
          }}
        />
      )}
      {showReview && (
        <JournalReviewModal
          onClose={() => {
            setShowReview(false);
            void load();
          }}
        />
      )}
    </div>
  );
}
