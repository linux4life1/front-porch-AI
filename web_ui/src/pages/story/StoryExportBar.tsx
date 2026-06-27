// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Export bar for the bible dashboard: text / markdown / EPUB downloads plus a
// host-bound audiobook (.wav) compile with live progress over the WS hub.
// Mirrors the desktop dashboard exports — all synthesis runs on the host.

import { useEffect, useState } from 'react';
import { api, ApiError } from '../../api/client';
import { ChatSocket } from '../../api/ws';
import { exportText, exportEpub, downloadBlob } from './storyUtil';

export function StoryExportBar({ id, title }: { id: string; title: string }) {
  const [error, setError] = useState('');
  const [abBusy, setAbBusy] = useState(false);
  const [abProgress, setAbProgress] = useState(0);
  const [abStatus, setAbStatus] = useState('');

  useEffect(() => {
    const socket = new ChatSocket((e) => {
      if (e.id !== id) return;
      if (e.event === 'story_audiobook_status') {
        if (e.generating) setAbBusy(true);
        if (typeof e.progress === 'number') setAbProgress(e.progress);
        if (e.status) setAbStatus(e.status);
      } else if (e.event === 'story_audiobook_ready') {
        setAbBusy(false);
        setAbStatus('Downloading…');
        download();
      } else if (e.event === 'story_audiobook_error') {
        setAbBusy(false);
        setError(e.error || 'Audiobook failed');
      }
    });
    socket.connect();
    return () => socket.close();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [id]);

  const safe = (title || 'story').replace(/[^\w.-]+/g, '_');

  const download = async () => {
    try {
      const blob = await api.getForBlob(`/api/stories/${id}/audiobook`);
      downloadBlob(blob, `audiobook_${safe}.wav`);
      setAbStatus('');
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Audiobook download failed');
    }
  };

  const wrap = (fn: () => Promise<void>) => async () => {
    setError('');
    try {
      await fn();
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Export failed');
    }
  };

  const startAudiobook = async () => {
    setError('');
    setAbProgress(0);
    setAbStatus('Starting…');
    setAbBusy(true);
    try {
      await api.post(`/api/stories/${id}/audiobook`);
    } catch (e) {
      setAbBusy(false);
      setError(e instanceof ApiError ? e.message : 'Could not start audiobook');
    }
  };

  return (
    <section className="card">
      <h3>Export</h3>
      <div className="btn-row">
        <button className="ghost" onClick={wrap(() => exportText(id, 'text', title))}>Download .txt</button>
        <button className="ghost" onClick={wrap(() => exportText(id, 'markdown', title))}>Download .md</button>
        <button className="ghost" onClick={wrap(() => exportEpub(id, title))}>Export eBook (.epub)</button>
        <button className="ghost" disabled={abBusy} onClick={startAudiobook}>
          {abBusy ? 'Compiling…' : 'Export Audiobook (.wav)'}
        </button>
        {abBusy && (
          <button className="ghost" onClick={() => api.post(`/api/stories/${id}/audiobook/cancel`).catch(() => {})}>
            Stop
          </button>
        )}
      </div>
      {abBusy && (
        <div className="ab-progress" style={{ marginTop: 10 }}>
          <span className="muted small">{abStatus}</span>
          <div className="ab-bar"><span style={{ width: `${Math.round(abProgress * 100)}%` }} /></div>
        </div>
      )}
      {error && <p className="error">{error}</p>}
    </section>
  );
}
