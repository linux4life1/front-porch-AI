// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Setting place's picture behind the chat (desktop twin of
// SceneBackdropLayer and SceneBackdropGame): a canvas that paints the
// picture under the veil and plays the move from one place to the next by
// the story's weather (sceneBackdropTransition.ts), with the place's name
// on a card while it runs. The first picture shows at once; under reduced
// motion a move is a still swap and the name shows briefly. Where the page
// has no 2D canvas, two <img> layers dissolve instead. The Ambient Stage's
// tint paints over the picture here, in place of the chat view's own
// backdrop layer.

import { useEffect, useRef, useState } from 'react';
import { mulberry32 } from '../../theme/sceneEffects';
import {
  SCENE_MOVE_STILL_TITLE, sceneFogBankX, sceneFogBanks, sceneFogWash, sceneMoveDuration, sceneMoveFrame,
  sceneMoveKindFor, sceneMoveTitle, type SceneFogBank, type SceneMoveFrame, type SceneMoveKind,
} from '../../theme/sceneBackdropTransition';

/** The chat state's `sceneBackdrop`, or null when the chat has none. */
export interface SceneBackdropWire {
  placeId: string;
  placeName: string;
  url: string;
  condition?: string | null;
}

/** How long the fallback dissolve runs; matches the travel move. */
export const SCENE_BACKDROP_TRANSITION_MS = 1600;

export function parseSceneBackdrop(raw: unknown): SceneBackdropWire | null {
  if (!raw || typeof raw !== 'object') return null;
  const w = raw as Record<string, unknown>;
  if (typeof w.placeId !== 'string' || typeof w.url !== 'string' || !w.url.startsWith('/api/')) {
    return null;
  }
  return {
    placeId: w.placeId,
    placeName: typeof w.placeName === 'string' ? w.placeName : '',
    url: w.url,
    condition: typeof w.condition === 'string' ? w.condition : null,
  };
}

function reducedMotion(): boolean {
  return typeof window !== 'undefined'
    && typeof window.matchMedia === 'function'
    && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
}

/** fnv1a32 of the place id, the desktop's seed for its fog banks. */
function seedOf(s: string): number {
  let h = 0x811c9dc5;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h >>> 0;
}

const REST: SceneMoveFrame = {
  outAlpha: 0, outScale: 1, outDx: 0, inAlpha: 1, inScale: 1, inDx: 0,
  sweep: -1, sweepAlpha: 0, cover: 0, flash: 0, dip: 0, title: 0,
};

/** The colours the move paints with; the veil is the desktop's 0.45 dim. */
const VEIL = 'rgba(0, 0, 0, 0.45)'; // theme-keep: the scrim every background wears
const LIGHT = [240, 244, 255]; // theme-keep: the scene palette's flash, the sweep and the strike
const FOG = [169, 177, 187]; // theme-keep: the scene palette's fog, the roll

// theme-keep: the scene palette's own colours at a frame's alpha, never a theme hue
const withAlpha = (c: number[], a: number) => `rgba(${c[0]}, ${c[1]}, ${c[2]}, ${a})`;

