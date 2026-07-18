// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// HuggingFace model browser + the live download queue. Matches the desktop
// manager: per-task pause / resume / cancel, bulk pause-all / resume-all /
// clear-completed, an overall progress bar, and per-task size / ETA / errors.
// Progress is polled (1.2s) only while something is active.

import { useCallback, useEffect, useState } from 'react';
import { api, ApiError } from '../../api/client';
import { type HFModel, type HFFile, type Download, type DownloadsState, fmtSize, fmtEta } from './types';

const EMPTY: DownloadsState = { downloads: [], overallProgress: 0, overallSpeed: 0, activeCount: 0 };
const ACTIVE = new Set(['downloading', 'pending', 'verifying']);

export function ModelDownloads({
  query,
  setQuery,
  searchNonce,
  onError,
}: {
  query: string;
  setQuery: (q: string) => void;
  searchNonce: number;
  onError: (s: string) => void;
}) {
  const [results, setResults] = useState<HFModel[]>([]);
  const [searching, setSearching] = useState(false);
  const [expanded, setExpanded] = useState<string | null>(null);
  const [files, setFiles] = useState<HFFile[]>([]);
  const [dl, setDl] = useState<DownloadsState>(EMPTY);

  const loadDownloads = useCallback(
    () => api.get<DownloadsState>('/api/backend/downloads').then(setDl).catch(() => {}),
    [],
  );
  useEffect(() => {
    void loadDownloads();
  }, [loadDownloads]);

  const hasActive = dl.downloads.some((d) => ACTIVE.has(d.state));
  useEffect(() => {
    if (!hasActive) return;
    const t = setInterval(() => void loadDownloads(), 1200);
    return () => clearInterval(t);
  }, [hasActive, loadDownloads]);

  const search = useCallback(
    (q: string) => {
      const t = q.trim();
      if (!t) return;
      setSearching(true);
      setExpanded(null);
      api.get<{ models: HFModel[] }>(`/api/backend/hf/search?q=${encodeURIComponent(t)}`)
        .then((r) => setResults(r.models))
        .catch((e) => onError(e instanceof ApiError ? e.message : 'Search failed'))
        .finally(() => setSearching(false));
    },
    [onError],
  );

  // A recommended-chip click (HardwarePanel) bumps searchNonce → run that search.
  useEffect(() => {
    if (searchNonce > 0) search(query);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [searchNonce]);

  const expand = (id: string) => {
    if (expanded === id) {
      setExpanded(null);
      return;
    }
    setExpanded(id);
    setFiles([]);
    api.get<{ files: HFFile[] }>(`/api/backend/hf/files?repoId=${encodeURIComponent(id)}`)
      .then((r) => setFiles(r.files))
      .catch(() => setFiles([]));
  };

  // Every queue mutation returns the fresh DownloadsState — just swap it in.
  const mutate = (p: Promise<DownloadsState>) =>
    p.then(setDl).catch((e) => onError(e instanceof ApiError ? e.message : 'Action failed'));
  const download = (f: HFFile) =>
    mutate(api.post<DownloadsState>('/api/backend/downloads', { repoId: f.repoId, filename: f.filename }));
  const taskAct = (id: string, verb: string) => mutate(api.post<DownloadsState>(`/api/backend/downloads/${id}/${verb}`));
  const bulk = (verb: string) => mutate(api.post<DownloadsState>(`/api/backend/downloads/${verb}`));

  const hasCompleted = dl.downloads.some((d) => ['completed', 'failed', 'cancelled'].includes(d.state));

  return (
    <section className="card">
      <h3>Download models (HuggingFace)</h3>

      {dl.downloads.length > 0 && (
        <div className="dl-queue">
          {dl.activeCount > 0 && (
            <div className="dl-overall">
              <div className="dl-overall-head">
                <span className="muted small">{dl.activeCount} active · {fmtSize(dl.overallSpeed)}/s</span>
                <span className="muted small">{Math.round(dl.overallProgress * 100)}%</span>
              </div>
              <div className="stat-track"><div className="stat-fill" style={{ width: `${Math.round(dl.overallProgress * 100)}%` }} /></div>
            </div>
          )}
          <div className="dl-bulk">
            <button className="ghost small-btn" onClick={() => bulk('pause-all')}>Pause all</button>
            <button className="ghost small-btn" onClick={() => bulk('resume-all')}>Resume all</button>
            {hasCompleted && <button className="ghost small-btn" onClick={() => bulk('clear-completed')}>Clear finished</button>}
          </div>
          <ul className="download-list">
            {dl.downloads.map((d) => (
              <DownloadRow key={d.id} d={d} onAct={taskAct} />
            ))}
          </ul>
        </div>
      )}

      <div className="tool-row">
        <input
          placeholder="Search GGUF models…"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          onKeyDown={(e) => e.key === 'Enter' && search(query)}
        />
        <button className="primary" disabled={searching} onClick={() => search(query)}>{searching ? '…' : 'Search'}</button>
      </div>

      <ul className="hf-list">
        {results.map((m) => (
          <li key={m.id} className="card hf-row">
            <button className="hf-head" onClick={() => expand(m.id)}>
              <strong>{m.name}</strong>
              <span className="muted small">{m.author} · ♥ {m.likes} · ↓ {m.downloads}</span>
            </button>
            {expanded === m.id && (
              <ul className="file-list">
                {files.length === 0 ? (
                  <li className="muted small">Loading files…</li>
                ) : (
                  files.map((f) => (
                    <li key={f.filename}>
                      <span className="small">{f.filename} <span className="muted">({fmtSize(f.sizeBytes)} · {f.quant})</span></span>
                      <button className="icon-btn" title="Download" onClick={() => download(f)}>⬇</button>
                    </li>
                  ))
                )}
              </ul>
            )}
          </li>
        ))}
      </ul>
    </section>
  );
}

function DownloadRow({ d, onAct }: { d: Download; onAct: (id: string, verb: string) => void }) {
  const pct = Math.round(d.progress * 100);
  const sizeLabel =
    d.totalBytes > 0 ? `${fmtSize(d.bytesDownloaded)} / ${fmtSize(d.totalBytes)}` : '';
  const detail =
    d.state === 'downloading'
      ? `${pct}% · ${fmtSize(d.speedBytesPerSec)}/s · ETA ${fmtEta(d.etaSeconds)}`
      : d.state === 'paused'
        ? `Paused · ${pct}%`
        : d.state === 'failed'
          ? `Failed${d.errorMessage ? `: ${d.errorMessage}` : ''}`
          : d.status;

  return (
    <li className={`dl-item state-${d.state}`}>
      <div className="dl-head">
        <span className="dl-name" title={d.repoId ?? undefined}>{d.filename}</span>
        <div className="dl-controls">
          {d.state === 'downloading' && <button className="icon-btn" title="Pause" onClick={() => onAct(d.id, 'pause')}>⏸</button>}
          {(d.state === 'paused' || d.state === 'failed') && <button className="icon-btn" title="Resume" onClick={() => onAct(d.id, 'resume')}>▶</button>}
          {!['completed', 'cancelled'].includes(d.state) && <button className="icon-btn" title="Cancel" onClick={() => onAct(d.id, 'cancel')}>✕</button>}
        </div>
      </div>
      <div className="dl-sub">
        <span className={`muted small${d.state === 'failed' ? ' dl-err' : ''}`}>{detail}</span>
        {sizeLabel && <span className="muted small">{sizeLabel}</span>}
      </div>
      <div className="stat-track"><div className={`stat-fill${d.state === 'failed' ? ' danger' : ''}`} style={{ width: `${pct}%` }} /></div>
    </li>
  );
}
