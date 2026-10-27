// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Draws and drives the Ambient Stage's moving weather on a <canvas> behind
// the chat (docs/design/ambient-stage.md). The desktop's Flame components
// (lib/ui/chat_components/ambient/) are the reference: clouds as one path of
// puffs each, fog as low breathing banks, rain as one batch of slanted strokes, snow
// as three batches by size, the storm flash as a full wash. Every colour is a
// string from the wire; per-shape strength is globalAlpha.
//
// Pause rules: the loop runs at most 30 frames a second, stops while the tab
// is hidden, holds still under prefers-reduced-motion (a still frame stays),
// and stops while a reply is generating when the desktop's Pause effects
// while generating is on.

import {
  SNOW_BAND_ALPHA, SNOW_BAND_RADIUS, SceneEffectsSim, snowBand,
  type EffectPaints, type Flash, type SceneEffectsWire,
} from './sceneEffects';
import {
  BOLT_CORE_ALPHA, BOLT_CORE_WIDTH, BOLT_GLOW_ALPHA, BOLT_GLOW_WIDTH,
  CLOUD_BODY_ALPHA, CLOUD_TOP_ALPHA, CLOUD_TOP_LIFT, CLOUD_TOP_SCALE,
  FAR_SHEET_ALPHA, FAR_SHEET_DX, FAR_SHEET_DY, FAR_SHEET_LENGTH, FAR_SHEET_WIDTH,
  FOG_BANK_CORE, FOG_BANK_SQUASH, GROUND_FOG_HEIGHT, GROUND_FOG_STRIPES, HEAVY_RAIN_DENSITY, MID_SHEET_ALPHA, MID_SHEET_DX, MID_SHEET_DY, MID_SHEET_LENGTH,
  RAIN_BAND_ALPHA, RAIN_BAND_LENGTH, RAIN_BAND_WIDTH, SPLASH_RING_ALPHA, STREAK_SPRITE_HEIGHT, STREAK_SPRITE_WIDTH,
  SNOW_FAR_ALPHA, SNOW_HALO_ALPHA, SNOW_HALO_WIDTH, SceneSplashes,
  cloudBob, flashShape, fogBankBreath, fogBob, groundFogBreath, groundFogStripeAlpha, rainBand, rainGust, rainLean, rainLit, sceneBolt,
  type Bolt,
} from './sceneEffectsRender';

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
    g.addColorStop(FOG_BANK_CORE, paints.fog);
    g.addColorStop(1, paints.fogClear);
    return g;
  });
  fogGradients.set(sim, { fog: paints.fog, clear: paints.fogClear, grads });
  return grads;
}

/**
 * Paints one frame of the sim in the desktop's order (clouds, fog, rain or
 * snow, the flash) by the recipe in sceneEffectsRender.ts: shaded clouds
 * that bob, fog banks breathing over a breathing ground band, rain as a far
 * sheet behind three depth bands with splashes at the ground, snow as a far
 * sheet behind three bands with a halo on the nearest, and a storm flash
 * that strikes twice with a seeded bolt.
 */