/** Paints one frame of the move: pictures, veil, dip, sweep, fog, flash. */
export function paintSceneMove(
  ctx: CanvasRenderingContext2D, w: number, h: number, f: SceneMoveFrame,
  current: HTMLImageElement | null, previous: HTMLImageElement | null, banks: SceneFogBank[],
): void {
  ctx.clearRect(0, 0, w, h);
  const picture = (img: HTMLImageElement, alpha: number, scale: number, dx: number) => {
    if (!img.naturalWidth || !img.naturalHeight) return;
    const s = Math.max(w / img.naturalWidth, h / img.naturalHeight) * scale;
    const dw = img.naturalWidth * s;
    const dh = img.naturalHeight * s;
    ctx.globalAlpha = alpha;
    ctx.drawImage(img, (w - dw) / 2 + dx * w, (h - dh) / 2, dw, dh);
  };
  if (previous && f.outAlpha > 0) picture(previous, f.outAlpha, f.outScale, f.outDx);
  if (current && f.inAlpha > 0) picture(current, f.inAlpha, f.inScale, f.inDx);
  ctx.globalAlpha = 1;
  ctx.fillStyle = VEIL;
  ctx.fillRect(0, 0, w, h);
  if (f.dip > 0) {
    ctx.globalAlpha = f.dip;
    ctx.fillRect(0, 0, w, h);
  }
  if (f.sweep >= 0 && f.sweepAlpha > 0) {
    const cx = -0.3 * w + f.sweep * 1.6 * w;
    const half = 0.15 * w;
    const g = ctx.createLinearGradient(-half, 0, half, 0);
    g.addColorStop(0, withAlpha(LIGHT, 0));
    g.addColorStop(0.5, withAlpha(LIGHT, f.sweepAlpha));
    g.addColorStop(1, withAlpha(LIGHT, 0));
    ctx.save();
    ctx.globalAlpha = 1;
    ctx.globalCompositeOperation = 'lighter';
    ctx.translate(cx, h / 2);
    ctx.rotate(-0.35);
    ctx.fillStyle = g;
    ctx.fillRect(-half, -h, half * 2, h * 2);
    ctx.restore();
  }
  if (f.cover > 0) {
    ctx.globalAlpha = 1;
    ctx.fillStyle = withAlpha(FOG, sceneFogWash(f.cover));
    ctx.fillRect(0, 0, w, h);
    const span = Math.max(w, h);
    for (const bank of banks) {
      const cx = sceneFogBankX(bank, f.cover) * w;
      const cy = bank.y * h;
      const r = bank.r * span;
      const g = ctx.createRadialGradient(cx, cy, 0, cx, cy, r);
      g.addColorStop(0, withAlpha(FOG, 0.95 * f.cover));
      g.addColorStop(1, withAlpha(FOG, 0));
      ctx.fillStyle = g;
      ctx.beginPath();
      ctx.arc(cx, cy, r, 0, Math.PI * 2);
      ctx.fill();
    }
  }
  if (f.flash > 0) {
    ctx.globalAlpha = 1;
    ctx.fillStyle = withAlpha(LIGHT, 0.95 * f.flash);
    ctx.fillRect(0, 0, w, h);
  }
  ctx.globalAlpha = 1;
}

interface Props {
  backdrop: SceneBackdropWire | null;
}

interface Move { kind: SceneMoveKind; start: number; duration: number; banks: SceneFogBank[] }

