// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Ambient Stage's moving weather on the web (docs/design/ambient-stage.md).
// A line-for-line port of lib/services/chat/scene/scene_effects_sim.dart and
// scene_rng.dart: the same mulberry32, the same scatter order, the same
// steps, so the seed on the wire scatters the same rain the desktop draws.
// Budgets, kinds and colours all come from the wire (SceneTokens.toWire);
// this file keeps only the motion constants, and the shared fixture
// test/fixtures/ambient/scene_effects_vectors.json pins both sides to them.

/** mulberry32: 32-bit integer maths, a number in [0, 1) per call. */
export function mulberry32(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export const PARTICLE_CAP = 400;
export const FOG_BLOBS = 7;
export const FLASH_DECAY = 4.0;
export const SNOW_BAND_RADIUS = [1.57, 2.3, 3.03];
export const SNOW_BAND_ALPHA = [0.5, 0.7, 0.9];

export type EffectKind = 'none' | 'rain' | 'snow' | 'clouds' | 'fog';

export interface EffectPaints {
  rain: string;
  snow: string;
  cloud: string;
  fog: string;
  /** The fog's hue at zero alpha: each blob fades into it. */
  fogClear: string;
  flash: string;
}

export interface EffectSpec {
  kind: EffectKind;
  /** Particles per square CSS pixel of stage. */
  density: number;
  clouds: number;
  fog: boolean;
  lightning: boolean;
  wind: number;
}

export interface SceneEffectsWire {
  level: 'tint' | 'effects';
  seed: number;
  pauseWhileGenerating: boolean;
  effects: EffectSpec & { paints: EffectPaints };
}

const KINDS: EffectKind[] = ['none', 'rain', 'snow', 'clouds', 'fog'];
const CSS_COLOUR = /^(#[0-9a-f]{6}|rgba\(\d+, \d+, \d+, [0-9.]+\))$/;
const finite = (v: unknown, min: number, max: number): v is number =>
  typeof v === 'number' && Number.isFinite(v) && v >= min && v <= max;

/**
 * The moving-weather part of a scene from the desktop, or null when the
 * payload has none (an older desktop) or is not one. Never throws.
 */
export function parseSceneEffects(raw: unknown): SceneEffectsWire | null {
  if (!raw || typeof raw !== 'object') return null;
  const w = raw as Record<string, unknown>;
  if (w.level !== 'tint' && w.level !== 'effects') return null;
  if (!finite(w.seed, 0, 0xffffffff) || !Number.isInteger(w.seed)) return null;
  const e = w.effects as Record<string, unknown> | undefined;
  if (!e || typeof e !== 'object') return null;
  if (!KINDS.includes(e.kind as EffectKind)) return null;
  if (!finite(e.density, 0, 1) || !finite(e.clouds, 0, 50) || !Number.isInteger(e.clouds)) return null;
  if (!finite(e.wind, 0, 2) || typeof e.fog !== 'boolean' || typeof e.lightning !== 'boolean') return null;
  const p = e.paints as Record<string, unknown> | undefined;
  if (!p || typeof p !== 'object') return null;
  const names = ['rain', 'snow', 'cloud', 'fog', 'fogClear', 'flash'] as const;
  if (!names.every((n) => typeof p[n] === 'string' && CSS_COLOUR.test(p[n] as string))) return null;
  return {
    level: w.level,
    seed: w.seed,
    pauseWhileGenerating: w.pauseWhileGenerating !== false,
    effects: {
      kind: e.kind as EffectKind,
      density: e.density,
      clouds: e.clouds,
      fog: e.fog,
      lightning: e.lightning,
      wind: e.wind,
      paints: {
        rain: p.rain as string,
        snow: p.snow as string,
        cloud: p.cloud as string,
        fog: p.fog as string,
        fogClear: p.fogClear as string,
        flash: p.flash as string,
      },
    },
  };
}

/** Whether a parsed scene asks for any moving weather at all. */
export function hasEffects(s: SceneEffectsWire | null): s is SceneEffectsWire {
  return !!s && s.level === 'effects' && (s.effects.density > 0 || s.effects.clouds > 0 || s.effects.fog);
}

/** The particle count for a stage of width by height CSS pixels. */
export function particlesFor(density: number, width: number, height: number): number {
  return Math.min(PARTICLE_CAP, Math.round(width * height * density));
}

export interface Drop { x: number; y: number; v: number; len: number; drift: number; a: number }
export interface Cloud { x: number; y: number; w: number; h: number; v: number; a: number; puffs: number; seed: number }
export interface FogBlob { x: number; y: number; r: number; v: number; a: number }
export interface Flash { at: number; rumbleDelay: number }

/** The moving weather as plain numbers, stepped by advance(dt seconds). */
export class SceneEffectsSim {
  readonly drops: Drop[] = [];
  readonly clouds: Cloud[] = [];
  readonly fogBlobs: FogBlob[] = [];
  time = 0;
  flash = 0;
  nextFlashAt = 0;
  onFlash: ((f: Flash) => void) | null = null;
  private readonly rnd: () => number;

  constructor(
    readonly spec: EffectSpec,
    readonly seed: number,
    readonly width: number,
    readonly height: number,
  ) {
    this.rnd = mulberry32(seed);
    this.scatter();
  }

  private get snow(): boolean {
    return this.spec.kind === 'snow';
  }

  private scatter(): void {
    const r = this.rnd;
    const w = this.width;
    const h = this.height;
    const n = particlesFor(this.spec.density, w, h);
    const snow = this.snow;
    for (let i = 0; i < n; i++) {
      const x = r() * w;
      const y = r() * h;
      const v = snow ? 18 + r() * 22 : 420 + r() * 260;
      const len = snow ? 1.2 + r() * 2.2 : 10 + r() * 14;
      const drift = r() * Math.PI * 2;
      const a = 0.35 + r() * 0.5;
      this.drops.push({ x, y, v, len, drift, a });
    }
    for (let i = 0; i < this.spec.clouds; i++) {
      const x = r() * w;
      const y = 10 + r() * (h * 0.28);
      const cw = w * (0.18 + r() * 0.22);
      const ch = h * (0.06 + r() * 0.06);
      const v = 6 + r() * 10;
      const a = 0.45 + r() * 0.3;
      const puffs = 3 + Math.floor(r() * 3);
      const seed = r();
      this.clouds.push({ x, y, w: cw, h: ch, v, a, puffs, seed });
    }
    if (this.spec.fog) {
      for (let i = 0; i < FOG_BLOBS; i++) {
        const x = r() * w;
        const y = h * (0.35 + r() * 0.6);
        const rad = w * (0.25 + r() * 0.25);
        const v = 4 + r() * 6;
        const a = 0.25 + r() * 0.25;
        this.fogBlobs.push({ x, y, r: rad, v, a });
      }
    }
    this.nextFlashAt = 2.5 + r() * 6;
  }

  /** Steps dt seconds, clamped to 0..0.1 like the desktop. */
  advance(dt: number): void {
    const step = dt < 0 ? 0 : dt > 0.1 ? 0.1 : dt;
    this.time += step;
    for (const c of this.clouds) {
      c.x += c.v * step;
      if (c.x - c.w > this.width) c.x = -c.w;
    }
    for (const f of this.fogBlobs) {
      f.x += f.v * step;
      if (f.x - f.r > this.width) f.x = -f.r;
    }
    if (this.spec.kind === 'rain') this.rain(step);
    else if (this.snow) this.fall(step);
    if (this.spec.lightning && this.time >= this.nextFlashAt) {
      this.flash = 1;
      const rumbleDelay = 0.4 + this.rnd() * 1.4;
      this.nextFlashAt = this.time + 7 + this.rnd() * 12;
      this.onFlash?.({ at: this.time, rumbleDelay });
    }
    const faded = this.flash - step * FLASH_DECAY;
    this.flash = faded > 0 ? faded : 0;
  }

  private rain(step: number): void {
    const wind = this.spec.wind;
    for (const p of this.drops) {
      p.y += p.v * step;
      p.x += p.v * wind * step;
      if (p.y > this.height) {
        p.y = -p.len;
        p.x = this.rnd() * this.width;
      }
      if (p.x > this.width) p.x -= this.width;
    }
  }

  private fall(step: number): void {
    for (const p of this.drops) {
      p.drift += step * 0.8;
      p.y += p.v * step;
      p.x += Math.sin(p.drift) * 12 * step;
      if (p.y > this.height) {
        p.y = -4;
        p.x = this.rnd() * this.width;
      }
      if (p.x < 0) p.x += this.width;
      else if (p.x > this.width) p.x -= this.width;
    }
  }
}

/** A cloud's puffs, left to right, as the desktop draws them. */
export function puffsOf(c: Cloud): { x: number; y: number; rx: number; ry: number }[] {
  const out = [];
  for (let p = 0; p < c.puffs; p++) {
    const r = c.h * (0.7 + ((p * 37 + c.seed * 100) % 10) / 20);
    out.push({ x: c.x + (p / c.puffs) * c.w, y: c.y + Math.sin(c.seed * 10 + p) * c.h * 0.3, rx: r * 1.6, ry: r });
  }
  return out;
}

/** Which of the three snow bands a flake draws in. */
export function snowBand(d: Drop): number {
  return d.len < 1.93 ? 0 : d.len < 2.67 ? 1 : 2;
}
