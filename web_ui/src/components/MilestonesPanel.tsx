// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "Our Story" milestones timeline (Living Time §7) — the web mirror of the
// desktop journal dialog's timeline tab. Pure read-model over
// /api/chat/tools/timeline (growth rings, salient journal memories, dreams,
// Chance Time strikes, achieved objectives), grouped by story day where
// known. Group-aware: scoped to the focused participant like GrowthPanel.

import { useEffect, useState } from 'react';
import { api } from '../api/client';

interface TimelineEntry {
  kind: 'ring' | 'chance' | 'objective' | 'memory' | 'dream' | string;
  text: string;
  day?: number;
  position?: number;
  emotion?: string;
}
interface TimelineData {
  owner: string | null;
  entries: TimelineEntry[];
}

const KIND_ICONS: Record<string, string> = {
  ring: '🌱',
  chance: '⚡',
  objective: '🎯',
  memory: '📔',
  dream: '🌙',
  ambition: '🧭',
  milestone: '🏆',
  promise: '🤝',
};

export function MilestonesPanel({
  focusedId,
  reloadKey,
}: {
  focusedId?: string | null;
  reloadKey: number;
}) {
  const [data, setData] = useState<TimelineData | null>(null);

  useEffect(() => {
    let alive = true;
    const q = focusedId ? `?owner=${encodeURIComponent(focusedId)}` : '';
    api
      .get<TimelineData>(`/api/chat/tools/timeline${q}`)
      .then((d) => {
        if (alive) setData(d);
      })
      .catch(() => {
        if (alive) setData({ owner: null, entries: [] });
      });
    return () => {
      alive = false;
    };
  }, [focusedId, reloadKey]);

  if (!data) return null;
  if (data.entries.length === 0) {
    return (
      <p className="muted milestones-empty">
        Nothing on the timeline yet — strong memories, growth, Chance Time
        strikes, achieved objectives, and dreams gather here.
      </p>
    );
  }

  const rows: React.ReactNode[] = [];
  let lastDay: number | undefined;
  data.entries.forEach((e, i) => {
    if (e.day !== undefined && e.day !== lastDay) {
      lastDay = e.day;
      rows.push(
        <div key={`d${e.day}-${i}`} className="milestone-day">
          Day {e.day}
        </div>,
      );
    }
    rows.push(
      <div key={i} className="milestone-row">
        <span className="milestone-icon">{KIND_ICONS[e.kind] ?? '•'}</span>
        <span className="milestone-text">{e.text}</span>
        {e.emotion && <em className="milestone-emotion">{e.emotion}</em>}
      </div>,
    );
  });
  return <div className="milestones-panel">{rows}</div>;
}
