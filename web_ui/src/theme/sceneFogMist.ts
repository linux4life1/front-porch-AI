// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// How the chat canvas draws fog: two layers of mist, far and near, each a
// seeded texture of wispy value noise thickest toward the ground, streaming
// sideways at its own speed and breathing slowly. The twin of
// lib/services/chat/scene/scene_fog_mist.dart: the same texture number for
// number from the scene's seed, and the layers' shares of the fog paint sum
// to 0.5, the fog bound the readability floor test composites.

import { mulberry32 } from './sceneEffects';

export const MIST_WIDTH = 192;
export const MIST_HEIGHT = 96;
export const MIST_LAYERS = 2;
export const MIST_CELLS_X = [4, 8];
export const MIST_CELLS_Y = [4, 7];
export const MIST_SHARE = [0.2, 0.3];
export const MIST_SPAN = 1.5;
export const MIST_SPEED = [0.008, 0.02];
export const MIST_GROUND = [0.18, 0.3];
export const MIST_FROM = [0.42, 0.5];
export const MIST_FULL = [0.78, 0.85];

const OCTAVES = 5;
const LATTICE = 256;

/** Layer `layer`'s density, 0 to 1, for the scene `seed`: row by row, MIST_WIDTH by MIST_HEIGHT. */
export function sceneMist(seed: number, layer: number): Float64Array {
  const r = mulberry32((seed ^ (0x9e3779b9 * (layer + 1))) >>> 0);
  const lat = new Float64Array(LATTICE * LATTICE);
  for (let i = 0; i < lat.length; i++) lat[i] = r();
  const cellsX = MIST_CELLS_X[layer];
  const cellsY = MIST_CELLS_Y[layer];
  const from = MIST_FROM[layer];
  const span = MIST_FULL[layer] - from;
  const ground = MIST_GROUND[layer];
  const out = new Float64Array(MIST_WIDTH * MIST_HEIGHT);
  for (let y = 0; y < MIST_HEIGHT; y++) {
    const v = (y + 0.5) / MIST_HEIGHT;
    const lift = ground * v * v;
    for (let x = 0; x < MIST_WIDTH; x++) {
      const u = (x + 0.5) / MIST_WIDTH;
      let sum = 0;
      let amp = 0.5;
      let norm = 0;
      let period = cellsX;
      for (let o = 0; o < OCTAVES; o++) {
        sum += amp * noise(lat, u * period, v * cellsY * (1 << o), period);
        norm += amp;
        amp *= 0.5;
        period *= 2;
      }
      const raw = (sum / norm + lift - from) / span;
      const t = raw < 0 ? 0 : raw > 1 ? 1 : raw;
      out[y * MIST_WIDTH + x] = t * t * (3 - 2 * t);
    }
  }
  return out;
}

/** Smoothed value noise on the lattice, wrapping sideways every `period` cells so a tile meets itself. */
function noise(lat: Float64Array, x: number, y: number, period: number): number {
  const xi = Math.floor(x);
  const yi = Math.floor(y);
  const fx = x - xi;
  const fy = y - yi;
  const i0 = xi % period;
  const i1 = (xi + 1) % period;
  const j0 = (yi % LATTICE) * LATTICE;
  const j1 = ((yi + 1) % LATTICE) * LATTICE;
  const u = fx * fx * (3 - 2 * fx);
  const w = fy * fy * (3 - 2 * fy);
  const top = lat[j0 + i0] + (lat[j0 + i1] - lat[j0 + i0]) * u;
  const bottom = lat[j1 + i0] + (lat[j1 + i1] - lat[j1 + i0]) * u;
  return top + (bottom - top) * w;
}

/** How much of layer `layer`'s share shows at `time`: its own slow phase between 0.6 and 1. */
export function mistBreath(layer: number, time: number): number {
  return 0.8 + 0.2 * Math.sin(time * 0.21 + layer * 2.1);
}

/** How far layer `layer`'s tiles have streamed right at `time`, in pixels within one tile. */
export function mistShift(layer: number, time: number, width: number): number {
  return (time * MIST_SPEED[layer] * width) % (width * MIST_SPAN);
}
