// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Installed local .gguf models: switch the loaded one (local backends) or delete
// any that isn't currently loaded. Also shows where models live (read-only — the
// folder is a host-only setting on an internet-exposable server).

import { useEffect, useState } from 'react';
import { api, ApiError } from '../../api/client';
import { type LocalModelFile, type ModelSwitch, fmtSize } from './types';

export function LocalModels({
  isLocal,
  reloadStatus,
  onError,
}: {
  isLocal: boolean;
  reloadStatus: () => Promise<void>;
  onError: (s: string) => void;
}) {
  const [models, setModels] = useState<LocalModelFile[]>([]);
  const [folder, setFolder] = useState<string>('');
  const [busy, setBusy] = useState(false);
  // Why the running KoboldCpp could not load the model just switched to, shown
  // in that model's row.
  const [refused, setRefused] = useState<{ path: string; words: string } | null>(null);

  const load = () => api.get<{ models: LocalModelFile[] }>('/api/backend/models').then((r) => setModels(r.models)).catch(() => {});
  useEffect(() => {
    void load();
    api.get<{ path: string }>('/api/backend/models-folder').then((r) => setFolder(r.path)).catch(() => {});
  }, []);

  const use = (m: LocalModelFile) => {
    if (!window.confirm(`Switch to "${m.name}"? This restarts the backend (~30s).`)) return;
    setBusy(true);
    setRefused(null);
    api.post<ModelSwitch>('/api/backend/models/switch', { path: m.path })
      .then((r) => {
        setRefused(r.refused ? { path: m.path, words: r.refused } : null);
        return Promise.all([load(), reloadStatus()]);
      })
      .catch((e) => onError(e instanceof ApiError ? e.message : 'Switch failed'))
      .finally(() => setBusy(false));
  };

  const del = (m: LocalModelFile) => {
    if (!window.confirm(`Delete "${m.name}"? This permanently removes the file from disk.`)) return;
    setBusy(true);
    api.post<{ models: LocalModelFile[] }>('/api/backend/models/delete', { path: m.path })
      .then((r) => setModels(r.models))
      .catch((e) => onError(e instanceof ApiError ? e.message : 'Delete failed'))
      .finally(() => setBusy(false));
  };

  return (
    <section className="card">
      <h3>Installed models</h3>
      {folder && <p className="muted small mono-path">{folder}</p>}
      {models.length === 0 ? (
        <p className="muted">No local models found.</p>
      ) : (
        <ul className="model-list">
          {models.map((m) => (
            <li key={m.path}>
              <div className="model-info">
                <strong>{m.name}</strong>
                <span className="muted small">
                  {fmtSize(m.sizeBytes)} · {m.quant}{m.paramCountB ? ` · ${m.paramCountB}B` : ''}
                </span>
                {refused?.path === m.path && (
                  <span className="error small" role="alert" data-testid="switch-refused" style={{ whiteSpace: 'pre-line' }}>
                    {refused.words}
                  </span>
                )}
              </div>
              <div className="model-actions">
                {m.loaded ? (
                  <span className="badge">Loaded</span>
                ) : (
                  <>
                    {isLocal && <button disabled={busy} onClick={() => use(m)}>Use</button>}
                    <button className="danger-btn" disabled={busy} title="Delete model" onClick={() => del(m)}>🗑</button>
                  </>
                )}
              </div>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