export function SceneBackdrop({ backdrop }: Props) {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const ctxRef = useRef<CanvasRenderingContext2D | null | undefined>(undefined);
  const current = useRef<HTMLImageElement | null>(null);
  const previous = useRef<HTMLImageElement | null>(null);
  const move = useRef<Move | null>(null);
  const raf = useRef(0);
  const shownUrl = useRef<string | null>(null);
  const [title, setTitle] = useState<{ name: string; kind: SceneMoveKind | 'still'; key: number } | null>(null);
  // The fallback dissolve's two layers, where the page has no 2D canvas.
  const [fallback, setFallback] = useState<{ shown: SceneBackdropWire | null; leaving: SceneBackdropWire | null }>({ shown: null, leaving: null });
  const fallbackTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const context = (): CanvasRenderingContext2D | null => {
    if (ctxRef.current !== undefined) return ctxRef.current;
    const c = canvasRef.current;
    ctxRef.current = c ? c.getContext('2d') : null;
    return ctxRef.current;
  };

  const size = () => {
    const c = canvasRef.current;
    if (!c) return { w: 0, h: 0 };
    const rect = c.getBoundingClientRect();
    const w = Math.max(1, Math.round(rect.width));
    const h = Math.max(1, Math.round(rect.height));
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    if (c.width !== Math.round(w * dpr) || c.height !== Math.round(h * dpr)) {
      c.width = Math.round(w * dpr);
      c.height = Math.round(h * dpr);
      context()?.setTransform(dpr, 0, 0, dpr, 0, 0);
    }
    return { w, h };
  };

  const paint = (now: number) => {
    const ctx = context();
    if (!ctx) return;
    const { w, h } = size();
    const m = move.current;
    let f = REST;
    if (m) {
      const p = (now - m.start) / (m.duration * 1000);
      if (p >= 1) {
        move.current = null;
        previous.current = null;
        setTitle(null);
      } else {
        f = sceneMoveFrame(m.kind, p);
      }
    }
    paintSceneMove(ctx, w, h, f, current.current, previous.current, m?.banks ?? []);
  };

  const frame = (now: number) => {
    raf.current = 0;
    paint(now);
    if (move.current) raf.current = requestAnimationFrame(frame);
  };

  const show = (img: HTMLImageElement, wire: SceneBackdropWire, first: boolean) => {
    const still = reducedMotion();
    if (first || still || !current.current) {
      previous.current = null;
      current.current = img;
      move.current = null;
      paint(performance.now());
      if (!first) {
        setTitle({ name: wire.placeName, kind: 'still', key: Date.now() });
        setTimeout(() => setTitle((t) => (t && t.kind === 'still' ? null : t)), SCENE_MOVE_STILL_TITLE * 1000);
      }
      return;
    }
    const kind = sceneMoveKindFor(wire.condition);
    previous.current = current.current;
    current.current = img;
    move.current = {
      kind, start: performance.now(), duration: sceneMoveDuration(kind),
      banks: kind === 'fogRoll' ? sceneFogBanks(mulberry32(seedOf(wire.placeId))) : [],
    };
    setTitle({ name: wire.placeName, kind, key: Date.now() });
    if (!raf.current) raf.current = requestAnimationFrame(frame);
  };

  useEffect(() => {
    const url = backdrop?.url ?? null;
    if (url === shownUrl.current) return;
    const first = shownUrl.current === null;
    shownUrl.current = url;
    if (!context()) {
      // No canvas: the two-layer dissolve.
      if (fallbackTimer.current !== null) clearTimeout(fallbackTimer.current);
      setFallback((fb) => {
        const instant = reducedMotion() || fb.shown === null || backdrop === null;
        if (!instant) {
          fallbackTimer.current = setTimeout(() => {
            setFallback((cur) => ({ ...cur, leaving: null }));
            fallbackTimer.current = null;
          }, SCENE_BACKDROP_TRANSITION_MS);
        }
        return { shown: backdrop, leaving: instant ? null : fb.shown };
      });
      if (backdrop && !first) {
        setTitle({ name: backdrop.placeName, kind: reducedMotion() ? 'still' : 'travel', key: Date.now() });
        setTimeout(() => setTitle(null), SCENE_BACKDROP_TRANSITION_MS);
      }
      return;
    }
    if (!backdrop) {
      current.current = null;
      previous.current = null;
      move.current = null;
      setTitle(null);
      const ctx = context();
      if (ctx) { const { w, h } = size(); ctx.clearRect(0, 0, w, h); }
      return;
    }
    const img = new Image();
    img.decoding = 'async';
    img.onload = () => {
      if (shownUrl.current !== url) return;
      show(img, backdrop, first);
    };
    img.src = backdrop.url;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [backdrop?.url]);

  useEffect(() => {
    const onResize = () => paint(performance.now());
    window.addEventListener('resize', onResize);
    return () => {
      window.removeEventListener('resize', onResize);
      if (raf.current) cancelAnimationFrame(raf.current);
      if (fallbackTimer.current !== null) clearTimeout(fallbackTimer.current);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  if (!backdrop && !fallback.shown) return null;
  const titleStyle = title
    ? { animationDuration: `${title.kind === 'still' ? SCENE_MOVE_STILL_TITLE : sceneMoveDuration(title.kind)}s` }
    : undefined;
  return (
    <div className="scene-backdrop" aria-hidden="true" data-place={backdrop?.placeId ?? fallback.shown?.placeId}>
      <canvas ref={canvasRef} className="scene-backdrop-canvas" />
      {fallback.leaving && (
        <img key={fallback.leaving.url} className="scene-backdrop-img is-leaving" src={fallback.leaving.url} alt="" />
      )}
      {fallback.shown && (
        <img key={fallback.shown.url} className={`scene-backdrop-img${fallback.leaving ? ' is-arriving' : ''}`} src={fallback.shown.url} alt="" />
      )}
      {fallback.shown && <div className="scene-backdrop-veil" />}
      <div className="scene-backdrop-tint" />
      {title && (
        <div key={title.key} className={`scene-move-title is-${title.kind}`} style={titleStyle} aria-live="polite">
          {title.name}
        </div>
      )}
    </div>
  );
}

/** The title's opacity on the shared timeline, for the CSS keyframes' sanity test. */
export const titleAlphaAt = sceneMoveTitle;
