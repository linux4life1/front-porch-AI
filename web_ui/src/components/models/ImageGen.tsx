// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Image-generation desk + generate, with one-tap insert into the active chat.
// Thin over /api/image.

import { useEffect, useRef, useState, type ReactNode } from 'react';
import { api, ApiError } from '../../api/client';
import { StudioDesk, type GenerateRequest } from './StudioDesk';
import { PackBanner } from './studio/PackBanner';
import { RecentShelf, type RecentEntry } from './studio/RecentShelf';
import type { ImageConfig } from './studio/types';

const PROGRESS_MS = 1000;

export function ImageGen({
  onError,
  progressMs = PROGRESS_MS,
  batch,
}: {
  onError: (s: string) => void;
  /** The Batch tab, when the desk is Image Studio's own page. */
  batch?: ReactNode;
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
  // The Recent shelf picture on show (the computer keeps every result there).
  const [recent, setRecent] = useState<{ name: string; kept: boolean } | null>(null);
  const [recentKey, setRecentKey] = useState(0);
  const [editPicture, setEditPicture] = useState<{ name: string; url: string; seq: number } | null>(null);
  const live = useRef(true);

  useEffect(() => {
    live.current = true;
    api
      .get<ImageConfig>('/api/image/config')
      .then((next) => live.current && setCfg(withGraphDefaults(next)))
      .catch((e) => console.warn('[image] config load failed', e));
    api
      .get<{ totpEnabled?: boolean }>('/api/auth/state')
      .then((st) => live.current && setTotpEnabled(!!st.totpEnabled))
      .catch((e) => console.warn('[image] auth state load failed', e));
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
        // Best-effort progress: the next tick asks again, so a miss is not logged.
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
        api
          .get<ImageConfig>('/api/image/config')
          .then(setCfg)
          .catch((err) => console.warn('[image] config reload after failed save failed', err));
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
    setRecent(null);
    api
      .post<{ image: string; filename: string | null; recent?: { name: string; kept: boolean } }>('/api/image/generate', body)
      .then((r) => {
        setImage(r.image);
        setFilename(r.filename);
        setRecent(r.recent ? { name: r.recent.name, kept: r.recent.kept } : null);
        setRecentKey((k) => k + 1);
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

  const restore = (entry: RecentEntry) => {
    setImage(entry.url);
    setFilename(entry.name);
    setPrompt(entry.prompt);
    setInserted(false);
    setGenError('');
    setRecent({ name: entry.name, kept: entry.kept });
  };

  const toggleStar = () => {
    if (!recent) return;
    api
      .post('/api/image/recent/keep', { name: recent.name, kept: !recent.kept })
      .then(() => {
        setRecent({ ...recent, kept: !recent.kept });
        setRecentKey((k) => k + 1);
      })
      .catch((e) => onError(e instanceof ApiError ? e.message : 'Could not star that picture.'));
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
        batch={batch}
        prompt={prompt}
        onPrompt={setPrompt}
        onGenerate={generate}
        generateError={genError}
        busy={busy}
        progress={progress}
        lastSaved={filename ? { name: filename, url: `/api/image/saved/${encodeURIComponent(filename)}` } : null}
        editPicture={editPicture}
        result={
          <>
          {image ? (
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
                {recent && (
                  <button type="button" className="secondary" aria-pressed={recent.kept} onClick={toggleStar}>
                    {recent.kept ? '★ Starred' : '☆ Star'}
                  </button>
                )}
              </div>
            </div>
          ) : null}
          <RecentShelf
            refreshKey={recentKey}
            selected={image ? recent?.name ?? null : null}
            onRestore={restore}
            onEdit={(entry) => setEditPicture({ name: entry.name, url: entry.url, seq: Date.now() })}
            onChanged={(entries) =>
              setRecent((now) => {
                const match = now && entries.find((e) => e.name === now.name);
                return match && match.kept !== now.kept ? { ...now, kept: match.kept } : now;
              })
            }
            onError={onError}
          />
          </>
        }
      />
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
