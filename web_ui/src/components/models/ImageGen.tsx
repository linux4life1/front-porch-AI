// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Image-generation backend config + generate, with one-tap insert into the
// active chat. Thin over /api/image.

import { useEffect, useState } from 'react';
import { api, ApiError } from '../../api/client';

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

export function ImageGen({ onError }: { onError: (s: string) => void }) {
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
