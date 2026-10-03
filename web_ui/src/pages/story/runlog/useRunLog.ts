// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The story's run log, newest first, kept current: it asks again whenever the
// project reloads or a run moves to its next step, the way the studio header
// asks the shelf where the story stands (useShelfState).

import { useCallback, useEffect, useState } from 'react';
import { api, ApiError } from '../../../api/client';
import type { StoryProject, StoryRunEntry } from '../../../storyTypes';

export function useRunLog(
  id: string,
  project: StoryProject | null,
  running: boolean,
  step: string | undefined,
  message: string | undefined,
): { entries: StoryRunEntry[]; error: string; reload: () => void } {
  const [entries, setEntries] = useState<StoryRunEntry[]>([]);
  const [error, setError] = useState('');
  const [nonce, setNonce] = useState(0);

  useEffect(() => {
    let live = true;
    api.get<{ entries: StoryRunEntry[] }>(`/api/stories/${id}/log`)
      .then((r) => {
        if (!live) return;
        setEntries([...(r.entries ?? [])].reverse());
        setError('');
      })
      // The list keeps what it had; the next change asks again.
      .catch((e) => { if (live) setError(e instanceof ApiError ? e.message : 'The run log could not be loaded'); });
    return () => { live = false; };
  }, [id, project, running, step, message, nonce]);

  const reload = useCallback(() => setNonce((n) => n + 1), []);
  return { entries, error, reload };
}
