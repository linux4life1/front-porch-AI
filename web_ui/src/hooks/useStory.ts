// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Shared Porch Stories hook: loads a project, subscribes to pipeline progress
// over the WS hub, and exposes a `run(stage, …)` that kicks off a background
// pipeline stage, plus `save(...)` for in-place edits (act titles, cast voices)
// and a chat-history preview loader. Used by the dashboard, structure, writer,
// and reader pages so the load + progress + refetch logic lives in one place.

import { useCallback, useEffect, useState } from 'react';
import { api, ApiError } from '../api/client';
import { ChatSocket } from '../api/ws';
import type { StoryProject, StoryStatus } from '../storyTypes';

export interface RunArgs {
  actIndex?: number;
  sceneIndex?: number;
  beatIndex?: number;
}

export function useStory(id: string) {
  const [project, setProject] = useState<StoryProject | null>(null);
  const [status, setStatus] = useState<StoryStatus | null>(null);
  const [error, setError] = useState('');

  const reload = useCallback(() => {
    api.get<StoryProject>(`/api/stories/${id}`)
      .then(setProject)
      .catch((e) => setError(e instanceof ApiError ? e.message : 'Failed to load'));
  }, [id]);

  useEffect(reload, [reload]);

  useEffect(() => {
    api.get<StoryStatus>('/api/stories/status').then(setStatus).catch(() => {});
    const socket = new ChatSocket((e) => {
      if (e.event === 'story_status') {
        setStatus(e as unknown as StoryStatus);
      } else if (e.event === 'story_updated') {
        setStatus((s) => (s ? { ...s, running: false } : s));
        reload();
      } else if (e.event === 'story_error') {
        setStatus((s) => (s ? { ...s, running: false } : s));
        setError(e.error || 'Generation failed');
      }
    });
    socket.connect();
    return () => socket.close();
  }, [reload]);

  const run = useCallback(async (stage: string, args: RunArgs = {}) => {
    setError('');
    setStatus({ running: true, step: '', status: 'Starting…', tokens: 0 });
    try {
      await api.post(`/api/stories/${id}/run`, { stage, ...args });
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Could not start');
      setStatus((s) => (s ? { ...s, running: false } : s));
    }
  }, [id]);

  /// Persist the full project (in-place edits). Optionally merge a [patch] and a
  /// [characterRoles] map (charDbId → role) that the server uses to rebuild the
  /// card snapshots. Reloads on success so the client resyncs.
  const save = useCallback(
    async (
      patch?: Partial<StoryProject>,
      characterRoles?: Record<string, string>,
    ): Promise<boolean> => {
      if (!project) return false;
      const body: Record<string, unknown> = { ...project, ...patch };
      if (characterRoles) body.character_roles = characterRoles;
      try {
        await api.post(`/api/stories/${id}`, body);
        reload();
        return true;
      } catch (e) {
        setError(e instanceof ApiError ? e.message : 'Save failed');
        return false;
      }
    },
    [id, project, reload],
  );

  return { project, status, error, run, save, reload };
}
