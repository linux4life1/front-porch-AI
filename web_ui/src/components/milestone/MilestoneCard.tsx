// The milestone card — the web twin of lib/ui/widgets/milestone/milestone_card.dart,
// transcribed from the approved mockup
// (docs/design/mockups/boons-and-bogies-milestones.html): "✦ Milestone", the
// kind line (naming the member in a group), the ring box (pill, tier line,
// sentence, meter), the receipt, the ask, and Reject / Accept on one row.
// Chrome follows the theme tokens; the accents are the fixed milestone palette.

import type { CSSProperties } from 'react';

import type { MilestoneViewJson } from './milestoneTypes';

export function milestoneAccent(view: Pick<MilestoneViewJson, 'kind' | 'pill'>): string {
  if (view.kind === 'overcome') return 'var(--ms-overcome)';
  return view.pill === 'BOGEY' ? 'var(--ms-violet)' : 'var(--ms-gold)';
}

export function MilestoneCard({
  view,
  replaying,
  busy,
  notice,
  badge,
  onAccept,
  onReject,
  onClose,
}: {
  view: MilestoneViewJson;
  replaying: boolean;
  busy: boolean;
  notice?: string;
  /** 0..1 — the Master badge's stamp; 1 under reduce motion. */
  badge: number;
  onAccept: () => void;
  onReject: () => void;
  onClose: () => void;
}) {
  const master = view.kind.startsWith('master_');
  const style = { '--ms-accent': milestoneAccent(view) } as CSSProperties;
  return (
    <div className="ms-card" role="dialog" aria-label={`Milestone: ${view.title}`} style={style}>
      <div className="ms-title">
        <span className="ms-star">✦</span> Milestone
      </div>
      <div className="ms-kind">
        {view.title}
        {view.inGroup && view.ownerName && (
          <>
            {' · '}
            <b>{view.ownerName}</b>
          </>
        )}
      </div>
      <div className="ms-ring">
        {master && (
          <span
            className={`ms-badge${view.pill === 'BOGEY' ? ' ms-badge-bogey' : ''}`}
            style={{
              opacity: badge,
              transform: `rotate(8deg) scale(${1 + 1.2 * (1 - badge)})`,
            }}
          >
            MASTER
          </span>
        )}
        <div className="ms-row">
          <span className="ms-pill">{view.pill}</span>
          <span className="ms-tier">{view.tierLine}</span>
        </div>
        <div className="ms-text">{view.text}</div>
        <div className="ms-meter">
          <i style={{ width: `${Math.round(Math.max(0, Math.min(1, view.meter)) * 100)}%` }} />
        </div>
      </div>
      {view.receipt && <div className="ms-receipt">{view.receipt}</div>}
      {view.ask && <div className="ms-ask">{view.ask}</div>}
      {notice && <div className="ms-notice">{notice}</div>}
      <div className="ms-btns">
        {replaying ? (
          <button className="ms-reject" disabled={busy} onClick={onClose}>
            Close
          </button>
        ) : (
          <>
            <button className="ms-reject" disabled={busy} onClick={onReject}>
              Reject
            </button>
            <button className="ms-accept" disabled={busy} onClick={onAccept}>
              Accept
            </button>
          </>
        )}
      </div>
    </div>
  );
}
