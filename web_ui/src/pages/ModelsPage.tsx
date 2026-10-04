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
import { KoboldStatusCard } from '../components/models/KoboldStatusCard';
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

  // While the managed engine is downloading (or absent — a download can be
  // kicked off from the desktop at any moment), poll so the progress line
  // stays live without a manual refresh.
  const engineBusy = status ? status.engineInstalled === false || status.engineDownloading === true : false;
  useEffect(() => {
    if (!engineBusy) return;
    const t = setInterval(() => void loadStatus(), 2000);
    return () => clearInterval(t);
  }, [engineBusy, loadStatus]);

  const pickQuery = (q: string) => {
    setQuery(q);
    setSearchNonce((n) => n + 1);
  };

  return (
    <div className="page">
      <h2>Models &amp; backends</h2>
      {error && <p className="error">{error}</p>}
      {status?.isLocal && <BackendStatusCard status={status} reload={loadStatus} onError={setError} />}
      <KoboldStatusCard onError={setError} />
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
      {status.cpuOnlyLowPerf && (
        <div className="cpu-warn">
          <strong>⚠️ Slow performance expected on this PC</strong>
          This computer's CPU doesn't support AVX2 and has no NVIDIA GPU, so the local AI
          runs on the CPU only — AMD/Intel graphics can't be used by the compatible engine
          build. Replies may be very slow. A newer CPU or an NVIDIA GPU is recommended, or
          connect to a cloud model instead.
        </div>
      )}
      {/* Managed engine acquisition (first-launch rework): the binary no
          longer downloads at boot, so surface missing / downloading states
          here with an install action — the web twin of the desktop chip. */}
      {status.engineDownloading && (
        <p className="muted small">
          ⬇️ Downloading AI engine — {status.engineStatusMessage || `${Math.round((status.engineProgress ?? 0) * 100)}%`}
        </p>
      )}
      {status.engineInstalled === false && !status.engineDownloading && (
        <p className="muted small">
          {status.engineError
            ? `⚠️ Engine download failed: ${status.engineError} `
            : 'The AI engine isn’t installed yet — needed to run models on this computer. '}
          <button className="link-btn" disabled={busy} onClick={() => act('/api/backend/engine/install')}>
            {status.engineError ? 'Retry download' : 'Download engine'}
          </button>
        </p>
      )}
      <p className="muted small">
        {status.running ? (status.modelReady ? 'Running · model ready' : `Running · ${status.statusMessage || 'loading…'}`) : 'Stopped'}
        {' · '}<strong>{status.loadedModel}</strong>
      </p>
      <div className="tool-row">
        <button disabled={busy || status.starting || status.engineInstalled === false} onClick={() => act('/api/backend/restart')}>
          {status.starting ? 'Starting…' : 'Restart'}
        </button>
        <button disabled={busy || !status.running} onClick={() => act('/api/backend/stop')}>Stop</button>
      </div>
    </section>
  );
}
