// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Tiny per-act valence trajectory sparkline (scene emotional valence over the
// act), mirroring the desktop _ValenceSparklinePainter. Bars grow up for
// positive valence, down for negative, scaled to the -10..+10 range.

export function ValenceSparkline({ values }: { values: number[] }) {
  if (values.length === 0) return null;
  const max = 10;
  return (
    <span className="valence-spark" aria-hidden="true">
      {values.map((v, i) => {
        const mag = Math.min(Math.abs(v), max) / max; // 0..1
        const h = Math.max(3, Math.round(mag * 22));
        return <i key={i} className={v < 0 ? 'neg' : ''} style={{ height: `${h}px` }} />;
      })}
    </span>
  );
}
