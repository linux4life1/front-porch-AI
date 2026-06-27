// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Avatar / expression-image manager for the character edit page: list a
// character's avatars, upload new ones (with an optional emotion label), mark
// the prime (default) one, and delete. Mirrors the desktop avatars dialog —
// including the interactive crop step (ImageCropModal) shown before upload, the
// web mirror of the desktop ImageCropDialog.

import { useEffect, useRef, useState } from 'react';
import { api } from '../api/client';
import { ImageCropModal } from './ImageCropModal';

interface AvatarItem {
  id: string;
  label: string;
  displayOrder: number;
  isPrime: boolean;
}

export function AvatarManager({ characterId }: { characterId: string }) {
  const [avatars, setAvatars] = useState<AvatarItem[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [pending, setPending] = useState<File | null>(null);
  const fileRef = useRef<HTMLInputElement>(null);
  const labelRef = useRef<HTMLInputElement>(null);

  const load = () =>
    api
      .get<{ avatars: AvatarItem[] }>(`/api/characters/${characterId}/avatars`)
      .then((r) => setAvatars(r.avatars))
      .catch(() => {});

  useEffect(() => {
    void load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [characterId]);

  // Receives the cropped PNG blob from ImageCropModal, names it, and uploads.
  const upload = async (blob: Blob) => {
    setPending(null);
    setBusy(true);
    setError('');
    const label = (labelRef.current?.value ?? '').trim();
    const q = label ? `?label=${encodeURIComponent(label)}` : '';
    try {
      const file = new File([blob], 'avatar.png', { type: blob.type || 'image/png' });
      const r = await api.upload<{ avatars: AvatarItem[] }>(
        `/api/characters/${characterId}/avatars${q}`,
        file,
      );
      setAvatars(r.avatars);
      if (labelRef.current) labelRef.current.value = '';
    } catch {
      setError('Upload failed (PNG/JPG, under 32 MB).');
    } finally {
      setBusy(false);
    }
  };

  const act = (p: Promise<{ avatars: AvatarItem[] }>) => {
    setBusy(true);
    p.then((r) => setAvatars(r.avatars))
      .catch(() => setError('Action failed.'))
      .finally(() => setBusy(false));
  };

  return (
    <div className="avatar-manager">
      <div className="avatar-grid">
        {avatars.map((a) => (
          <div key={a.id} className={`avatar-tile${a.isPrime ? ' prime' : ''}`}>
            <img src={`/api/characters/${characterId}/avatars/${a.id}/image`} alt={a.label} />
            {a.label && <span className="avatar-label">{a.label}</span>}
            {a.isPrime && <span className="avatar-badge">Prime</span>}
            <div className="avatar-actions">
              {!a.isPrime && (
                <button
                  className="icon-btn"
                  title="Make default"
                  disabled={busy}
                  onClick={() => act(api.post(`/api/characters/${characterId}/avatars/${a.id}/prime`))}
                >
                  ★
                </button>
              )}
              <button
                className="icon-btn"
                title="Delete"
                disabled={busy}
                onClick={() => act(api.post(`/api/characters/${characterId}/avatars/${a.id}/delete`))}
              >
                🗑
              </button>
            </div>
          </div>
        ))}
      </div>
      <div className="tool-row">
        <input ref={labelRef} placeholder="Emotion label (optional, e.g. happy)" />
        <button className="ghost" disabled={busy} onClick={() => fileRef.current?.click()}>
          {busy ? 'Working…' : '⬆ Upload'}
        </button>
        <input
          ref={fileRef}
          type="file"
          accept="image/png,image/jpeg,image/webp"
          hidden
          onChange={(e) => {
            const f = e.target.files?.[0] ?? null;
            if (f) setPending(f);
            e.target.value = '';
          }}
        />
      </div>
      {error && <p className="error">{error}</p>}
      {pending && (
        <ImageCropModal
          file={pending}
          onCancel={() => setPending(null)}
          onCropped={(blob) => void upload(blob)}
        />
      )}
    </div>
  );
}
