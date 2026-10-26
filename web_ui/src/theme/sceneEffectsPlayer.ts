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
  SNOW_BAND_ALPHA, SNOW_BAND_RADIUS, SceneEffectsSim, snowBand,
  type EffectPaints, type SceneEffectsWire,
} from './sceneEffects';

export const STEP_MS = 1000 / 30;

// A frame's timestamp jitters around the display's period, so two 60 Hz
// frames can sum to a hair under STEP_MS; this slack keeps a 60 Hz display
// painting every other frame instead of every third.
const SLACK_MS = 2;

// Each fog blob's gradient, built at the origin once per scatter and
// colour and moved with a translate, so a frame makes no gradients. Keyed
// by the sim, so a new scatter drops the old ones with it.
const fogGradients = new WeakMap<SceneEffectsSim, { fog: string; clear: string; grads: CanvasGradient[] }>();

function fogGradientsFor(ctx: CanvasRenderingContext2D, sim: SceneEffectsSim, paints: EffectPaints): CanvasGradient[] {
  const cached = fogGradients.get(sim);
  if (cached && cached.fog === paints.fog && cached.clear === paints.fogClear) return cached.grads;
  const grads = sim.fogBlobs.map((f) => {
    const g = ctx.createRadialGradient(0, 0, 0, 0, 0, f.r);
    g.addColorStop(0, paints.fog);
    g.addColorStop(1, paints.fogClear);
    return g;
  });
  fogGradients.set(sim, { fog: paints.fog, clear: paints.fogClear, grads });
  return grads;
}

/** Paints one frame of the sim: clouds, fog, rain or snow, the flash, in the desktop's order. */
export function paintSceneEffects(ctx: CanvasRenderingContext2D, sim: SceneEffectsSim, paints: EffectPaints): void {
  const { width: w, height: h } = sim;
  ctx.clearRect(0, 0, w, h);
  ctx.fillStyle = paints.cloud;
  for (const c of sim.clouds) {
    ctx.globalAlpha = c.a;
    ctx.beginPath();
    for (const p of c.shapes) {
      const x = c.x + p.dx;
      ctx.moveTo(x + p.rx, p.y);
      ctx.ellipse(x, p.y, p.rx, p.ry, 0, 0, Math.PI * 2);
    }
    ctx.fill();
  }
  if (sim.fogBlobs.length) {
    const grads = fogGradientsFor(ctx, sim, paints);
    sim.fogBlobs.forEach((f, i) => {
      ctx.globalAlpha = f.a;
      ctx.fillStyle = grads[i];
      ctx.save();
      ctx.translate(f.x, f.y);
      ctx.fillRect(-f.r, -f.r, f.r * 2, f.r * 2);
      ctx.restore();
    });
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

/**
 * Owns the sim, the canvas size and the frame loop for one scatter (a seed
 * and an effects spec). The colours and the pause switch can change under
 * it without the rain jumping: setPaints and setPauseWhileGenerating.
 */
export class SceneEffectsPlayer {
  private sim: SceneEffectsSim | null = null;
  private raf = 0;
  private last = 0;
  private acc = 0;
  private sincePaint = 0;
  private generating = false;
  private paints: EffectPaints;
  private pauseWhileGenerating: boolean;
  private readonly reduce: MediaQueryList | null;
  private readonly onChange = () => this.sync();

  constructor(
    private readonly canvas: HTMLCanvasElement,
    private readonly wire: SceneEffectsWire,
  ) {
    this.paints = wire.effects.paints;
    this.pauseWhileGenerating = wire.pauseWhileGenerating;
    this.reduce = typeof window.matchMedia === 'function' ? window.matchMedia('(prefers-reduced-motion: reduce)') : null;
    this.reduce?.addEventListener?.('change', this.onChange);
    document.addEventListener('visibilitychange', this.onChange);
    this.resize();
  }

  /** Whether the weather should move now. */
  get running(): boolean {
    if (document.hidden || this.reduce?.matches) return false;
    return !(this.pauseWhileGenerating && this.generating);
  }

  setGenerating(generating: boolean): void {
    this.generating = generating;
    this.sync();
  }

  setPauseWhileGenerating(on: boolean): void {
    this.pauseWhileGenerating = on;
    this.sync();
  }

  /** New colours (a mode switch) on the same weather; a still frame repaints in them. */
  setPaints(paints: EffectPaints): void {
    if (paints === this.paints) return;
    this.paints = paints;
    if (!this.raf) this.paint();
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
    if (ctx && this.sim) paintSceneEffects(ctx, this.sim, this.paints);
  }

  private sync(): void {
    if (this.running) {
      if (!this.raf) {
        this.last = 0;
        this.acc = 0;
        this.sincePaint = 0;
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
    const elapsed = Math.min(100, now - (this.last || now));
    this.last = now;
    this.acc += elapsed;
    this.sincePaint += elapsed;
    if (this.acc < STEP_MS - SLACK_MS) return;
    // Keep the remainder, so a 60 Hz display lands on every other frame
    // (30 fps) rather than every third, but bank at most half a step: a
    // long stall paints once, not a burst of catch-up frames.
    this.acc = Math.min(STEP_MS / 2, this.acc - STEP_MS);
    const dt = Math.min(0.1, this.sincePaint / 1000);
    this.sincePaint = 0;
    this.sim?.advance(dt);
    this.paint();
  };
}
