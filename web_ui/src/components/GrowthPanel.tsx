// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Growth Rings timeline — the web mirror of the desktop GrowthPanel
// (docs/design/growth-rings.md; replaced the evolution review modal). Rings
// grouped by tier (Established / Developing / Emerging) with category chips,
// strength bars, and receipt pills; a collapsible Past section; Check now /
// Plant a ring / Reset actions; and the review banner (review-first mode,
// default OFF). Group-aware: every read/write is scoped to the focused
// participant, so a member's timeline is identical to a 1:1 timeline.

import { useCallback, useEffect, useState } from 'react';
import { api } from '../api/client';
import { GrowthReviewModal } from './GrowthReviewModal';

export interface GrowthRing {
  id: string;
  content: string;
  category: string;
  tier: 'emerging' | 'developing' | 'established';
  strength: number;
  pinned: boolean;
  retired: boolean;
  receipts: number[];
}
interface GrowthData {
  name: string;
  ownerId: string;
  passRunning: boolean;
  hasLegacyBlob?: boolean;
  reviewPending?: number;
  rings: GrowthRing[];
}

const TIERS: Array<[GrowthRing['tier'], string]> = [
  ['established', 'Established'],
  ['developing', 'Developing'],
  ['emerging', 'Emerging'],
];
const CATEGORIES = ['trait', 'stance', 'habit', 'skill', 'scar'];

/** Small modal for planting/editing one ring (sentence + category). */
function RingEditor({
  title,
  initialText = '',
  initialCategory = 'trait',
  onSave,
  onClose,
}: {
  title: string;
  initialText?: string;
  initialCategory?: string;
  onSave: (text: string, category: string) => void;
  onClose: () => void;
}) {
  const [text, setText] = useState(initialText);
  const [category, setCategory] = useState(
    CATEGORIES.includes(initialCategory) ? initialCategory : 'trait',
  );
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
          maxLength={200}
          placeholder='One sentence of change — "Has started guarding {{user}}&apos;s sleep."'
          value={text}
          onChange={(e) => setText(e.target.value)}
        />
        <div className="growth-cat-row">
          {CATEGORIES.map((c) => (
            <button
              key={c}
              className={`growth-chip selectable cat-${c}${category === c ? ' selected' : ''}`}
              onClick={() => setCategory(c)}
            >
              {c}
            </button>
          ))}
        </div>
        <div className="modal-actions">
          <button onClick={onClose}>Cancel</button>
          <button
            className="primary"
            disabled={!text.trim()}
            onClick={() => onSave(text.trim(), category)}
          >
            Save
          </button>
        </div>
      </div>
    </div>
  );
}

