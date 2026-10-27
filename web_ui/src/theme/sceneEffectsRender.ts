// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// How the chat canvas draws the sim's numbers so the weather reads as
// weather: depth in the rain and the snow, a storm that strikes, fog that
// lies on the ground and breathes, clouds with a lit top. The twin of
// lib/services/chat/scene/scene_effects_render.dart: pure arithmetic over
// the sim's state, same numbers, so the sim and its vectors stay as they
// are. Every alpha is a share of the paint's own ceiling and nothing here
// draws past the readability bounds (clouds 0.75, fog 0.5 of their paints).

import { mulberry32, type Drop } from './sceneEffects';

export const RAIN_BAND_WIDTH = [0.7, 1.0, 1.7];
export const RAIN_BAND_LENGTH = [0.65, 1.0, 1.35];
export const RAIN_BAND_ALPHA = [0.45, 0.8, 1.0];

export const FAR_SHEET_DX = 0.5;
export const FAR_SHEET_DY = 0.37;
export const FAR_SHEET_LENGTH = 0.5;
export const FAR_SHEET_WIDTH = 0.6;
export const FAR_SHEET_ALPHA = 0.3;

export const SPLASH_ZONE = 14;
export const SPLASH_ALPHA = 0.6;

export const SNOW_HALO_WIDTH = 2.4;
export const SNOW_HALO_ALPHA = 0.16;
export const SNOW_FAR_ALPHA = 0.3;

export const CLOUD_BODY_ALPHA = 0.62;
export const CLOUD_TOP_ALPHA = 0.32;
export const CLOUD_TOP_SCALE = 0.78;
export const CLOUD_TOP_LIFT = 0.22;

export const GROUND_FOG_STRIPES = 24;
export const GROUND_FOG_HEIGHT = 0.3;
export const GROUND_FOG_ALPHA = 0.35;

export const BOLT_GLOW_WIDTH = 7;
export const BOLT_GLOW_ALPHA = 0.35;
export const BOLT_CORE_WIDTH = 2;
export const BOLT_CORE_ALPHA = 0.95;

/** Which depth band a raindrop draws in: 0 far, 1 mid, 2 near. */
export function rainBand(d: Drop): number {
  return d.a < 0.52 ? 0 : d.a < 0.68 ? 1 : 2;
}

/** How much of the ground fog's peak shows at `time` seconds. */
export function groundFogBreath(time: number): number {
  return 0.8 + 0.2 * Math.sin(time * 0.35);
}

/** The ground fog's alpha share for stripe `i`, top to bottom, before the breath. */
export function groundFogStripeAlpha(i: number): number {
  const t = (i + 1) / GROUND_FOG_STRIPES;
  return GROUND_FOG_ALPHA * t * t;
}

/** A fog blob's slow vertical bob, as a share of the stage's height. */
export function fogBob(i: number, time: number): number {
  return Math.sin(time * 0.25 + i * 1.7) * 0.015;
}

/** A cloud's slow vertical bob, as a share of the stage's height. */
export function cloudBob(seed: number, time: number): number {
  return Math.sin(time * 0.1 + seed * Math.PI * 2) * 0.01;
}

/** The flash's shown strength for the sim's decaying flash: strike, dark beat, second strike, fade. */
export function flashShape(flash: number): number {
  if (flash <= 0) return 0;
  if (flash > 0.72) return 1;
  if (flash > 0.58) return 0.15;
  if (flash > 0.42) return 0.85;
  return (flash / 0.42) * 0.6;
}

export interface Bolt { trunk: [number, number][]; branch: [number, number][] }

/**
 * A lightning bolt's trunk and one branch in canvas pixels, from the scene's
 * seed and the flash's place in the schedule (nextFlashAt, already moved on
 * to the next strike when the flash fires, so fixed for the flash's life).
 */
export function sceneBolt(seed: number, nextFlashAt: number, width: number, height: number): Bolt {
  const r = mulberry32((seed ^ Math.floor(nextFlashAt * 1000)) >>> 0);
  const segments = 9;
  const trunk: [number, number][] = [];
  let x = width * (0.15 + r() * 0.7);
  let y = -4;
  trunk.push([x, y]);
  const reach = height * 0.55;
  for (let i = 0; i < segments; i++) {
    y += (reach / segments) * (0.7 + r() * 0.6);
    x += (r() - 0.5) * width * 0.06;
    trunk.push([x, y]);
  }
  const branch: [number, number][] = [trunk[3]];
  let bx = trunk[3][0];
  let by = trunk[3][1];
  const side = r() < 0.5 ? -1 : 1;
  for (let i = 0; i < 4; i++) {
    by += (reach / segments) * (0.5 + r() * 0.5);
    bx += side * (0.2 + r() * 0.8) * width * 0.03;
    branch.push([bx, by]);
  }
  return { trunk, branch };
}