export function paintSceneEffects(ctx: CanvasRenderingContext2D, sim: SceneEffectsSim, paints: EffectPaints): void {
  const { width: w, height: h } = sim;
  ctx.clearRect(0, 0, w, h);
  ctx.fillStyle = paints.cloud;
  for (const c of sim.clouds) {
    const bob = cloudBob(c.seed, sim.time) * h;
    ctx.globalAlpha = c.a * CLOUD_BODY_ALPHA;
    ctx.beginPath();
    for (const p of c.shapes) {
      const x = c.x + p.dx;
      ctx.moveTo(x + p.rx, p.y + bob);
      ctx.ellipse(x, p.y + bob, p.rx, p.ry, 0, 0, Math.PI * 2);
    }
    ctx.fill();
    ctx.globalAlpha = c.a * CLOUD_TOP_ALPHA;
    ctx.beginPath();
    for (const p of c.shapes) {
      const x = c.x + p.dx;
      const y = p.y + bob - p.ry * CLOUD_TOP_LIFT;
      ctx.moveTo(x + p.rx * CLOUD_TOP_SCALE, y);
      ctx.ellipse(x, y, p.rx * CLOUD_TOP_SCALE, p.ry * CLOUD_TOP_SCALE, 0, 0, Math.PI * 2);
    }
    ctx.fill();
  }
  if (sim.fogBlobs.length) {
    const grads = fogGradientsFor(ctx, sim, paints);
    sim.fogBlobs.forEach((f, i) => {
      ctx.globalAlpha = f.a * fogBankBreath(i, sim.time);
      ctx.fillStyle = grads[i];
      ctx.save();
      ctx.translate(f.x, f.y + fogBob(i, sim.time) * h);
      ctx.scale(1, FOG_BANK_SQUASH);
      ctx.fillRect(-f.r, -f.r, f.r * 2, f.r * 2);
      ctx.restore();
    });
    const breath = groundFogBreath(sim.time);
    const band = h * GROUND_FOG_HEIGHT;
    const stripe = band / GROUND_FOG_STRIPES;
    ctx.fillStyle = paints.fog;
    for (let i = 0; i < GROUND_FOG_STRIPES; i++) {
      ctx.globalAlpha = groundFogStripeAlpha(i) * breath;
      ctx.fillRect(0, h - band + i * stripe, w, stripe + 0.5);
    }
  }
  if (sim.spec.kind === 'rain' && sim.drops.length) {
    paintRain(ctx, sim, paints.rain);
  } else if (sim.spec.kind === 'snow' && sim.drops.length) {
    paintSnow(ctx, sim, paints.snow);
  }
  if (sim.flash > 0) {
    const strength = flashShape(sim.flash);
    ctx.globalAlpha = strength;
    ctx.fillStyle = paints.flash;
    ctx.fillRect(0, 0, w, h);
    const bolt = boltFor(sim);
    ctx.strokeStyle = paints.flash;
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    ctx.beginPath();
    trace(ctx, bolt.trunk);
    trace(ctx, bolt.branch);
    ctx.globalAlpha = BOLT_GLOW_ALPHA * strength;
    ctx.lineWidth = BOLT_GLOW_WIDTH;
    ctx.stroke();
    ctx.globalAlpha = BOLT_CORE_ALPHA * strength;
    ctx.lineWidth = BOLT_CORE_WIDTH;
    ctx.stroke();
  }
  ctx.globalAlpha = 1;
}

const streakSprites = new WeakMap<SceneEffectsSim, { colour: string; sprites: HTMLCanvasElement[] | null }>();

/**
 * One streak sprite per band, tinted with the rain colour: a soft tail
 * fading to a full head, drawn at len / height scale with the head at the
 * drop. Built once per scatter and colour. Null where the page has no 2D
 * context to build them on, and the rain falls back to plain lines.
 */
function streakSpritesFor(sim: SceneEffectsSim, colour: string): HTMLCanvasElement[] | null {
  const cached = streakSprites.get(sim);
  if (cached && cached.colour === colour) return cached.sprites;
  let sprites: HTMLCanvasElement[] | null = [];
  for (const w of STREAK_SPRITE_WIDTH) {
    const c = document.createElement('canvas');
    const scale = 2;
    c.width = w * scale;
    c.height = STREAK_SPRITE_HEIGHT * scale;
    const g = c.getContext('2d');
    if (!g) { sprites = null; break; }
    const grad = g.createLinearGradient(0, 0, 0, c.height);
    // theme-keep: an alpha mask cut into the tinted streak, never a colour on screen
    grad.addColorStop(0, 'rgba(0,0,0,0)');
    // theme-keep: alpha mask
    grad.addColorStop(0.55, 'rgba(0,0,0,0.4)');
    // theme-keep: alpha mask
    grad.addColorStop(1, 'rgba(0,0,0,1)');
    g.fillStyle = colour;
    g.beginPath();
    g.roundRect(0, 0, c.width, c.height, c.width / 2);
    g.fill();
    g.globalCompositeOperation = 'destination-in';
    g.fillStyle = grad;
    g.fillRect(0, 0, c.width, c.height);
    sprites.push(c);
  }
  streakSprites.set(sim, { colour, sprites });
  return sprites;
}

