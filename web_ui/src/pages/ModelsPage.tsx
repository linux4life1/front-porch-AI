// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Models & backends page. Thin orchestrator over focused components:
// local backend status, hardware + recommendations, installed models
// (switch/delete), the HuggingFace browser + download queue, and image gen.

import { useCallback, useEffect, useState } from 'react';
import { api, ApiError } from '../api/client';
import { HardwarePanel } from '../components/models/HardwarePanel';
import { LocalModels } from '../components/models/LocalModels';
import { ModelDownloads } from '../components/models/ModelDownloads';
import { ImageGen } from '../components/models/ImageGen';
import { type BackendStatus } from '../components/models/types';

export function ModelsPage() {
  const [status, setStatus] = useState<BackendStatus | null>(null);
  const [error, setError] = useState('');
  // Search box state lives here so HardwarePanel's recommendation chips can drive
  // the downloader's search; the nonce bumps to (re)trigger a search on chip tap.
  const [query, setQuery] = useState('');
  const [searchNonce, setSearchNonce] = useState(0);

  const loadStatus = useCallback(
    () => api.get<BackendStatus>('/api/backend/status').then(setStatus).catch(() => {}),
    [],
  );
  useEffect(() => {
    void loadStatus();
  }, [loadStatus]);

  const pickQuery = (q: string) => {
    setQuery(q);
    setSearchNonce((n) => n + 1);
  };

  return (
    <div className="page">
      <h2>Models &amp; backends</h2>
      {error && <p className="error">{error}</p>}
      {status?.isLocal && <BackendStatusCard status={status} reload={loadStatus} onError={setError} />}
      <HardwarePanel onPickQuery={pickQuery} />
      <LocalModels isLocal={status?.isLocal ?? false} reloadStatus={loadStatus} onError={setError} />
      <ModelDownloads query={query} setQuery={setQuery} searchNonce={searchNonce} onError={setError} />
      <ImageGen onError={setError} />
    </div>
  );
}

function BackendStatusCard({
  status,
  reload,
  onError,
}: {
  status: BackendStatus;
  reload: () => Promise<void>;
  onError: (s: string) => void;
}) {
  const [busy, setBusy] = useState(false);
  const act = (path: string) => {
    setBusy(true);
    api.post(path)
      .then(() => reload())
      .catch((e) => onError(e instanceof ApiError ? e.message : 'Failed'))
      .finally(() => setBusy(false));
  };
  return (
    <section className="card">
      <h3>Local backend</h3>
      <p className="muted small">
        {status.running ? (status.modelReady ? 'Running · model ready' : `Running · ${status.statusMessage || 'loading…'}`) : 'Stopped'}
        {' · '}<strong>{status.loadedModel}</strong>
      </p>
      <div className="tool-row">
        <button disabled={busy || status.starting} onClick={() => act('/api/backend/restart')}>
          {status.starting ? 'Starting…' : 'Restart'}
        </button>
        <button disabled={busy || !status.running} onClick={() => act('/api/backend/stop')}>Stop</button>
      </div>
    </section>
  );
}
