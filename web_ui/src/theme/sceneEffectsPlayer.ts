// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Draws and drives the Ambient Stage's moving weather on a <canvas> behind
// the chat (docs/design/ambient-stage.md). The desktop's Flame components
// (lib/ui/chat_components/ambient/) are the reference: clouds as one path of
// puffs each, fog as radial blobs, rain as one batch of slanted strokes, snow
// as three batches by size, the storm flash as a full wash. Every colour is a
// string from the wire; per-shape strength is globalAlpha.
//
// Pause rules: the loop runs at most 30 frames a second, stops while the tab
// is hidden, holds still under prefers-reduced-motion (a still frame stays),
// and stops while a reply is generating when the desktop's Pause effects
// while generating is on.

import {
  SNOW_BAND_ALPHA, SNOW_BAND_RADIUS, SceneEffectsSim, puffsOf, snowBand,
  type EffectPaints, type SceneEffectsWire,
} from './sceneEffects';

const STEP_MS = 1000 / 30;

/** Paints one frame of the sim. */
export function paintSceneEffects(ctx: CanvasRenderingContext2D, sim: SceneEffectsSim, paints: EffectPaints): void {
  const { width: w, height: h } = sim;
  ctx.clearRect(0, 0, w, h);
  ctx.fillStyle = paints.cloud;
  for (const c of sim.clouds) {
    ctx.globalAlpha = c.a;
    ctx.beginPath();
    for (const p of puffsOf(c)) {
      ctx.moveTo(p.x + p.rx, p.y);
      ctx.ellipse(p.x, p.y, p.rx, p.ry, 0, 0, Math.PI * 2);
    }
    ctx.fill();
  }
  for (const f of sim.fogBlobs) {
    const g = ctx.createRadialGradient(f.x, f.y, 0, f.x, f.y, f.r);
    g.addColorStop(0, paints.fog);
    g.addColorStop(1, paints.fogClear);
    ctx.globalAlpha = f.a;
    ctx.fillStyle = g;
    ctx.fillRect(f.x - f.r, f.y - f.r, f.r * 2, f.r * 2);
  }
  if (sim.spec.kind === 'rain' && sim.drops.length) {
    const wind = sim.spec.wind;
    ctx.globalAlpha = 1;
    ctx.strokeStyle = paints.rain;
    ctx.lineWidth = 1;
    ctx.beginPath();
    for (const p of sim.drops) {
      ctx.moveTo(p.x, p.y);
      ctx.lineTo(p.x - p.len * wind, p.y - p.len);
    }
    ctx.stroke();
  } else if (sim.spec.kind === 'snow' && sim.drops.length) {
    ctx.fillStyle = paints.snow;
    for (let b = 0; b < 3; b++) {
      ctx.globalAlpha = SNOW_BAND_ALPHA[b];
      ctx.beginPath();
      for (const p of sim.drops) {
        if (snowBand(p) !== b) continue;
        ctx.moveTo(p.x + SNOW_BAND_RADIUS[b], p.y);
        ctx.arc(p.x, p.y, SNOW_BAND_RADIUS[b], 0, Math.PI * 2);
      }
      ctx.fill();
    }
  }
  if (sim.flash > 0) {
    ctx.globalAlpha = sim.flash;
    ctx.fillStyle = paints.flash;
    ctx.fillRect(0, 0, w, h);
  }
  ctx.globalAlpha = 1;
}

/** Owns the sim, the canvas size and the frame loop for one scene. */
export class SceneEffectsPlayer {
  private sim: SceneEffectsSim | null = null;
  private raf = 0;
  private last = 0;
  private acc = 0;
  private generating = false;
  private readonly reduce: MediaQueryList | null;
  private readonly onChange = () => this.sync();

  constructor(
    private readonly canvas: HTMLCanvasElement,
    private readonly wire: SceneEffectsWire,
  ) {
    this.reduce = typeof window.matchMedia === 'function' ? window.matchMedia('(prefers-reduced-motion: reduce)') : null;
    this.reduce?.addEventListener?.('change', this.onChange);
    document.addEventListener('visibilitychange', this.onChange);
    this.resize();
  }

  /** Whether the weather should move now. */
  get running(): boolean {
    if (document.hidden || this.reduce?.matches) return false;
    return !(this.wire.pauseWhileGenerating && this.generating);
  }

  setGenerating(generating: boolean): void {
    this.generating = generating;
    this.sync();
  }

  /** Scatters again for the canvas's current size (a resize or a new scene). */
  resize(): void {
    const rect = this.canvas.getBoundingClientRect();
    const w = Math.max(1, Math.round(rect.width));
    const h = Math.max(1, Math.round(rect.height));
    if (this.sim && this.sim.width === w && this.sim.height === h) return;
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    this.canvas.width = Math.round(w * dpr);
    this.canvas.height = Math.round(h * dpr);
    this.canvas.getContext('2d')?.setTransform(dpr, 0, 0, dpr, 0, 0);
    this.sim = new SceneEffectsSim(this.wire.effects, this.wire.seed, w, h);
    this.paint();
    this.sync();
  }

  dispose(): void {
    if (this.raf) cancelAnimationFrame(this.raf);
    this.raf = 0;
    this.reduce?.removeEventListener?.('change', this.onChange);
    document.removeEventListener('visibilitychange', this.onChange);
  }

  private paint(): void {
    const ctx = this.canvas.getContext('2d');
    if (ctx && this.sim) paintSceneEffects(ctx, this.sim, this.wire.effects.paints);
  }

  private sync(): void {
    if (this.running) {
      if (!this.raf) {
        this.last = 0;
        this.acc = 0;
        this.raf = requestAnimationFrame(this.frame);
      }
    } else if (this.raf) {
      cancelAnimationFrame(this.raf);
      this.raf = 0;
    }
  }

  private readonly frame = (now: number) => {
    this.raf = 0;
    if (!this.running) return;
    this.raf = requestAnimationFrame(this.frame);
    this.acc += Math.min(100, now - (this.last || now));
    this.last = now;
    if (this.acc < STEP_MS) return;
    const dt = Math.min(0.1, this.acc / 1000);
    this.acc = 0;
    this.sim?.advance(dt);
    this.paint();
  };
}
