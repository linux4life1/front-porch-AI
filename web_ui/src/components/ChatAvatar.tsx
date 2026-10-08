// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Self-hiding chat avatar images, extracted verbatim from ChatPage. Both try a
// `primary` source, fall back to `fallback`, and render NOTHING (no broken-image
// glyph) if every source fails — important because Safari renders a broken-image
// box for an empty/odd src WITHOUT firing onError.

import { useCallback, useEffect, useRef, useState } from 'react';
import { api } from '../api/client';

/**
 * primary → fallback → nothing. Also checks right after each source is placed:
 * WebKit reports a URL it has already seen fail (the header and the sidebar
 * portrait ask for the same expression picture) before any error listener
 * runs, so onError never fires and the broken-picture box stays.
 */
function useFallbackSrc(primary: string, fallback?: string) {
  const [src, setSrc] = useState(primary);
  const [failed, setFailed] = useState(false);
  const ref = useRef<HTMLImageElement>(null);
  useEffect(() => {
    setSrc(primary);
    setFailed(false);
  }, [primary]);
  const onError = useCallback(() => {
    if (fallback && src !== fallback) setSrc(fallback);
    else setFailed(true);
  }, [fallback, src]);
  useEffect(() => {
    const img = ref.current;
    if (img && img.complete && img.naturalWidth === 0 && img.getAttribute('src')) onError();
  }, [src, onError]);
  return { src, gone: failed || !src, ref, onError };
}

/** A bare <img> for the small chat-header avatar. */
export function SmartImg({ primary, fallback, className }: { primary: string; fallback?: string; className: string }) {
  const { src, gone, ref, onError } = useFallbackSrc(primary, fallback);
  if (gone) return null;
  return <img ref={ref} className={className} src={src} alt="" onError={onError} />;
}

/** Larger character portrait for the insight panel — prefers the mood-driven
 *  expression avatar (cache-busted by mood) and falls back to the static card
 *  avatar; if every source fails it renders NOTHING. The mood also appears in the
 *  Mood stat row, so hiding here loses no information. */
export function Portrait({ primary, fallback, mood }: { primary: string; fallback?: string; mood?: string }) {
  const { src, gone, ref, onError } = useFallbackSrc(primary, fallback);
  if (gone) return null;
  return (
    <div className="portrait-wrap">
      <img ref={ref} className="portrait" src={src} alt="" onError={onError} />
      {mood && <span className="portrait-mood">{mood}</span>}
    </div>
  );
}

/** The sidebar [Portrait] with chevrons to swipe between a character's uploaded
 *  "looks". Face 0 is the base (the mood-driven portrait / member avatar —
 *  expressions still apply there); faces 1..N are looks, shown statically. The
 *  pick sticks per-character via localStorage. Chevrons appear only when the
 *  character actually has looks; a character with none behaves exactly as the
 *  bare [Portrait] did. Mirrors the desktop sidebar face-ring (single reference,
 *  upload-only on web). */
export function LookSwiper({
  characterId,
  basePrimary,
  baseFallback,
  mood,
}: {
  characterId: string;
  basePrimary: string;
  baseFallback?: string;
  mood?: string;
}) {
  const [looks, setLooks] = useState<{ id: string }[]>([]);
  const [idx, setIdx] = useState(0); // 0 = base; 1..N = looks[idx-1]
  const lsKey = `fpai.look.${characterId}`;

  useEffect(() => {
    if (!characterId) {
      setLooks([]);
      setIdx(0);
      return;
    }
    let alive = true;
    api
      .get<{ avatars: { id: string; isLook: boolean }[] }>(
        `/api/characters/${characterId}/avatars`,
      )
      .then((r) => {
        if (!alive) return;
        const ls = r.avatars.filter((a) => a.isLook).map((a) => ({ id: a.id }));
        setLooks(ls);
        const saved = localStorage.getItem(lsKey);
        const at = saved ? ls.findIndex((l) => l.id === saved) : -1;
        setIdx(at >= 0 ? at + 1 : 0);
      })
      .catch(() => {
        if (alive) {
          setLooks([]);
          setIdx(0);
        }
      });
    return () => {
      alive = false;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [characterId]);

  const total = 1 + looks.length;
  const onLook = idx > 0 && idx <= looks.length;
  const primary = onLook
    ? `/api/characters/${characterId}/avatars/${looks[idx - 1].id}/image?w=512`
    : basePrimary;

  const flip = (d: number) => {
    const next = (idx + d + total) % total;
    setIdx(next);
    if (next === 0) localStorage.removeItem(lsKey);
    else localStorage.setItem(lsKey, looks[next - 1].id);
  };

  return (
    <div className="portrait-swiper">
      <Portrait
        primary={primary}
        fallback={onLook ? undefined : baseFallback}
        mood={onLook ? undefined : mood}
      />
      {looks.length > 0 && (
        <>
          <button
            className="portrait-chevron left"
            onClick={() => flip(-1)}
            aria-label="Previous look"
          >
            ‹
          </button>
          <button
            className="portrait-chevron right"
            onClick={() => flip(1)}
            aria-label="Next look"
          >
            ›
          </button>
          <span className="portrait-dots">
            {idx + 1}/{total}
          </span>
        </>
      )}
    </div>
  );
}
