// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The insight panel's labelled stat bar (bond / trust / needs), lifted out of
// ChatInsight so the needs bar can be pinned on its own.

import type { CSSProperties } from 'react';
import { needTone } from './needTone';
import type { NeedTrouble } from '../theme/moodAtmosphere';

/** A labelled stat bar. `percent` is 0-1 or 0-100: anything at or under 1 is
 *  read as a fraction. */
export function StatBar({ label, value, percent, tone, className, style, badge, fill }: {
  label: string; value: string; percent: number; tone?: string;
  /** Extra classes and custom properties on the stat (Mood on the character). */
  className?: string; style?: CSSProperties;
  /** A badge at the bar's end, for a need in trouble. */
  badge?: string;
  /** Paint the fill with this CSS colour (the wide card's per-need hues). */
  fill?: string;
}) {
  const pct = Math.max(0, Math.min(100, percent <= 1 ? percent * 100 : percent));
  return (
    <div className={`stat${className ? ` ${className}` : ''}`} style={style}>
      <div className="stat-head">
        <span>{label}</span>
        <span className="muted">{value}</span>
      </div>
      <div className="stat-track">
        <div
          className={`stat-fill ${tone ?? ''}`}
          style={{ width: `${pct}%`, ...(fill ? { background: fill } : {}) }}
        />
        {badge && <span className="need-badge" aria-hidden="true">{badge}</span>}
      </div>
    </div>
  );
}

/** One need (0-100) in its band colour. Passed on as a fraction, so a need at
 *  1, the on-screen wear floor, draws a sliver rather than a full bar. With
 *  Mood on the character, a need in [trouble] throbs in its own [hue]. */
export function NeedBar({
  label,
  value,
  urgentAt,
  criticalAt,
  trouble,
  hue,
  fill,
}: {
  label: string;
  value: number;
  /** The engine's cutoffs from the realism payload; the helper's defaults otherwise. */
  urgentAt?: number;
  criticalAt?: number;
  trouble?: NeedTrouble;
  hue?: string;
  /** Paint the bar with this CSS colour always (not just when in trouble). */
  fill?: string;
}) {
  const low = !!trouble?.low;
  const classes = low
    ? ['need-low', trouble?.critical ? 'need-critical' : '', trouble?.inverted ? 'need-inverted' : ''].filter(Boolean).join(' ')
    : undefined;
  return (
    <StatBar
      label={label}
      value={`${value}`}
      percent={value / 100}
      tone={needTone(value, urgentAt, criticalAt)}
      className={classes}
      fill={fill}
      style={low && hue ? ({ '--need-hue': hue } as CSSProperties) : undefined}
      badge={low ? (trouble?.inverted ? '↕' : '!') : undefined}
    />
  );
}
