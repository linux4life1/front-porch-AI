// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Growth review-first modal — the web mirror of the desktop
// GrowthReviewDialog (docs/design/growth-rings.md §3.1, default OFF).
// Proposals speak plain words — new / stronger / reworded / outgrown — and
// every one ships checked; unchecking drops just that one. Apply commits the
// accepted set through the same applier autonomous mode uses; Discard writes
// nothing (the reviewed window counts as handled either way).

import { useEffect, useState } from 'react';
import { api, ApiError } from '../api/client';

interface ReviewOp {
  action: 'add' | 'reinforce' | 'revise' | 'retire';
  text: string;
  oldContent: string;
}
interface ReviewBatch {
  pending: boolean;
  owners: Array<{ ownerName: string; ops: ReviewOp[] }>;
}

const ACTION_LABEL: Record<ReviewOp['action'], string> = {
  add: 'New ring',
  reinforce: 'Stronger',
  revise: 'Reworded',
  retire: 'Outgrown',
};

function opBody(op: ReviewOp): string {
  switch (op.action) {
    case 'add':
      return op.text;
    case 'reinforce':
      return `${op.oldContent} — seen again`;
    case 'revise':
      return `${op.oldContent} → ${op.text}`;
    case 'retire':
      return op.oldContent;
  }
}

export function GrowthReviewModal({ onClose }: { onClose: () => void }) {
  const [batch, setBatch] = useState<ReviewBatch | null>(null);
  const [rejected, setRejected] = useState<Set<string>>(new Set());
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  useEffect(() => {
    api
      .get<ReviewBatch>('/api/chat/tools/growth/review')
      .then(setBatch)
      .catch((e) => setError(e instanceof ApiError ? e.message : 'Failed to load review'));
  }, []);

  const toggle = (key: string) =>
    setRejected((prev) => {
      const next = new Set(prev);
      if (next.has(key)) next.delete(key);
      else next.add(key);
      return next;
    });

  const settle = async (apply: boolean) => {
    setBusy(true);
    setError('');
    try {
      await api.post('/api/chat/tools/growth/review', {
        apply,
        rejected: [...rejected],
      });
      onClose();
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Failed to apply');
      setBusy(false);
    }
  };

  return (
    <div className="drawer-backdrop center" onClick={() => !busy && onClose()}>
      <div className="modal growth-review-modal" onClick={(e) => e.stopPropagation()}>
        <div className="drawer-head">
          <span>🌱 Growth to review</span>
          <button className="link-btn" onClick={onClose} disabled={busy}>Close</button>
        </div>
        {!batch && !error && <div className="centered"><div className="spinner" /></div>}
        {batch && !batch.pending && (
          <p className="muted small">Nothing waiting — it was settled elsewhere.</p>
        )}
        {batch?.pending && (
          <>
            <p className="muted small">Uncheck anything that doesn&apos;t ring true, then apply.</p>
            <div className="growth-review-list">
              {batch.owners.map((owner, o) => (
                <div key={o}>
                  {batch.owners.length > 1 && (
                    <div className="growth-review-owner">{owner.ownerName}&apos;s growth</div>
                  )}
                  {owner.ops.map((op, i) => {
                    const key = `${o}:${i}`;
                    const checked = !rejected.has(key);
                    return (
                      <label key={key} className={`growth-proposal${checked ? '' : ' off'}`}>
                        <input
                          type="checkbox"
                          checked={checked}
                          onChange={() => toggle(key)}
                        />
                        <span>
                          <span className={`growth-chip act-${op.action}`}>{ACTION_LABEL[op.action]}</span>
                          <span className={op.action === 'retire' ? 'struck' : ''}> {opBody(op)}</span>
                        </span>
                      </label>
                    );
                  })}
                </div>
              ))}
            </div>
            {error && <p className="error">{error}</p>}
            <div className="modal-actions">
              <button className="danger" onClick={() => settle(false)} disabled={busy}>Discard all</button>
              <button className="primary" onClick={() => settle(true)} disabled={busy}>
                {busy ? 'Applying…' : 'Apply selected'}
              </button>
            </div>
          </>
        )}
        {error && !batch && <p className="error">{error}</p>}
      </div>
    </div>
  );
}