const splashes = new WeakMap<SceneEffectsSim, SceneSplashes>();

/** Every drop as a streak sprite (its far sheet, a mid sheet in heavy rain, then itself), then the splashes. */
function paintRain(ctx: CanvasRenderingContext2D, sim: SceneEffectsSim, colour: string): void {
  const { width: w, height: h } = sim;
  const gust = rainGust(sim.time);
  const lean = rainLean(sim.spec.wind, gust);
  const stretch = 0.85 + 0.15 * gust;
  const lit = rainLit(sim.flash);
  const heavy = sim.spec.density >= HEAVY_RAIN_DENSITY;
  const sprites = streakSpritesFor(sim, colour);
  const wind = sim.spec.wind;
  const alpha = (share: number) => Math.min(1, share * lit);
  if (sprites) {
    const cos = Math.cos(lean);
    const sin = Math.sin(lean);
    const draw = (x: number, y: number, len: number, band: number, share: number) => {
      const sp = sprites[band];
      const k = len / STREAK_SPRITE_HEIGHT;
      const sw = STREAK_SPRITE_WIDTH[band];
      // Rotate about the head, scale by the length, then place the head at the drop.
      ctx.setTransform(cos * k, sin * k, -sin * k, cos * k, x, y);
      ctx.globalAlpha = alpha(share);
      ctx.drawImage(sp, -sw / 2, -STREAK_SPRITE_HEIGHT, sw, STREAK_SPRITE_HEIGHT);
    };
    const base = ctx.getTransform();
    for (const p of sim.drops) {
      draw((p.x + w * FAR_SHEET_DX) % w, (p.y + h * FAR_SHEET_DY) % h, p.len * FAR_SHEET_LENGTH * stretch, 0, FAR_SHEET_ALPHA);
      if (heavy) draw((p.x + w * MID_SHEET_DX) % w, (p.y + h * MID_SHEET_DY) % h, p.len * MID_SHEET_LENGTH * stretch, 1, MID_SHEET_ALPHA);
      const b = rainBand(p);
      draw(p.x, p.y, p.len * RAIN_BAND_LENGTH[b] * stretch, b, RAIN_BAND_ALPHA[b]);
    }
    ctx.setTransform(base);
  } else {
    ctx.strokeStyle = colour;
    ctx.lineCap = 'butt';
    const slant = Math.tan(-lean);
    const line = (x: number, y: number, len: number) => { ctx.moveTo(x, y); ctx.lineTo(x - len * slant, y - len); };
    ctx.globalAlpha = alpha(FAR_SHEET_ALPHA);
    ctx.lineWidth = FAR_SHEET_WIDTH;
    ctx.beginPath();
    for (const p of sim.drops) line((p.x + w * FAR_SHEET_DX) % w, (p.y + h * FAR_SHEET_DY) % h, p.len * FAR_SHEET_LENGTH * stretch);
    ctx.stroke();
    if (heavy) {
      ctx.globalAlpha = alpha(MID_SHEET_ALPHA);
      ctx.lineWidth = RAIN_BAND_WIDTH[1];
      ctx.beginPath();
      for (const p of sim.drops) line((p.x + w * MID_SHEET_DX) % w, (p.y + h * MID_SHEET_DY) % h, p.len * MID_SHEET_LENGTH * stretch);
      ctx.stroke();
    }
    for (let b = 0; b < 3; b++) {
      ctx.globalAlpha = alpha(RAIN_BAND_ALPHA[b]);
      ctx.lineWidth = RAIN_BAND_WIDTH[b];
      ctx.beginPath();
      for (const p of sim.drops) {
        if (rainBand(p) === b) line(p.x, p.y, p.len * RAIN_BAND_LENGTH[b] * stretch);
      }
      ctx.stroke();
    }
    void wind;
  }
  let tracker = splashes.get(sim);
  if (!tracker) { tracker = new SceneSplashes(); splashes.set(sim, tracker); }
  tracker.observe(sim.drops, sim.time, h);
  if (!tracker.live.length) return;
  ctx.strokeStyle = colour;
  ctx.fillStyle = colour;
  ctx.lineWidth = 1;
  for (const s of tracker.live) {
    const p = SceneSplashes.progress(s, sim.time);
    const r = SceneSplashes.ringRadius(p);
    ctx.globalAlpha = alpha(SPLASH_RING_ALPHA * (1 - p));
    ctx.beginPath();
    ctx.ellipse(s.x, h - 1, r, r * 0.35, 0, 0, Math.PI * 2);
    ctx.stroke();
    const lift = SceneSplashes.dropletLift(p);
    if (lift <= 0) continue;
    ctx.beginPath();
    ctx.arc(s.x - 3 - 6 * p, h - 1 - lift, 0.8, 0, Math.PI * 2);
    ctx.arc(s.x + 3 + 6 * p, h - 1 - lift * 0.8, 0.8, 0, Math.PI * 2);
    ctx.fill();
  }
}

