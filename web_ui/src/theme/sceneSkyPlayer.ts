// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Draws and drives the story-clock sky on two canvases behind the chat
// (docs/design/ambient-stage.md): the sky under the moving weather (the
// minute-blended gradient, the horizon band, the stars) and the discs over
// it (the sun and the moon, dimmed and spread wider the thicker the
// weather, so a disc always reads through). The desktop's SceneSkyLayer and
// SceneDiscLayer (lib/ui/chat_components/ambient/scene_sky_layer.dart) are
// the reference. Every colour is a channel triple from the wire.
//
// The loop runs only while something moves: a sweep after a clock jump, or
// the twinkle while stars are out, at Tint and effects; at Tint only the
// sky paints once per scene. It runs at most 30 frames a second, stops
// while the tab is hidden, holds still under prefers-reduced-motion, and
// stops while a reply is generating when Pause effects while generating
// is on.

import {
  HORIZON_ALPHA, MOONRISE, MOONSET, MOON_LIGHT_SCALE, SKY_FADE, SKY_TOP_ALPHA, STAR_COUNT, STAR_LIGHT_SCALE,
  STAR_SEED, SUNRISE, SUNSET, SUN_LIGHT_SCALE, SceneSkyMotion, horizonGlowAt, scatterStars, skyArcAt, skyWashAt,
  starTwinkle, starVisibilityAt, type Rgb, type SceneSkyWire, type SkyStar,
} from './sceneSky';

const STEP_MS = 1000 / 30;
const SLACK_MS = 2;

export type SkyLayer = 'under' | 'over';

const tint = (c: Rgb, a: number): string =>
  // theme-keep: the wire's own channels at an alpha, never a colour of this file's
  `rgba(${Math.round(c[0])}, ${Math.round(c[1])}, ${Math.round(c[2])}, ${Math.max(0, Math.min(1, a)).toFixed(4)})`;

/** A disc fades in over the first third of its climb from the horizon. */
const horizonFade = (alt: number): number => Math.max(0, Math.min(1, alt * 3));

/** The sky under the weather: gradient, horizon band, stars. */
export function paintSkyUnder(
  ctx: CanvasRenderingContext2D, w: number, h: number, wire: SceneSkyWire, minute: number, time: number, stars: SkyStar[], still: boolean,
): void {
  const { paints } = wire;
  const veil = 1 - wire.disc;
  ctx.clearRect(0, 0, w, h);
  const wash = skyWashAt(minute, paints.stops);
  const g = ctx.createLinearGradient(0, 0, 0, h * SKY_FADE);
  g.addColorStop(0, tint(wash.colour, wash.alpha * SKY_TOP_ALPHA * paints.scale));
  g.addColorStop(1, tint(wash.colour, 0));
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, w, h);
  const glow = horizonGlowAt(minute);
  if (glow.strength > 0) {
    const colour = glow.dawn ? paints.dawn : paints.dusk;
    const alpha = glow.strength * HORIZON_ALPHA * paints.scale * (1 - 0.6 * veil);
    const hg = ctx.createLinearGradient(0, h * 0.2, 0, h * 0.6);
    hg.addColorStop(0, tint(colour, 0));
    hg.addColorStop(0.6, tint(colour, alpha));
    hg.addColorStop(1, tint(colour, 0));
    ctx.fillStyle = hg;
    ctx.fillRect(0, 0, w, h);
  }
  const visible = starVisibilityAt(minute) * wire.stars;
  if (visible <= 0) return;
  const scale = wire.dark ? 1 : STAR_LIGHT_SCALE;
  for (const s of stars) {
    const twinkle = still ? 1 : starTwinkle(s, time);
    ctx.fillStyle = tint(paints.star, s.alpha * visible * twinkle * scale);
    ctx.beginPath();
    ctx.arc(s.x * w, s.y * h, s.size, 0, Math.PI * 2);
    ctx.fill();
  }
}

/** The sun and the moon over the weather. */
export function paintSkyOver(ctx: CanvasRenderingContext2D, w: number, h: number, wire: SceneSkyWire, minute: number): void {
  const { paints } = wire;
  const veil = 1 - wire.disc;
  const unit = Math.min(w, h);
  ctx.clearRect(0, 0, w, h);
  const sun = skyArcAt(minute, SUNRISE, SUNSET);
  if (sun) {
    const x = sun.x * w;
    const y = sun.y * h;
    const r = Math.max(10, unit * 0.028);
    const a = horizonFade(sun.alt) * (wire.dark ? 1 : SUN_LIGHT_SCALE);
    const warm = sun.alt < 0.35 ? paints.sunLow : paints.sunHigh;
    const glow = ctx.createRadialGradient(x, y, 0, x, y, r * (6 + 6 * veil));
    glow.addColorStop(0, tint(warm, (0.45 + 0.25 * veil) * a));
    glow.addColorStop(0.35, tint(warm, (0.12 + 0.1 * veil) * a));
    glow.addColorStop(1, tint(warm, 0));
    ctx.fillStyle = glow;
    ctx.fillRect(0, 0, w, h);
    ctx.fillStyle = tint(warm, (0.95 - 0.45 * veil) * a);
    ctx.beginPath();
    ctx.arc(x, y, r * (1 + 0.3 * veil), 0, Math.PI * 2);
    ctx.fill();
  }
  const moon = skyArcAt(minute, MOONRISE, MOONSET);
  if (moon) {
    const x = moon.x * w;
    const y = moon.y * h;
    const r = Math.max(8, unit * 0.022);
    const a = horizonFade(moon.alt) * (wire.dark ? 1 : MOON_LIGHT_SCALE);
    const glow = ctx.createRadialGradient(x, y, 0, x, y, r * (5 + 6 * veil));
    glow.addColorStop(0, tint(paints.moonGlow, (0.25 + 0.3 * veil) * a));
    glow.addColorStop(1, tint(paints.moonGlow, 0));
    ctx.fillStyle = glow;
    ctx.fillRect(0, 0, w, h);
    // The lit face: the disc less a second disc slid across it, centred on
    // the moon at new and two radii off at full; waxing lights the right
    // edge. Even-odd of the two circles, clipped to the disc.
    const lit = 1 - Math.abs(wire.moonPhase - 0.5) * 2;
    const off = (wire.moonPhase < 0.5 ? -1 : 1) * lit * r * 2.05;
    ctx.save();
    ctx.beginPath();
    ctx.arc(x, y, r, 0, Math.PI * 2);
    ctx.clip();
    ctx.fillStyle = tint(paints.moon, (0.95 - 0.4 * veil) * a);
    ctx.beginPath();
    ctx.arc(x, y, r, 0, Math.PI * 2);
    ctx.moveTo(x + off + r, y);
    ctx.arc(x + off, y, r, 0, Math.PI * 2);
    ctx.fill('evenodd');
    ctx.restore();
  }
}

