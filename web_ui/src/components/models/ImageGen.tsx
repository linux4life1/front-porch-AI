// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Image-generation desk + generate, with one-tap insert into the active chat.
// Thin over /api/image.

import { useEffect, useRef, useState } from 'react';
import { api, ApiError } from '../../api/client';
import { ImageRemoteFields } from './ImageRemoteFields';
import { StudioDesk, type GenerateRequest } from './StudioDesk';
import { PackBanner } from './studio/PackBanner';
import type { ImageConfig } from './studio/types';

const PROGRESS_MS = 1000;

export function ImageGen({
  onError,
  progressMs = PROGRESS_MS,
}: {
  onError: (s: string) => void;
  /** How often progress is asked for while a picture is made; for tests. */
  progressMs?: number;
}) {
  const [cfg, setCfg] = useState<ImageConfig | null>(null);
  const [prompt, setPrompt] = useState('');
  const [image, setImage] = useState<string | null>(null);
  const [filename, setFilename] = useState<string | null>(null);
  const [inserted, setInserted] = useState(false);
  const [busy, setBusy] = useState(false);
  const [progress, setProgress] = useState<number | null>(null);
  const [genError, setGenError] = useState('');
  const [totpEnabled, setTotpEnabled] = useState(false);
  const live = useRef(true);

  useEffect(() => {
    live.current = true;
    api
      .get<ImageConfig>('/api/image/config')
      .then((next) => live.current && setCfg(withGraphDefaults(next)))
      .catch(() => {});
    api
      .get<{ totpEnabled?: boolean }>('/api/auth/state')
      .then((st) => live.current && setTotpEnabled(!!st.totpEnabled))
      .catch(() => {});
    return () => {
      live.current = false;
    };
  }, []);

  // While a picture is being made, ask how far it is. Reading only.
  useEffect(() => {
    if (!busy) {
      setProgress(null);
      return;
    }
    let stop = false;
    const timer = window.setInterval(() => {
      api
        .get<ImageConfig>('/api/image/config')
        .then((c) => !stop && setProgress(typeof c.genProgress === 'number' ? c.genProgress : null))
        .catch(() => {});
    }, progressMs);
    return () => {
      stop = true;
      window.clearInterval(timer);
    };
  }, [busy, progressMs]);

  if (!cfg) return null;

  const save = (patch: Record<string, unknown>) => {
    // A change is shown at once, except one that needs the password: that one
    // is a draft on the desk until the computer accepts it.
    if (!('currentPassword' in patch)) {
      setCfg((prev) => (prev ? { ...prev, ...(patch as Partial<ImageConfig>) } : prev));
    }
    return api
      .post<ImageConfig>('/api/image/config', patch)
      .then((next) => {
        setCfg(next);
        return true;
      })
      .catch((e: unknown) => {
        if (e instanceof ApiError && e.payload.totpRequired === true) setTotpEnabled(true);
        onError(e instanceof ApiError ? e.message : 'Save failed');
        api.get<ImageConfig>('/api/image/config').then(setCfg).catch(() => {});
        return false;
      });
  };

  const generate = ({ mode, picture }: GenerateRequest) => {
    const body: Record<string, unknown> = { prompt, mode };
    if (picture?.kind === 'file') body.referenceImage = picture.dataUrl;
    if (picture?.kind === 'saved') body.referenceFilename = picture.name;
    setBusy(true);
    setGenError('');
    setImage(null);
    setFilename(null);
    setInserted(false);
    api
      .post<{ image: string; filename: string | null }>('/api/image/generate', body)
      .then((r) => {
        setImage(r.image);
        setFilename(r.filename);
      })
      .catch((e: unknown) => {
        const message = e instanceof ApiError ? e.message : 'Generation failed';
        setGenError(message);
        onError(message);
      })
      .finally(() => setBusy(false));
  };

  const insertIntoChat = () => {
    if (!filename) return;
    // prompt rides along so the chat image carries the same hover/copyable
    // prompt the desktop attaches (older servers ignore the extra field).
    api
      .post('/api/chat/insert-image', { filename, prompt })
      .then(() => setInserted(true))
      .catch((e) => onError(e instanceof ApiError ? e.message : 'Could not insert into chat'));
  };

  return (
    <section className="card">
      <h3>Image generation</h3>
      <PackBanner />
      <StudioDesk
        cfg={cfg}
        onConfig={setCfg}
        save={save}
        totpEnabled={totpEnabled}
        prompt={prompt}
        onPrompt={setPrompt}
        onGenerate={generate}
        generateError={genError}
        busy={busy}
        progress={progress}
        lastSaved={filename ? { name: filename, url: `/api/image/saved/${encodeURIComponent(filename)}` } : null}
        result={
          image ? (
            <div className="image-result">
              <img src={image} alt="Generated" />
              <div className="image-result-actions">
                <a className="help-link" href={image} download="generated.png">
                  Download
                </a>
                {filename && (
                  <button className="secondary" disabled={inserted} onClick={insertIntoChat}>
                    {inserted ? 'Inserted ✓' : 'Insert into chat'}
                  </button>
                )}
              </div>
            </div>
          ) : null
        }
      />
      {cfg.backend === 'remote' && (
        <ImageRemoteFields
          selectedHostId={cfg.imageRemoteHost ?? ''}
          hosts={cfg.imageRemoteHosts ?? []}
          modelId={cfg.model}
          hasApiKey={cfg.hasApiKey}
          remoteApiUrl={cfg.remoteApiUrl}
          onHost={(id) => void save({ imageRemoteHost: id })}
          onModel={(id) => void save({ model: id })}
          onError={onError}
        />
      )}
    </section>
  );
}

/** A computer that does not name the graphs on its desk gets the built-in ones. */
function withGraphDefaults(cfg: ImageConfig): ImageConfig {
  return {
    ...cfg,
    comfyCreateWorkflowId: cfg.comfyCreateWorkflowId ?? 'sd',
    comfyEditWorkflowId: cfg.comfyEditWorkflowId ?? 'qwen_image_edit',
  };
}
