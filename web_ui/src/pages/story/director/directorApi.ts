// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Director's writes. The server keeps one project; a full save from a page
// that loaded it a while ago would put an old plan back, so the two fields the
// page owns (the box and the protect switch) are merged into a project fetched
// just now. The plan edits (tick, discard, undo) are their own endpoints.

import { api } from '../../../api/client';
import { saveStoryProject } from '../../../hooks/useStory';
import type { StoryProject } from '../../../storyTypes';

/** Merge [patch] into the freshest copy of the story and save it. Skips the write when nothing changes. */
export async function saveDirectorFields(
  id: string,
  patch: { director_draft?: string; director_protect?: boolean },
): Promise<void> {
  const fresh = await api.get<StoryProject>(`/api/stories/${id}`);
  const same = (patch.director_draft === undefined || patch.director_draft === (fresh.director_draft ?? ''))
    && (patch.director_protect === undefined || patch.director_protect === (fresh.director_protect !== false));
  if (same) return;
  await saveStoryProject(id, { ...fresh, ...patch });
}

type DirectorEndpoint = 'action' | 'protect' | 'discard' | 'undo';

/** `undo` answers `{status: 'nothing-to-undo'}` when the snapshot of that plan is gone. */
export const directorPost = (id: string, endpoint: DirectorEndpoint, body: Record<string, unknown> = {}) =>
  api.post<{ status?: string; ok?: boolean }>(`/api/stories/${id}/director/${endpoint}`, body);
