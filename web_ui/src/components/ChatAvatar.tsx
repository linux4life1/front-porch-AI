// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Self-hiding chat avatar images, extracted verbatim from ChatPage. Both try a
// `primary` source, fall back to `fallback`, and render NOTHING (no broken-image
// glyph) if every source fails — important because Safari renders a broken-image
// box for an empty/odd src WITHOUT firing onError.

import { useEffect, useState } from 'react';

/** A bare <img> for the small chat-header avatar. */
export function SmartImg({ primary, fallback, className }: { primary: string; fallback?: string; className: string }) {
  const [src, setSrc] = useState(primary);
  const [failed, setFailed] = useState(false);
  useEffect(() => {
    setSrc(primary);
    setFailed(false);
  }, [primary]);
  if (failed || !src) return null;
  return (
    <img
      className={className}
      src={src}
      alt=""
      onError={() => {
        if (fallback && src !== fallback) setSrc(fallback);
        else setFailed(true);
      }}
    />
  );
}

/** Larger character portrait for the insight panel — prefers the mood-driven
 *  expression avatar (cache-busted by mood) and falls back to the static card
 *  avatar; if every source fails it renders NOTHING. The mood also appears in the
 *  Mood stat row, so hiding here loses no information. */
export function Portrait({ primary, fallback, mood }: { primary: string; fallback?: string; mood?: string }) {
  const [src, setSrc] = useState(primary);
  const [failed, setFailed] = useState(false);
  useEffect(() => {
    setSrc(primary);
    setFailed(false);
  }, [primary]);
  if (failed || !src) return null;
  return (
    <div className="portrait-wrap">
      <img
        className="portrait"
        src={src}
        alt=""
        onError={() => {
          if (fallback && src !== fallback) setSrc(fallback);
          else setFailed(true);
        }}
      />
      {mood && <span className="portrait-mood">{mood}</span>}
    </div>
  );
}
