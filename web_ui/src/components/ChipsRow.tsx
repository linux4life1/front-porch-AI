// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Per-message Realism + Needs chips shown under an AI reply. Extracted verbatim
// from ChatPage to keep that page under the file-size cap. Realism deltas sit on
// their own row, Needs deltas on a second row below (matching the desktop
// bubble). A chip carrying a reason is tappable to reveal it inline (works on
// touch where hover can't) and also exposes the reason as a title for desktop
// hover. The last message additionally offers the Director redo (reprocess Needs
// with a critique) + revert.

import { useState } from 'react';
import { type Chips, NEED_LABELS } from './chatTypes';

interface Pill {
  key: string;
  label: string;
  cls: string;
  reason?: string;
}

export function ChipsRow({
  chips,
  isLast,
  busy,
  onReprocess,
  onRevert,
}: {
  chips: Chips;
  isLast: boolean;
  busy: boolean;
  onReprocess: () => void;
  onRevert: () => void;
}) {
  const [openKey, setOpenKey] = useState<string | null>(null);
  const signed = (n: number) => (n > 0 ? `+${n}` : `${n}`);

  const realism: Pill[] = [];
  if (chips.bondDelta) realism.push({ key: 'bond', label: `Bond ${signed(chips.bondDelta)}`, cls: chips.bondDelta > 0 ? 'up' : 'down', reason: chips.bondReason });
  if (chips.trustDelta) realism.push({ key: 'trust', label: `Trust ${signed(chips.trustDelta)}`, cls: chips.trustDelta > 0 ? 'up' : 'down', reason: chips.trustReason });
  if (chips.arousalDelta) realism.push({ key: 'arousal', label: `Arousal ${signed(chips.arousalDelta)}`, cls: chips.arousalDelta > 0 ? 'up' : 'down' });
  if (chips.emotionLabel) realism.push({ key: 'mood', label: chips.emotionLabel, cls: 'mood' });
  if (chips.timeSkipTo) realism.push({ key: 'time', label: `⏱ ${chips.timeSkipTo}`, cls: 'time' });
  if (chips.chanceTimeEvent) realism.push({ key: 'chance', label: '🎲 Chance Time', cls: 'time', reason: chips.chanceTimeEvent });

  const needs: Pill[] = [];
  for (const [k, v] of Object.entries(chips.needsDeltas ?? {})) {
    const delta = typeof v === 'number' ? v : v?.delta;
    const reason = typeof v === 'number' ? undefined : v?.reason;
    if (!delta) continue;
    needs.push({ key: `need-${k}`, label: `${NEED_LABELS[k] ?? k} ${signed(delta)}`, cls: delta > 0 ? 'up' : 'down', reason });
  }

  const showReprocess = isLast && !busy && !!chips.needsReprocessable;
  const showRevert = isLast && !busy && !!chips.needsRevertable;
  if (realism.length === 0 && needs.length === 0 && !showReprocess && !showRevert) return null;

  const toggle = (key: string) => setOpenKey((cur) => (cur === key ? null : key));
  const renderPill = (p: Pill) => {
    const hasReason = !!p.reason && p.reason.trim().length > 0;
    return (
      <span
        key={p.key}
        className={`chip ${p.cls}${hasReason ? ' has-reason' : ''}${openKey === p.key ? ' open' : ''}`}
        title={hasReason ? p.reason : undefined}
        role={hasReason ? 'button' : undefined}
        tabIndex={hasReason ? 0 : undefined}
        aria-expanded={hasReason ? openKey === p.key : undefined}
        onClick={hasReason ? () => toggle(p.key) : undefined}
        onKeyDown={hasReason ? (e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); toggle(p.key); } } : undefined}
      >
        {p.label}{hasReason && <span className="chip-info" aria-hidden> ⓘ</span>}
      </span>
    );
  };

  const openReason = [...realism, ...needs].find((p) => p.key === openKey)?.reason ?? '';

  return (
    <div className="chips-block">
      {realism.length > 0 && <div className="chips-row realism">{realism.map(renderPill)}</div>}
      {needs.length > 0 && <div className="chips-row needs">{needs.map(renderPill)}</div>}
      {openKey && openReason && <div className="chip-reason">{openReason}</div>}
      {(showReprocess || showRevert) && (
        <div className="needs-reprocess-row">
          {showReprocess && (
            <button type="button" className="btn-reprocess" onClick={onReprocess} title="Reprocess Needs with your critique">
              ✍ Manual Reprocess
            </button>
          )}
          {showRevert && (
            <button type="button" className="btn-revert" onClick={onRevert} title="Restore the Needs deltas from before the last reprocess">
              ↺ Revert reprocess
            </button>
          )}
        </div>
      )}
    </div>
  );
}
