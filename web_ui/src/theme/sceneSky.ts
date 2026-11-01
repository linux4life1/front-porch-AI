// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The story-clock sky on the web (docs/design/ambient-stage.md): a
// line-for-line port of lib/services/chat/scene/scene_sky.dart. The six
// period washes are keyframes blended by the minute, a sun and a moon ride
// an arc across the top of the stage, stars come out after sunset, and a
// horizon band glows at dawn and dusk. The minute, the moon's phase, what
// the weather lets through and each brightness's colours come on the wire
// (`scene.sky`, with its `dark` and `light` paints); this file only blends
// and places them. test/fixtures/ambient/scene_sky_vectors.json pins both
// sides.

import type { ThemeMode } from './appTheme';
import { mulberry32 } from './sceneEffects';

export const SUNRISE = 360;
export const SUNSET = 1110;
export const MOONRISE = 1140;
export const MOONSET = 330;
export const STAR_DUSK = 150;
export const STAR_FADE_FROM = 300;
export const STAR_FADE_TO = 390;
export const SWEEP_SECONDS = 1.8;
export const STAR_SEED = 0x5ea5bed;
export const STAR_COUNT = 110;
export const STAR_BAND = 0.72;
export const SKY_TOP_ALPHA = 0.5;
export const SKY_FADE = 0.55;
export const HORIZON_ALPHA = 0.22;
export const SUN_LIGHT_SCALE = 0.75;
export const MOON_LIGHT_SCALE = 0.6;
export const STAR_LIGHT_SCALE = 0.55;

/** A colour as its three channels, 0 to 255. */
export type Rgb = [number, number, number];

export interface SkyStop { at: number; colour: Rgb; alpha: number }

/** One brightness's sky colours, from the mode's `sky` map on the wire. */
export interface SkyPaints {
  scale: number;
  stops: SkyStop[];
  sunHigh: Rgb;
  sunLow: Rgb;
  moon: Rgb;
  moonGlow: Rgb;
  star: Rgb;
  dawn: Rgb;
  dusk: Rgb;
}

export interface SceneSkyWire {
  level: 'tint' | 'effects';
  pauseWhileGenerating: boolean;
  dark: boolean;
  minute: number;
  moonPhase: number;
  /** How much of the disc shows, 0 to 1, and how many of the stars. */
  disc: number;
  stars: number;
  paints: SkyPaints;
}

const HEX = /^#([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/;
const RGBA = /^rgba\((\d+), (\d+), (\d+), [0-9.]+\)$/;

/** The channels of a wire colour (`#rrggbb` or `rgba(r, g, b, a)`), or null. */
export function parseRgb(raw: unknown): Rgb | null {
  if (typeof raw !== 'string') return null;
  const hex = HEX.exec(raw);
  if (hex) return [parseInt(hex[1], 16), parseInt(hex[2], 16), parseInt(hex[3], 16)];
  const rgba = RGBA.exec(raw);
  if (rgba) return [Number(rgba[1]), Number(rgba[2]), Number(rgba[3])];
  return null;
}

const finite = (v: unknown, min: number, max: number): v is number =>
  typeof v === 'number' && Number.isFinite(v) && v >= min && v <= max;

function parsePaints(raw: unknown): SkyPaints | null {
  if (!raw || typeof raw !== 'object') return null;
  const p = raw as Record<string, unknown>;
  if (!finite(p.scale, 0, 1) || !Array.isArray(p.stops) || p.stops.length === 0) return null;
  const stops: SkyStop[] = [];
  for (const s of p.stops as unknown[]) {
    if (!s || typeof s !== 'object') return null;
    const o = s as Record<string, unknown>;
    const colour = parseRgb(o.colour);
    if (!colour || !finite(o.at, 0, 1439) || !finite(o.alpha, 0, 1)) return null;
    stops.push({ at: o.at, colour, alpha: o.alpha });
  }
  const names = ['sunHigh', 'sunLow', 'moon', 'moonGlow', 'star', 'dawn', 'dusk'] as const;
  const colours = {} as Record<(typeof names)[number], Rgb>;
  for (const n of names) {
    const c = parseRgb(p[n]);
    if (!c) return null;
    colours[n] = c;
  }
  return { scale: p.scale, stops, ...colours };
}

/**
 * The sky part of a scene from the desktop, painted for [mode], or null
 * when the payload has none (an older desktop) or is not one. Never throws.
 */
export function parseSceneSky(raw: unknown, mode: ThemeMode): SceneSkyWire | null {
  if (!raw || typeof raw !== 'object') return null;
  const w = raw as Record<string, unknown>;
  if (w.level !== 'tint' && w.level !== 'effects') return null;
  const s = w.sky as Record<string, unknown> | undefined;
  if (!s || typeof s !== 'object') return null;
  if (!finite(s.minute, 0, 1439) || !Number.isInteger(s.minute)) return null;
  if (!finite(s.moonPhase, 0, 1) || !finite(s.disc, 0, 1) || !finite(s.stars, 0, 1)) return null;
  // The sky's colours for each brightness ride on the sky itself, not on
  // the mode maps, which keep the keys they shipped with.
  const paints = parsePaints(s[mode]);
  if (!paints) return null;
  return {
    level: w.level,
    pauseWhileGenerating: w.pauseWhileGenerating !== false,
    dark: mode === 'dark',
    minute: s.minute,
    moonPhase: s.moonPhase,
    disc: s.disc,
    stars: s.stars,
    paints,
  };
}

