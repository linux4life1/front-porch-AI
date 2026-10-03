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
  /** Stage-specific extras (sequence, directive, protect, refinement, name). */
  [key: string]: unknown;
}

/** Fired after a save made outside a page's own `useStory` (the studio header's Rename). */
const SAVED_EVENT = 'story-saved';

/// Save a whole project from somewhere that has no `useStory` of its own (the
/// shell's Rename). Every `useStory` showing that story reloads, so no page
/// keeps the old title and writes it back on its next save.
export async function saveStoryProject(id: string, body: Record<string, unknown>): Promise<void> {
  await api.post(`/api/stories/${id}`, body);
  window.dispatchEvent(new CustomEvent(SAVED_EVENT, { detail: id }));
}

/// Rename through the title-only route. A whole-project write from the shelf
/// or the header could overwrite a run in progress; this one touches nothing
/// else. Pages showing the story reload the same way as after a save.
export async function renameStory(id: string, title: string): Promise<void> {
  await api.post(`/api/stories/${id}/rename`, { title });
  window.dispatchEvent(new CustomEvent(SAVED_EVENT, { detail: id }));
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
    const onSaved = (e: Event) => { if ((e as CustomEvent<string>).detail === id) reload(); };
    window.addEventListener(SAVED_EVENT, onSaved);
    return () => window.removeEventListener(SAVED_EVENT, onSaved);
  }, [id, reload]);

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
      } else if (e.event === 'connected') {
        // (Re)connected — a `story_updated`/`story_status` may have fired while
        // the socket was down. Re-pull status + project so a finished (or
        // progressed) pipeline isn't shown as stuck.
        api.get<StoryStatus>('/api/stories/status').then(setStatus).catch(() => {});
        reload();
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

  /// Ask the running stage to stop at its next safe point; the status
  /// stream flips `stopping` until it does.
  const stop = useCallback(async () => {
    try {
      const s = await api.post<StoryStatus>(`/api/stories/${id}/stop`, {});
      setStatus(s);
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Could not stop');
    }
  }, [id]);

  return { project, status, error, run, stop, save, reload };
}
