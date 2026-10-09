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
  const signed = (n: number) => (n >= 0 ? `+${n}` : `${n}`);

  const realism: Pill[] = [];
  // Desktop twin: message_bubble.realism.dart + kFeelingsUnscoredLabel/Tip.
  const unscored = !!chips.feelingsUnscored && chips.bondDelta == null && chips.trustDelta == null;
  if (unscored) realism.push({ key: 'unscored', label: 'Feelings not scored this time', cls: 'time', reason: "The model's answer couldn't be read, so bond and trust stayed where they were. To try again and keep this reply, tap Manual Reprocess and pick Feelings." });
  if (chips.bondDelta != null) realism.push({ key: 'bond', label: chips.bondDelta === 0 ? 'Bond unchanged' : `Bond ${signed(chips.bondDelta)}`, cls: chips.bondDelta > 0 ? 'up' : chips.bondDelta < 0 ? 'down' : 'time', reason: chips.bondReason });
  if (chips.trustDelta != null) realism.push({ key: 'trust', label: chips.trustDelta === 0 ? 'Trust unchanged' : `Trust ${signed(chips.trustDelta)}`, cls: chips.trustDelta > 0 ? 'up' : chips.trustDelta < 0 ? 'down' : 'time', reason: chips.trustReason });
  if (chips.arousalDelta) realism.push({ key: 'arousal', label: `Arousal ${signed(chips.arousalDelta)}`, cls: chips.arousalDelta > 0 ? 'up' : 'down' });
  if (chips.emotionLabel) realism.push({ key: 'mood', label: chips.emotionLabel, cls: 'mood' });
  if (chips.timePassed) realism.push({ key: 'passed', label: `⏱ ${chips.timePassed}`, cls: 'time' });
  if (chips.timeSkipTo) realism.push({ key: 'time', label: `⏱ ${chips.timeSkipTo}`, cls: 'time' });
  if (chips.chanceTimeEvent) realism.push({ key: 'chance', label: '🎲 Chance Time', cls: 'time', reason: chips.chanceTimeEvent });
  if (chips.searchQuery) realism.push({ key: 'search', label: chips.searchOk === false ? '🔎 Looked up — nothing' : '🔎 Looked up', cls: 'time', reason: chips.searchQuery });
  if (chips.wikiQuery) realism.push({ key: 'wiki', label: chips.wikiOk === false ? '📖 Wiki — nothing' : '📖 Wiki', cls: 'time', reason: chips.wikiQuery });
  const toolName = chips.toolName;
  const toolOk = chips.toolOk;
  if (toolName) realism.push({ key: 'tool', label: toolOk === false ? `${toolName} — nothing` : toolName, cls: 'time', reason: toolName });

  const needs: Pill[] = [];
  for (const [k, v] of Object.entries(chips.needsDeltas ?? {})) {
    const delta = typeof v === 'number' ? v : v?.delta;
    const reason = typeof v === 'number' ? undefined : v?.reason;
    if (!delta) continue;
    needs.push({ key: `need-${k}`, label: `${NEED_LABELS[k] ?? k} ${signed(delta)}`, cls: delta > 0 ? 'up' : 'down', reason });
  }
  if (chips.needsUnaffected && needs.length === 0) {
    needs.push({ key: 'unaffected', label: 'No needs affected', cls: 'time' });
  }

  // Either Manual Reprocess choice keeps the button: Needs or Feelings.
  const showReprocess = isLast && !busy && (!!chips.needsReprocessable || !!chips.feelingsReprocessable);
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
            <button type="button" className="btn-reprocess" onClick={onReprocess} title="Redo the Needs or the Feelings for this reply">
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
