// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Where the story stands, in the shelf's own words ("Act II · 41,200 / 80,000",
// "Structure ready · nothing written") and the 0..1 fraction behind the
// header's progress bar. The relay computes both with the Dart helper the
// desktop shelf calls, so the header never words it differently.

import { useEffect, useState } from 'react';
import { api } from '../../api/client';
import type { StoryProject, StoryShelfState } from '../../storyTypes';

/** The header's second line: the shelf status, with the unit the shelf has no room for. */
export function headerSubtitle(shelf: StoryShelfState | null, running: boolean, project: StoryProject): string {
  if (running && project.acts.length === 0) return 'Building the bible…';
  if (!shelf) return '';
  return shelf.status.includes(' / ') ? `${shelf.status} words` : shelf.status;
}

/** Re-asks whenever the project reloads or a run moves to its next step. */
export function useShelfState(
  id: string,
  project: StoryProject,
  running: boolean,
  step: string | undefined,
): StoryShelfState | null {
  const [shelf, setShelf] = useState<StoryShelfState | null>(null);
  useEffect(() => {
    let live = true;
    api.get<{ stories: { id: string; shelf?: StoryShelfState }[] }>('/api/stories')
      .then((r) => {
        const mine = (r.stories ?? []).find((s) => s.id === id)?.shelf;
        if (live && mine) setShelf(mine);
      })
      // The header keeps the last words it had; the next change asks again.
      .catch(() => undefined);
    return () => { live = false; };
  }, [id, project, running, step]);
  return shelf;
}
