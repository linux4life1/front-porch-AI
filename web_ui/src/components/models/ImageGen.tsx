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
  style: string;
  model: string;
  negativePrompt: string;
  steps: number;
  cfgScale: number;
  sampler: string;
  localUrl: string;
  drawThingsHost: string;
  drawThingsPort: number;
  remoteApiUrl: string;
  remoteModelName: string;
  hasApiKey: boolean;
}

// Mirrors ImageGenService.styleLabels (desktop) + the Image Studio size list.
const STYLES: Record<string, string> = {
  photorealistic: 'Photorealistic',
  anime: 'Anime / Manga',
  fantasy_art: 'Fantasy Art',
  oil_painting: 'Oil Painting',
  digital_art: 'Digital Art',
  watercolor: 'Watercolor',
};
const SIZES = ['512x512', '768x768', '1024x1024', '1536x1024', '1024x1536'];

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
      ) : cfg.backend === 'a1111' ? (
        <>
          <label>
            A1111 URL
            <input value={cfg.localUrl} onChange={(e) => set({ localUrl: e.target.value })} onBlur={() => saveConfig({ localUrl: cfg.localUrl })} placeholder="http://127.0.0.1:7860" />
          </label>
          <label>
            Model <span className="muted small">(checkpoint, optional)</span>
            <input value={cfg.model} onChange={(e) => set({ model: e.target.value })} onBlur={() => saveConfig({ model: cfg.model })} />
          </label>
        </>
      ) : (
        <>
          <div className="img-row2">
            <label>
              Draw Things host
              <input value={cfg.drawThingsHost} onChange={(e) => set({ drawThingsHost: e.target.value })} onBlur={() => saveConfig({ drawThingsHost: cfg.drawThingsHost })} placeholder="127.0.0.1" />
            </label>
            <label>
              gRPC port
              <input type="number" value={cfg.drawThingsPort} onChange={(e) => set({ drawThingsPort: Number(e.target.value) })} onBlur={() => cfg.drawThingsPort > 0 && saveConfig({ drawThingsPort: cfg.drawThingsPort })} />
            </label>
          </div>
          <label>
            Model <span className="muted small">(optional)</span>
            <input value={cfg.model} onChange={(e) => set({ model: e.target.value })} onBlur={() => saveConfig({ model: cfg.model })} />
          </label>
        </>
      )}

      <label>
        Art style
        <select value={STYLES[cfg.style] ? cfg.style : 'photorealistic'} onChange={(e) => { set({ style: e.target.value }); void saveConfig({ style: e.target.value }); }}>
          {Object.entries(STYLES).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
        </select>
      </label>
      <div className="img-row2">
        <label>
          Size
          <select value={cfg.size} onChange={(e) => { set({ size: e.target.value }); void saveConfig({ size: e.target.value }); }}>
            {SIZES.map((s) => <option key={s} value={s}>{s}</option>)}
          </select>
        </label>
        <label>
          Sampler
          <input value={cfg.sampler} onChange={(e) => set({ sampler: e.target.value })} onBlur={() => saveConfig({ sampler: cfg.sampler })} placeholder="Euler a" />
        </label>
      </div>
      <div className="img-row2">
        <label>
          Steps
          <input type="number" min={1} max={150} value={cfg.steps} onChange={(e) => set({ steps: Number(e.target.value) })} onBlur={() => cfg.steps > 0 && saveConfig({ steps: cfg.steps })} />
        </label>
        <label>
          CFG scale
          <input type="number" min={1} max={30} step={0.5} value={cfg.cfgScale} onChange={(e) => set({ cfgScale: Number(e.target.value) })} onBlur={() => cfg.cfgScale > 0 && saveConfig({ cfgScale: cfg.cfgScale })} />
        </label>
      </div>
      <label>
        Negative prompt
        <textarea rows={2} value={cfg.negativePrompt} onChange={(e) => set({ negativePrompt: e.target.value })} onBlur={() => saveConfig({ negativePrompt: cfg.negativePrompt })} />
      </label>

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