export const smoothstep = (t: number): number => t * t * (3 - 2 * t);
const clamp01 = (v: number): number => (v < 0 ? 0 : v > 1 ? 1 : v);

/** The wash at a minute, blended between the stops around it, wrapping across midnight. */
export function skyWashAt(minute: number, stops: SkyStop[]): { colour: Rgb; alpha: number } {
  for (let i = 0; i < stops.length; i++) {
    const a = stops[i];
    const b = stops[(i + 1) % stops.length];
    const bAt = b.at > a.at ? b.at : b.at + 1440;
    const m = minute >= a.at ? minute : minute + 1440;
    if (m >= a.at && m < bAt) {
      const t = smoothstep((m - a.at) / (bAt - a.at));
      const ac = a.alpha === 0 ? b.colour : a.colour;
      const bc = b.alpha === 0 ? a.colour : b.colour;
      return {
        colour: [ac[0] + (bc[0] - ac[0]) * t, ac[1] + (bc[1] - ac[1]) * t, ac[2] + (bc[2] - ac[2]) * t],
        alpha: a.alpha + (b.alpha - a.alpha) * t,
      };
    }
  }
  return { colour: stops[0].colour, alpha: stops[0].alpha };
}

export interface SkyArc { p: number; x: number; y: number; alt: number }

/** Where a disc is on its arc, or null below the horizon. */
export function skyArcAt(minute: number, rise: number, set: number): SkyArc | null {
  const span = set > rise ? set - rise : set + 1440 - rise;
  const since = minute >= rise ? minute - rise : minute + 1440 - rise;
  if (since > span) return null;
  const p = since / span;
  const alt = Math.sin(Math.PI * p);
  return { p, x: 0.08 + 0.84 * p, y: 0.4 - 0.27 * alt, alt };
}

export function starVisibilityAt(minute: number): number {
  if (minute >= SUNSET && minute < SUNSET + STAR_DUSK) return smoothstep((minute - SUNSET) / STAR_DUSK);
  if (minute >= SUNSET + STAR_DUSK || minute < STAR_FADE_FROM) return 1;
  if (minute < STAR_FADE_TO) return 1 - smoothstep((minute - STAR_FADE_FROM) / (STAR_FADE_TO - STAR_FADE_FROM));
  return 0;
}

export function horizonGlowAt(minute: number): { strength: number; dawn: boolean } {
  const dawn = 1 - clamp01(Math.abs(minute - 380) / 110);
  const dusk = 1 - clamp01(Math.abs(minute - 1100) / 120);
  return dawn >= dusk ? { strength: dawn, dawn: true } : { strength: dusk, dawn: false };
}

export interface SkyStar { x: number; y: number; size: number; alpha: number; phase: number; speed: number }

export function scatterStars(seed: number, count: number): SkyStar[] {
  const r = mulberry32(seed);
  const out: SkyStar[] = [];
  for (let i = 0; i < count; i++) {
    out.push({
      x: r(),
      y: r() * STAR_BAND,
      size: 0.6 + r() * 1.2,
      alpha: 0.35 + r() * 0.55,
      phase: r() * Math.PI * 2,
      speed: 0.6 + r() * 1.4,
    });
  }
  return out;
}

export const starTwinkle = (s: SkyStar, time: number): number => 0.7 + 0.3 * Math.sin(time * s.speed + s.phase);

/**
 * The minute the stage shows, trailing the clock through a sweep: a jump
 * on an animated stage plays forward through the day over SWEEP_SECONDS,
 * and a still one snaps. Stepped by the player's loop.
 */
export class SceneSkyMotion {
  private shownMinute: number;
  private targetMinute: number;
  private from = 0;
  private to = 0;
  private t = 1;
  /** Seconds the stage has animated, for the twinkle. */
  time = 0;

  constructor(minute: number) {
    this.shownMinute = minute;
    this.targetMinute = minute;
  }

  get shown(): number { return ((this.shownMinute % 1440) + 1440) % 1440; }
  get target(): number { return this.targetMinute; }
  get sweeping(): boolean { return this.t < 1; }

  retarget(minute: number, sweep: boolean): void {
    if (minute === this.targetMinute) return;
    this.targetMinute = minute;
    if (!sweep) {
      this.shownMinute = minute;
      this.t = 1;
      return;
    }
    this.from = this.shown;
    let delta = minute - this.from;
    if (delta <= 0) delta += 1440;
    this.to = this.from + delta;
    this.t = 0;
  }

  advance(dt: number): void {
    this.time += dt;
    if (this.t >= 1) return;
    this.t = Math.min(1, this.t + dt / SWEEP_SECONDS);
    this.shownMinute = this.t >= 1 ? this.targetMinute : this.from + (this.to - this.from) * smoothstep(this.t);
  }
}