export class SceneSkyPlayer {
  private wire: SceneSkyWire;
  private readonly motion: SceneSkyMotion;
  private readonly stars = scatterStars(STAR_SEED, STAR_COUNT);
  private readonly canvases = new Map<SkyLayer, HTMLCanvasElement>();
  private readonly observers = new Map<SkyLayer, ResizeObserver>();
  private generating = false;
  private raf = 0;
  private last = 0;
  private acc = 0;
  private sincePaint = 0;
  private w = 0;
  private h = 0;
  private readonly reduce: MediaQueryList | null;
  private readonly onChange = () => this.sync();

  constructor(wire: SceneSkyWire) {
    this.wire = wire;
    this.motion = new SceneSkyMotion(wire.minute);
    this.reduce = typeof window.matchMedia === 'function' ? window.matchMedia('(prefers-reduced-motion: reduce)') : null;
    this.reduce?.addEventListener?.('change', this.onChange);
    document.addEventListener('visibilitychange', this.onChange);
  }

  /** Whether the sky may move at all: Tint and effects, and no reduce motion. */
  private get animated(): boolean {
    return this.wire.level === 'effects' && !this.reduce?.matches;
  }

  /** Whether the loop should tick now. */
  get running(): boolean {
    if (!this.animated || document.hidden) return false;
    if (this.wire.pauseWhileGenerating && this.generating) return false;
    return this.motion.sweeping || starVisibilityAt(this.motion.shown) * this.wire.stars > 0;
  }

  /** Hands a layer its canvas, or null when the canvas goes away. */
  attach(layer: SkyLayer, canvas: HTMLCanvasElement | null): void {
    this.observers.get(layer)?.disconnect();
    this.observers.delete(layer);
    if (!canvas) {
      this.canvases.delete(layer);
      return;
    }
    this.canvases.set(layer, canvas);
    if (typeof ResizeObserver === 'function') {
      const observer = new ResizeObserver(() => this.resize());
      observer.observe(canvas);
      this.observers.set(layer, observer);
    }
    this.resize(true);
  }

  /** A new scene: a new minute sweeps or snaps, new colours repaint. */
  setScene(wire: SceneSkyWire): void {
    this.wire = wire;
    this.motion.retarget(wire.minute, this.animated);
    this.paint();
    this.sync();
  }

  setGenerating(generating: boolean): void {
    this.generating = generating;
    this.sync();
  }

  /** Sizes every canvas to its box and repaints; the two share one size. */
  resize(force = false): void {
    const first = this.canvases.values().next().value;
    if (!first) return;
    const rect = first.getBoundingClientRect();
    const w = Math.max(1, Math.round(rect.width));
    const h = Math.max(1, Math.round(rect.height));
    if (!force && w === this.w && h === this.h) return;
    this.w = w;
    this.h = h;
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    for (const canvas of this.canvases.values()) {
      canvas.width = Math.round(w * dpr);
      canvas.height = Math.round(h * dpr);
      canvas.getContext('2d')?.setTransform(dpr, 0, 0, dpr, 0, 0);
    }
    this.paint();
    this.sync();
  }

  dispose(): void {
    if (this.raf) cancelAnimationFrame(this.raf);
    this.raf = 0;
    for (const o of this.observers.values()) o.disconnect();
    this.observers.clear();
    this.canvases.clear();
    this.reduce?.removeEventListener?.('change', this.onChange);
    document.removeEventListener('visibilitychange', this.onChange);
  }

  private paint(): void {
    if (this.w === 0) return;
    const minute = this.motion.shown;
    const under = this.canvases.get('under')?.getContext('2d');
    if (under) paintSkyUnder(under, this.w, this.h, this.wire, minute, this.motion.time, this.stars, !this.animated);
    const over = this.canvases.get('over')?.getContext('2d');
    if (over) paintSkyOver(over, this.w, this.h, this.wire, minute);
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
    this.acc = Math.min(SLACK_MS, this.acc - STEP_MS);
    const dt = Math.min(0.1, this.sincePaint / 1000);
    this.sincePaint = 0;
    this.motion.advance(dt);
    this.paint();
  };
}
