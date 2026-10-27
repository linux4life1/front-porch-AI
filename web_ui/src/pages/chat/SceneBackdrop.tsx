// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Setting place's picture behind the chat (desktop twin of
// SceneBackdropLayer): the chat state names the place and where to fetch
// its cover; a change of place dissolves from the old picture to the new
// one, which settles from a touch larger to its true size, so a move is
// seen and not just read in the Places section. Under reduced motion the
// swap is instant. The veil and the Ambient Stage's tint paint over the
// picture here, in place of the chat view's own backdrop layer.

import { useEffect, useRef, useState } from 'react';

/** The chat state's `sceneBackdrop`, or null when the chat has none. */
export interface SceneBackdropWire {
  placeId: string;
  placeName: string;
  url: string;
}

/** How long the dissolve runs; matches the desktop's. */
export const SCENE_BACKDROP_TRANSITION_MS = 1200;

export function parseSceneBackdrop(raw: unknown): SceneBackdropWire | null {
  if (!raw || typeof raw !== 'object') return null;
  const w = raw as Record<string, unknown>;
  if (typeof w.placeId !== 'string' || typeof w.url !== 'string' || !w.url.startsWith('/api/')) {
    return null;
  }
  return { placeId: w.placeId, placeName: typeof w.placeName === 'string' ? w.placeName : '', url: w.url };
}

function reducedMotion(): boolean {
  return typeof window !== 'undefined'
    && typeof window.matchMedia === 'function'
    && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
}

interface Props {
  backdrop: SceneBackdropWire | null;
}

/**
 * Keeps the picture it is leaving under the one arriving until the dissolve
 * is over (keyed by the URL, which carries the picture's version, so a
 * re-saved cover of the same place dissolves too). Renders nothing without
 * a backdrop, so a chat with none keeps the theme background.
 */
export function SceneBackdrop({ backdrop }: Props) {
  const [shown, setShown] = useState<SceneBackdropWire | null>(backdrop);
  const [leaving, setLeaving] = useState<SceneBackdropWire | null>(null);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    if ((backdrop?.url ?? null) === (shown?.url ?? null)) return;
    if (timer.current !== null) clearTimeout(timer.current);
    const instant = reducedMotion() || shown === null || backdrop === null;
    setLeaving(instant ? null : shown);
    setShown(backdrop);
    if (!instant) {
      timer.current = setTimeout(() => {
        setLeaving(null);
        timer.current = null;
      }, SCENE_BACKDROP_TRANSITION_MS);
    }
  }, [backdrop, shown]);

  useEffect(() => () => {
    if (timer.current !== null) clearTimeout(timer.current);
  }, []);

  if (!shown) return null;
  return (
    <div className="scene-backdrop" aria-hidden="true" data-place={shown.placeId}>
      {leaving && (
        <img key={leaving.url} className="scene-backdrop-img is-leaving" src={leaving.url} alt="" />
      )}
      <img key={shown.url} className={`scene-backdrop-img${leaving ? ' is-arriving' : ''}`} src={shown.url} alt="" />
      <div className="scene-backdrop-veil" />
      <div className="scene-backdrop-tint" />
    </div>
  );
}
