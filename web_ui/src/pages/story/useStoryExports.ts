// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The one export implementation, reached from the studio header's ⋯ (and the
// reader): eBook and text download straight away; the audiobook compiles on
// the host with live progress over the WS hub, then downloads when ready.

import { useCallback, useEffect, useRef, useState } from 'react';
import { api, ApiError } from '../../api/client';
import { ChatSocket } from '../../api/ws';
import { downloadBlob, exportEpub, exportText, safeDownloadStem } from './storyUtil';

export function useStoryExports(id: string, title: string) {
  const [error, setError] = useState('');
  const [compiling, setCompiling] = useState(false);
  const [progress, setProgress] = useState(0);
  const stem = useRef(safeDownloadStem(title, 'story'));
  useEffect(() => { stem.current = safeDownloadStem(title, 'story'); }, [title]);

  useEffect(() => {
    const download = async () => {
      try {
        const blob = await api.getForBlob(`/api/stories/${id}/audiobook`);
        downloadBlob(blob, `audiobook_${stem.current}.wav`);
      } catch (e) {
        setError(e instanceof ApiError ? e.message : 'The audiobook could not be downloaded');
      }
    };
    const socket = new ChatSocket((e) => {
      if (e.id !== id) return;
      if (e.event === 'story_audiobook_status') {
        if (e.generating) setCompiling(true);
        if (typeof e.progress === 'number') setProgress(e.progress);
      } else if (e.event === 'story_audiobook_ready') {
        setCompiling(false);
        void download();
      } else if (e.event === 'story_audiobook_error') {
        setCompiling(false);
        setError(e.error || 'The audiobook could not be made');
      }
    });
    socket.connect();
    return () => socket.close();
  }, [id]);

  const attempt = useCallback((work: () => Promise<void>, fallback: string) => async () => {
    setError('');
    try {
      await work();
    } catch (e) {
      setError(e instanceof ApiError ? e.message : fallback);
    }
  }, []);

  return {
    error,
    clearError: () => setError(''),
    /** Compiling the audiobook; `progress` is 0..1. */
    compiling,
    progress,
    epub: attempt(() => exportEpub(id, title), 'The eBook could not be made'),
    markdown: attempt(() => exportText(id, 'markdown', title), 'The text could not be exported'),
    audiobook: attempt(async () => {
      setProgress(0);
      setCompiling(true);
      try {
        await api.post(`/api/stories/${id}/audiobook`);
      } catch (e) {
        setCompiling(false);
        throw e;
      }
    }, 'The audiobook could not be started'),
    abort: () => {
      setCompiling(false);
      api.post(`/api/stories/${id}/audiobook/cancel`).catch(() => undefined);
    },
  };
}
