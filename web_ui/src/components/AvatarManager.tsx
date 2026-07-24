// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The character's Avatar Gallery for the edit page — the web mirror of the
// desktop unified gallery. Two sections:
//   • Looks       — any image (outfit / scene / seasonal), uploaded as-is (no
//                   crop), the gallery faces you can swipe between in chat.
//   • Expressions — emotion-labeled face images (face-cropped on upload), used
//                   by the expression engine; "expression packs" = several of
//                   these uploaded together.
// The ★ favorite (one across BOTH sections) is the default opening face + the
// image baked into an exported / Stoop card. Upload-only: no in-app editing or
// generation on the web (that lives on desktop).

import { useEffect, useRef, useState } from 'react';
import { api } from '../api/client';
import { ImageCropModal } from './ImageCropModal';

interface AvatarItem {
  id: string;
  label: string;
  displayOrder: number;
  isPrime: boolean;
  isLook: boolean;
  isFavorite: boolean;
}

type Resp = { avatars: AvatarItem[] };

export function AvatarManager({ characterId }: { characterId: string }) {
  const [avatars, setAvatars] = useState<AvatarItem[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [pending, setPending] = useState<File | null>(null); // expression → crop
  const lookRef = useRef<HTMLInputElement>(null);
  const exprRef = useRef<HTMLInputElement>(null);
  const labelRef = useRef<HTMLInputElement>(null);

  const base = `/api/characters/${characterId}`;

  const load = () =>
    api
      .get<Resp>(`${base}/avatars`)
      .then((r) => setAvatars(r.avatars))
      .catch(() => {});

  useEffect(() => {
    void load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [characterId]);

  const run = (p: Promise<Resp>) => {
    setBusy(true);
    setError('');
    p.then((r) => setAvatars(r.avatars))
      .catch(() => setError('Action failed.'))
      .finally(() => setBusy(false));
  };

  // Looks: any image, uploaded as-is (a full outfit/scene shouldn't be square-cropped).
  const uploadLook = (file: File) =>
    run(api.upload<Resp>(`${base}/looks`, file));

  // Expressions: face-cropped (ImageCropModal) then uploaded with the emotion label.
  const uploadExpression = async (blob: Blob) => {
    setPending(null);
    const label = (labelRef.current?.value ?? '').trim();
    const q = label ? `?label=${encodeURIComponent(label)}` : '';
    const file = new File([blob], 'avatar.png', { type: blob.type || 'image/png' });
    run(
      api.upload<Resp>(`${base}/avatars${q}`, file).then((r) => {
        if (labelRef.current) labelRef.current.value = '';
        return r;
      }),
    );
  };

  const toggleFavorite = (a: AvatarItem) =>
    run(api.post(`${base}/favorite?avatarId=${a.isFavorite ? '' : a.id}`));

  // Desktop parity: delete the portrait — the ★ (else first) look is
  // promoted in its place. Only offered when a look exists to take over.
  const deletePortrait = () => {
    if (
      !window.confirm(
        'Delete the portrait? A gallery look becomes the new portrait — ' +
          'the ★ one when a look is starred, otherwise the first.',
      )
    )
      return;
    run(api.post(`${base}/portrait/delete`));
  };

  const looks = avatars.filter((a) => a.isLook);
  const expressions = avatars.filter((a) => !a.isLook);

  const tile = (a: AvatarItem, withPrime: boolean) => (
    <div
      key={a.id}
      className={`avatar-tile${a.isPrime ? ' prime' : ''}${a.isFavorite ? ' favorite' : ''}`}
    >
      <img src={`${base}/avatars/${a.id}/image?w=256`} alt={a.label || 'avatar'} />
      {a.label && <span className="avatar-label">{a.label}</span>}
      {a.isFavorite && <span className="avatar-badge">★ Default</span>}
      <div className="avatar-actions">
        <button
          className="icon-btn"
          title={a.isFavorite ? 'Unset default face' : 'Use as default face (★)'}
          disabled={busy}
          onClick={() => toggleFavorite(a)}
        >
          {a.isFavorite ? '★' : '☆'}
        </button>
        {withPrime && !a.isPrime && (
          <button
            className="icon-btn"
            title="Set as the expression engine's default"
            disabled={busy}
            onClick={() => run(api.post(`${base}/avatars/${a.id}/prime`))}
          >
            📌
          </button>
        )}
        <button
          className="icon-btn"
          title="Delete"
          disabled={busy}
          onClick={() => run(api.post(`${base}/avatars/${a.id}/delete`))}
        >
          🗑
        </button>
      </div>
    </div>
  );

  return (
    <div className="avatar-manager">
      {/* ── Looks ─────────────────────────────────────────────── */}
      <div className="gallery-section-head">
        <span className="section-label">Looks</span>
        <div className="tool-row">
          {looks.length > 0 && (
            <button className="ghost" disabled={busy} onClick={deletePortrait}>
              🗑 Delete portrait
            </button>
          )}
          <button className="ghost" disabled={busy} onClick={() => lookRef.current?.click()}>
            {busy ? 'Working…' : '⬆ Upload look'}
          </button>
        </div>
      </div>
      {looks.length === 0 ? (
        <p className="muted gallery-empty">
          Upload alternate looks (outfits, scenes) — you can swipe between them in chat.
        </p>
      ) : (
        <div className="avatar-grid">{looks.map((a) => tile(a, false))}</div>
      )}

      {/* ── Expressions ───────────────────────────────────────── */}
      <div className="gallery-section-head">
        <span className="section-label">Expressions</span>
        <div className="tool-row">
          <input ref={labelRef} placeholder="Emotion (e.g. happy)" />
          <button className="ghost" disabled={busy} onClick={() => exprRef.current?.click()}>
            {busy ? 'Working…' : '⬆ Upload'}
          </button>
        </div>
      </div>
      {expressions.length === 0 ? (
        <p className="muted gallery-empty">
          Upload emotion-labeled face images (a whole expression pack, one at a time).
        </p>
      ) : (
        <div className="avatar-grid">{expressions.map((a) => tile(a, true))}</div>
      )}

      {error && <p className="error">{error}</p>}

      {/* hidden inputs */}
      <input
        ref={lookRef}
        type="file"
        accept="image/png,image/jpeg,image/webp"
        hidden
        onChange={(e) => {
          const f = e.target.files?.[0];
          if (f) void uploadLook(f);
          e.target.value = '';
        }}
      />
      <input
        ref={exprRef}
        type="file"
        accept="image/png,image/jpeg,image/webp"
        hidden
        onChange={(e) => {
          const f = e.target.files?.[0] ?? null;
          if (f) setPending(f);
          e.target.value = '';
        }}
      />
      {pending && (
        <ImageCropModal
          file={pending}
          onCancel={() => setPending(null)}
          onCropped={(blob) => void uploadExpression(blob)}
        />
      )}
    </div>
  );
}
