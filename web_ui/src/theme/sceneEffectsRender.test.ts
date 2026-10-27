// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The render recipe the chat canvas shares with the desktop stage
// (sceneEffectsRender.ts, scene_effects_render.dart): the rain's depth
// bands, the flash's double strike, the ground fog's breath, and the bolt,
// pinned point for point so both surfaces draw the same strike from the
// same seed and schedule (the Dart test carries the same numbers).

import { describe, expect, it } from 'vitest';
import {
  GROUND_FOG_ALPHA, GROUND_FOG_STRIPES, RAIN_BAND_ALPHA, RAIN_BAND_LENGTH, RAIN_BAND_WIDTH,
  flashShape, groundFogBreath, groundFogStripeAlpha, rainBand, sceneBolt,
} from './sceneEffectsRender';

const drop = (a: number) => ({ x: 0, y: 0, v: 500, len: 12, drift: 0, a });
const round = (p: [number, number]) => p.map((v) => +v.toFixed(6));

describe('scene effects render recipe', () => {
  it('bands the rain by depth, nearest thickest, longest and brightest', () => {
    expect([0.35, 0.519, 0.52, 0.679, 0.68, 0.85].map((a) => rainBand(drop(a)))).toEqual([0, 0, 1, 1, 2, 2]);
    expect(RAIN_BAND_WIDTH[2]).toBeGreaterThan(RAIN_BAND_WIDTH[0]);
    expect(RAIN_BAND_LENGTH[2]).toBeGreaterThan(RAIN_BAND_LENGTH[0]);
    expect(RAIN_BAND_ALPHA[2]).toBeGreaterThan(RAIN_BAND_ALPHA[0]);
  });

  it('the flash strikes, goes dark, strikes again, then fades', () => {
    expect([1, 0.8, 0.65, 0.5, 0.3, 0.1].map(flashShape)).toEqual([1, 1, 0.15, 0.85, 0.42857142857142855, 0.14285714285714285]);
    expect(flashShape(0)).toBe(0);
  });

  it('draws the desktop\'s bolt, point for point, and a new one per strike', () => {
    const bolt = sceneBolt(42, 5.25, 800, 600);
    expect(bolt.trunk.map(round)).toEqual([
      [497.128779, -4], [473.207176, 26.016709], [453.541704, 53.757031], [463.235904, 101.213117],
      [466.208353, 136.280404], [466.268532, 178.425947], [488.195109, 209.236266], [495.113193, 238.655899],
      [478.161625, 270.981947], [482.522538, 312.643633],
    ]);
    expect(bolt.branch.map(round)).toEqual([
      [463.235904, 101.213117], [487.188566, 128.380062], [507.448071, 153.882795], [520.100893, 182.413338], [533.783087, 210.828382],
    ]);
    expect(bolt.branch[0]).toEqual(bolt.trunk[3]);
    expect(sceneBolt(42, 17.5, 800, 600).trunk).not.toEqual(bolt.trunk);
    expect(sceneBolt(42, 5.25, 800, 600).trunk).toEqual(bolt.trunk);
  });

  it('lays the ground fog thickest at the ground and breathes it', () => {
    expect(groundFogStripeAlpha(0)).toBeLessThan(groundFogStripeAlpha(GROUND_FOG_STRIPES - 1));
    expect(groundFogStripeAlpha(GROUND_FOG_STRIPES - 1)).toBe(GROUND_FOG_ALPHA);
    expect(GROUND_FOG_ALPHA).toBeLessThanOrEqual(0.5);
    for (let t = 0; t < 40; t += 0.7) {
      expect(groundFogBreath(t)).toBeGreaterThanOrEqual(0.6);
      expect(groundFogBreath(t)).toBeLessThanOrEqual(1);
    }
  });
});
