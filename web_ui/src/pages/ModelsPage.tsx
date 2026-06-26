// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Models & backends page: local backend status + restart/stop, installed local
// model switching, a HuggingFace model browser/downloader (progress polled), and
// image-generation backend config + generate. Thin over /api/backend + /api/image.

import { useCallback, useEffect, useState } from 'react';
import { api, ApiError } from '../api/client';

interface BackendStatus {
  isLocal: boolean;
  running: boolean;
  starting: boolean;
  modelReady: boolean;
  statusMessage: string;
  loadedModel: string;
}
interface LocalModel {
  name: string;
  path: string;
  sizeBytes: number;
  quant: string;
  paramCountB: number | null;
  loaded: boolean;
}
interface HFModel {
  id: string;
  name: string;
  author: string;
  likes: number;
  downloads: number;
  description: string | null;
}
interface HFFile {
  filename: string;
  sizeBytes: number;
  repoId: string;
  quant: string;
}
interface Download {
  id: string;
  filename: string;
  state: string;
  progress: number;
  speedBytesPerSec: number;
  etaSeconds: number;
}

const fmtSize = (b: number) => (b >= 1e9 ? `${(b / 1e9).toFixed(1)} GB` : `${(b / 1e6).toFixed(0)} MB`);

export function ModelsPage() {
  const [status, setStatus] = useState<BackendStatus | null>(null);
  const [error, setError] = useState('');

  const loadStatus = useCallback(
    () => api.get<BackendStatus>('/api/backend/status').then(setStatus).catch(() => {}),
    [],
  );
  useEffect(() => {
    void loadStatus();
  }, [loadStatus]);

  return (
    <div className="page">
      <h2>Models &amp; backends</h2>
      {error && <p className="error">{error}</p>}
      {status?.isLocal && <BackendSection status={status} reload={loadStatus} onError={setError} />}
      <LocalModelsSection isLocal={status?.isLocal ?? false} reloadStatus={loadStatus} onError={setError} />
      <DownloaderSection onError={setError} />
      <ImageSection onError={setError} />
    </div>
  );
}

function BackendSection({ status, reload, onError }: { status: BackendStatus; reload: () => Promise<void>; onError: (s: string) => void }) {
  const [busy, setBusy] = useState(false);
  const act = (path: string) => {
    setBusy(true);
    api.post(path).then(() => reload()).catch((e) => onError(e instanceof ApiError ? e.message : 'Failed')).finally(() => setBusy(false));
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

function LocalModelsSection({ isLocal, reloadStatus, onError }: { isLocal: boolean; reloadStatus: () => Promise<void>; onError: (s: string) => void }) {
  const [models, setModels] = useState<LocalModel[]>([]);
  const [busy, setBusy] = useState(false);
  const load = () => api.get<{ models: LocalModel[] }>('/api/backend/models').then((r) => setModels(r.models)).catch(() => {});
  useEffect(() => {
    void load();
  }, []);

  const use = (m: LocalModel) => {
    if (!window.confirm(`Switch to "${m.name}"? This restarts the backend (~30s).`)) return;
    setBusy(true);
    api.post('/api/backend/models/switch', { path: m.path })
      .then(() => Promise.all([load(), reloadStatus()]))
      .catch((e) => onError(e instanceof ApiError ? e.message : 'Switch failed'))
      .finally(() => setBusy(false));
  };

  return (
    <section className="card">
      <h3>Installed models</h3>
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
              </div>
              {m.loaded ? (
                <span className="badge">Loaded</span>
              ) : (
                isLocal && <button disabled={busy} onClick={() => use(m)}>Use</button>
              )}
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

function DownloaderSection({ onError }: { onError: (s: string) => void }) {
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<HFModel[]>([]);
  const [searching, setSearching] = useState(false);
  const [expanded, setExpanded] = useState<string | null>(null);
  const [files, setFiles] = useState<HFFile[]>([]);
  const [downloads, setDownloads] = useState<Download[]>([]);

  const loadDownloads = useCallback(
    () => api.get<{ downloads: Download[] }>('/api/backend/downloads').then((r) => setDownloads(r.downloads)).catch(() => {}),
    [],
  );
  useEffect(() => {
    void loadDownloads();
  }, [loadDownloads]);

  // Poll while any download is active.
  const hasActive = downloads.some((d) => d.state === 'downloading' || d.state === 'pending' || d.state === 'verifying');
  useEffect(() => {
    if (!hasActive) return;
    const t = setInterval(() => void loadDownloads(), 1500);
    return () => clearInterval(t);
  }, [hasActive, loadDownloads]);

  const search = () => {
    const q = query.trim();
    if (!q) return;
    setSearching(true);
    api.get<{ models: HFModel[] }>(`/api/backend/hf/search?q=${encodeURIComponent(q)}`)
      .then((r) => setResults(r.models))
      .catch((e) => onError(e instanceof ApiError ? e.message : 'Search failed'))
      .finally(() => setSearching(false));
  };

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

  const download = (f: HFFile) =>
    api.post<{ downloads: Download[] }>('/api/backend/downloads', { repoId: f.repoId, filename: f.filename })
      .then((r) => setDownloads(r.downloads))
      .catch((e) => onError(e instanceof ApiError ? e.message : 'Could not queue download'));

  const cancel = (id: string) =>
    api.post<{ downloads: Download[] }>(`/api/backend/downloads/${id}/cancel`).then((r) => setDownloads(r.downloads)).catch(() => {});

  return (
    <section className="card">
      <h3>Download models (HuggingFace)</h3>
      {downloads.length > 0 && (
        <ul className="download-list">
          {downloads.map((d) => (
            <li key={d.id}>
              <div className="dl-head">
                <span className="dl-name">{d.filename}</span>
                <span className="muted small">
                  {d.state === 'downloading' ? `${Math.round(d.progress * 100)}% · ${fmtSize(d.speedBytesPerSec)}/s` : d.state}
                </span>
                {(d.state === 'downloading' || d.state === 'pending') && (
                  <button className="icon-btn" title="Cancel" onClick={() => cancel(d.id)}>✕</button>
                )}
              </div>
              <div className="stat-track"><div className="stat-fill" style={{ width: `${Math.round(d.progress * 100)}%` }} /></div>
            </li>
          ))}
        </ul>
      )}
      <div className="tool-row">
        <input
          placeholder="Search GGUF models…"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          onKeyDown={(e) => e.key === 'Enter' && search()}
        />
        <button className="primary" disabled={searching} onClick={search}>{searching ? '…' : 'Search'}</button>
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
                {files.length === 0 ? <li className="muted small">Loading files…</li> : files.map((f) => (
                  <li key={f.filename}>
                    <span className="small">{f.filename} <span className="muted">({fmtSize(f.sizeBytes)} · {f.quant})</span></span>
                    <button className="icon-btn" title="Download" onClick={() => download(f)}>⬇</button>
                  </li>
                ))}
              </ul>
            )}
          </li>
        ))}
      </ul>
    </section>
  );
}

