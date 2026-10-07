// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The insight panel's labelled stat bar (bond / trust / needs), lifted out of
// ChatInsight so the needs bar can be pinned on its own.

import { needTone } from './needTone';

/** A labelled stat bar. `percent` is 0-1 or 0-100: anything at or under 1 is
 *  read as a fraction. */
export function StatBar({ label, value, percent, tone }: { label: string; value: string; percent: number; tone?: string }) {
  const pct = Math.max(0, Math.min(100, percent <= 1 ? percent * 100 : percent));
  return (
    <div className="stat">
      <div className="stat-head">
        <span>{label}</span>
        <span className="muted">{value}</span>
      </div>
      <div className="stat-track">
        <div className={`stat-fill ${tone ?? ''}`} style={{ width: `${pct}%` }} />
      </div>
    </div>
  );
}

/** One need (0-100) in its band colour. Passed on as a fraction, so a need at
 *  1, the on-screen wear floor, draws a sliver rather than a full bar. */
export function NeedBar({ label, value }: { label: string; value: number }) {
  return <StatBar label={label} value={`${value}`} percent={value / 100} tone={needTone(value)} />;
}
