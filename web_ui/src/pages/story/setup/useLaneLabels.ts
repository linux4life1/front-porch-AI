// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "Same as chat · Kimi K2.6", "OpenRouter · Opus": the relay names each job's
// model the way the desktop does (`POST /api/stories/lane-label`).

import { useEffect, useState } from 'react';
import { api } from '../../../api/client';
import type { StoryJob, StoryLaneChoice, StoryLaneJson } from '../../../storyTypes';
import { JOBS, laneToJson } from './draft';

interface Named {
  wire: string;
  label: string;
}

export function useLaneLabels(lanes: Record<StoryJob, StoryLaneChoice>): Partial<Record<StoryJob, string>> {
  const [named, setNamed] = useState<Partial<Record<StoryJob, Named>>>({});
  const key = JSON.stringify(JOBS.map(({ job }) => laneToJson(lanes[job])));

  useEffect(() => {
    let live = true;
    const wires = JSON.parse(key) as StoryLaneJson[];
    JOBS.forEach(({ job }, i) => {
      api.post<{ label: string }>('/api/stories/lane-label', wires[i])
        .then((r) => { if (live) setNamed((prev) => ({ ...prev, [job]: { wire: JSON.stringify(wires[i]), label: r.label } })); })
        // No name yet: the pick field shows the lane's plain name until the next change asks again.
        .catch(() => undefined);
    });
    return () => { live = false; };
  }, [key]);

  const out: Partial<Record<StoryJob, string>> = {};
  for (const { job } of JOBS) {
    const entry = named[job];
    if (entry && entry.wire === JSON.stringify(laneToJson(lanes[job]))) out[job] = entry.label;
  }
  return out;
}