/** The far sheet of pinpoints, the nearest band's halo, then the three bands. */
function paintSnow(ctx: CanvasRenderingContext2D, sim: SceneEffectsSim, colour: string): void {
  const { width: w, height: h } = sim;
  ctx.fillStyle = colour;
  ctx.globalAlpha = SNOW_FAR_ALPHA;
  ctx.beginPath();
  for (const p of sim.drops) {
    const fx = (p.x + w * FAR_SHEET_DX) % w;
    const fy = (p.y + h * FAR_SHEET_DY) % h;
    ctx.moveTo(fx + 0.5, fy);
    ctx.arc(fx, fy, 0.5, 0, Math.PI * 2);
  }
  ctx.fill();
  const halo = SNOW_BAND_RADIUS[2] * SNOW_HALO_WIDTH;
  ctx.globalAlpha = SNOW_HALO_ALPHA;
  ctx.beginPath();
  for (const p of sim.drops) {
    if (snowBand(p) !== 2) continue;
    ctx.moveTo(p.x + halo, p.y);
    ctx.arc(p.x, p.y, halo, 0, Math.PI * 2);
  }
  ctx.fill();
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

const bolts = new WeakMap<SceneEffectsSim, { at: number; bolt: Bolt }>();

/** The bolt for the flash under way, worked out once per flash. */
function boltFor(sim: SceneEffectsSim): Bolt {
  const cached = bolts.get(sim);
  if (cached && cached.at === sim.nextFlashAt) return cached.bolt;
  const bolt = sceneBolt(sim.seed, sim.nextFlashAt, sim.width, sim.height);
  bolts.set(sim, { at: sim.nextFlashAt, bolt });
  return bolt;
}

function trace(ctx: CanvasRenderingContext2D, points: [number, number][]): void {
  ctx.moveTo(points[0][0], points[0][1]);
  for (let i = 1; i < points.length; i++) ctx.lineTo(points[i][0], points[i][1]);
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
  /** Each storm flash as the sim fires it, for the scene sound's thunder. */
  onFlash: ((f: Flash) => void) | null = null;

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
    this.sim.onFlash = (f) => this.onFlash?.(f);
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
    // (30 fps) rather than every third, but bank no more than the slack:
    // after a stall the next frame never paints again 16 ms later. (A 45,
    // 50 or 75 Hz display settles a little under 30 fps; that is fine for
    // a cap whose job is to leave the GPU to the model.)
    this.acc = Math.min(SLACK_MS, this.acc - STEP_MS);
    const dt = Math.min(0.1, this.sincePaint / 1000);
    this.sincePaint = 0;
    this.sim?.advance(dt);
    this.paint();
  };
}