function ImageSection({ onError }: { onError: (s: string) => void }) {
  interface ImageConfig {
    backend: string;
    isConfigured: boolean;
    size: string;
    model: string;
    localUrl: string;
    remoteApiUrl: string;
    remoteModelName: string;
    hasApiKey: boolean;
  }
  const [cfg, setCfg] = useState<ImageConfig | null>(null);
  const [prompt, setPrompt] = useState('');
  const [apiKey, setApiKey] = useState('');
  const [image, setImage] = useState<string | null>(null);
  const [filename, setFilename] = useState<string | null>(null);
  const [inserted, setInserted] = useState(false);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    api.get<ImageConfig>('/api/image/config').then(setCfg).catch(() => {});
  }, []);

  if (!cfg) return null;
  const set = (patch: Partial<ImageConfig>) => setCfg({ ...cfg, ...patch });
  const saveConfig = (patch: Record<string, unknown>) =>
    api.post<ImageConfig>('/api/image/config', patch).then(setCfg).catch((e) => onError(e instanceof ApiError ? e.message : 'Save failed'));

  const generate = () => {
    if (!prompt.trim()) return;
    setBusy(true);
    setImage(null);
    setFilename(null);
    setInserted(false);
    api.post<{ image: string; filename: string | null }>('/api/image/generate', { prompt })
      .then((r) => { setImage(r.image); setFilename(r.filename); })
      .catch((e) => onError(e instanceof ApiError ? e.message : 'Generation failed'))
      .finally(() => setBusy(false));
  };

  const insertIntoChat = () => {
    if (!filename) return;
    api.post('/api/chat/insert-image', { filename })
      .then(() => setInserted(true))
      .catch((e) => onError(e instanceof ApiError ? e.message : 'Could not insert into chat'));
  };

  return (
    <section className="card">
      <h3>Image generation</h3>
      <label>
        Backend
        <select value={cfg.backend} onChange={(e) => { set({ backend: e.target.value }); void saveConfig({ backend: e.target.value }); }}>
          <option value="remote">Remote API</option>
          <option value="a1111">Local (A1111)</option>
          <option value="drawthings">Local (Draw Things)</option>
        </select>
      </label>
      {cfg.backend === 'remote' ? (
        <>
          <label>
            API URL
            <input value={cfg.remoteApiUrl} onChange={(e) => set({ remoteApiUrl: e.target.value })} onBlur={() => saveConfig({ remoteApiUrl: cfg.remoteApiUrl })} />
          </label>
          <label>
            Image model
            <input value={cfg.remoteModelName} onChange={(e) => set({ remoteModelName: e.target.value })} onBlur={() => saveConfig({ remoteModelName: cfg.remoteModelName })} />
          </label>
          <label>
            API key {cfg.hasApiKey && <span className="muted small">(set — leave blank to keep)</span>}
            <input type="password" value={apiKey} onChange={(e) => setApiKey(e.target.value)} onBlur={() => apiKey && saveConfig({ apiKey })} />
          </label>
        </>
      ) : (
        <label>
          Local URL
          <input value={cfg.localUrl} onChange={(e) => set({ localUrl: e.target.value })} onBlur={() => saveConfig({ localUrl: cfg.localUrl })} />
        </label>
      )}
      <label>
        Prompt
        <textarea rows={3} value={prompt} onChange={(e) => setPrompt(e.target.value)} placeholder="Describe the image…" />
      </label>
      <button className="primary" disabled={busy || !prompt.trim()} onClick={generate}>
        {busy ? 'Generating…' : 'Generate'}
      </button>
      {image && (
        <div className="image-result">
          <img src={image} alt="Generated" />
          <div className="image-result-actions">
            <a className="help-link" href={image} download="generated.png">Download</a>
            {filename && (
              <button className="secondary" disabled={inserted} onClick={insertIntoChat}>
                {inserted ? 'Inserted ✓' : 'Insert into chat'}
              </button>
            )}
          </div>
        </div>
      )}
    </section>
  );
}