export function GrowthPanel({
  focusedId,
  reloadKey,
}: {
  focusedId?: string | null;
  reloadKey: number;
}) {
  const [d, setD] = useState<GrowthData | null>(null);
  const [showPast, setShowPast] = useState(false);
  const [showReview, setShowReview] = useState(false);
  const [editor, setEditor] = useState<
    | { mode: 'plant' }
    | { mode: 'edit'; ring: GrowthRing }
    | null
  >(null);

  const q = focusedId ? `?participant=${encodeURIComponent(focusedId)}` : '';

  const load = useCallback(async () => {
    try {
      setD(await api.get<GrowthData>(`/api/chat/tools/growth${q}`));
    } catch {
      /* no active chat — stay hidden */
    }
  }, [q]);

  useEffect(() => {
    void load();
  }, [load, reloadKey]);

  const act = (action: string, body: Record<string, unknown> = {}) =>
    void api
      .post<GrowthData>(`/api/chat/tools/growth${q}`, { action, ...body })
      .then(setD)
      .catch(() => {});

  if (!d || !d.ownerId) return null;

  const active = d.rings.filter((r) => !r.retired);
  const past = d.rings.filter((r) => r.retired);

  const ringCard = (r: GrowthRing, isPast: boolean) => (
    <div key={r.id} className={`growth-ring${r.tier === 'emerging' && !isPast ? ' emerging' : ''}${isPast ? ' past' : ''}`}>
      <div className="growth-ring-top">
        <span className={`growth-chip cat-${r.category}`}>
          {r.category === 'archive' ? 'pre-rings archive' : r.category}
        </span>
        {r.pinned && <span className="growth-pin" title="Pinned — never fades">📌</span>}
        <span className="grow" />
        {!isPast ? (
          <>
            <button className="icon-btn" title={r.pinned ? 'Unpin' : 'Pin (never fades)'} onClick={() => act('pin', { ringId: r.id })}>
              {r.pinned ? '📍' : '📌'}
            </button>
            <button className="icon-btn" title="Edit wording" onClick={() => setEditor({ mode: 'edit', ring: r })}>✏️</button>
            <button className="icon-btn" title="Retire to past" onClick={() => act('retire', { ringId: r.id })}>🕰️</button>
          </>
        ) : (
          <>
            <button className="icon-btn" title="Bring back" onClick={() => act('restore', { ringId: r.id })}>↩️</button>
            <button
              className="icon-btn"
              title="Delete forever"
              onClick={() => window.confirm('Delete this ring forever?') && act('delete', { ringId: r.id })}
            >
              🗑️
            </button>
          </>
        )}
      </div>
      <div className="growth-ring-text">{r.content}</div>
      <div className="growth-ring-meta">
        {!isPast && (
          <div className="growth-strength">
            <i style={{ width: `${Math.round(r.strength * 100)}%` }} />
          </div>
        )}
        {r.receipts.slice(0, 3).map((p) => (
          <span key={p} className="growth-receipt" title={`Earned at message #${p}`}>#{p}</span>
        ))}
        {r.receipts.length > 3 && <span className="muted small">+{r.receipts.length - 3}</span>}
      </div>
    </div>
  );

  return (
    <div className="growth-panel">
      {(d.reviewPending ?? 0) > 0 && (
        <button className="growth-review-banner" onClick={() => setShowReview(true)}>
          🌱 <strong>{d.name} has grown</strong> — {d.reviewPending} proposal(s) waiting. Tap to review.
        </button>
      )}
      {d.hasLegacyBlob && (
        <p className="muted small">
          Growth recorded under the old system still applies — it converts to rings at the next check.
        </p>
      )}
      {active.length === 0 && past.length === 0 && !d.hasLegacyBlob && (
        <p className="muted small">
          {d.name} hasn&apos;t grown yet — rings appear as the story changes them.
        </p>
      )}
      {TIERS.map(([tier, label]) => {
        const rings = active.filter((r) => r.tier === tier);
        if (rings.length === 0) return null;
        return (
          <div key={tier}>
            <div className={`growth-tier-head tier-${tier}`}>
              <span className="growth-tier-dot" />
              {label}
            </div>
            {rings.map((r) => ringCard(r, false))}
          </div>
        );
      })}
      {past.length > 0 && (
        <button className="link-btn growth-past-toggle" onClick={() => setShowPast((v) => !v)}>
          {showPast ? '▾' : '▸'} Past growth ({past.length})
        </button>
      )}
      {showPast && past.map((r) => ringCard(r, true))}
      <div className="tool-row growth-actions">
        <button className="small" disabled={d.passRunning} onClick={() => act('check')}>
          {d.passRunning ? 'Checking…' : 'Check now'}
        </button>
        <button className="small" onClick={() => setEditor({ mode: 'plant' })}>Plant a ring</button>
        <span className="grow" />
        <button
          className="small danger"
          onClick={() =>
            window.confirm(
              `Remove every ring ${d.name} has grown in this chat (including past growth)? ` +
                'The original character card is untouched. This cannot be undone.',
            ) && act('reset')
          }
        >
          Reset
        </button>
      </div>
      {editor?.mode === 'plant' && (
        <RingEditor
          title={`Plant a ring for ${d.name}`}
          onClose={() => setEditor(null)}
          onSave={(text, category) => {
            act('plant', { text, category });
            setEditor(null);
          }}
        />
      )}
      {editor?.mode === 'edit' && (
        <RingEditor
          title="Edit ring"
          initialText={editor.ring.content}
          initialCategory={editor.ring.category}
          onClose={() => setEditor(null)}
          onSave={(text, category) => {
            act('edit', { ringId: editor.ring.id, text, category });
            setEditor(null);
          }}
        />
      )}
      {showReview && (
        <GrowthReviewModal
          onClose={() => {
            setShowReview(false);
            void load();
          }}
        />
      )}
    </div>
  );
}
