// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The render recipe the chat canvas shares with the desktop stage
// (sceneEffectsRender.ts, scene_effects_render.dart): the rain's depth
// bands, the flash's double strike, the fog's mist, and the bolt,
// pinned point for point so both surfaces draw the same strike from the
// same seed and schedule (the Dart test carries the same numbers).

import { describe, expect, it } from 'vitest';
import {
  RAIN_BAND_ALPHA, RAIN_BAND_LENGTH, RAIN_BAND_WIDTH, SPLASH_LIFE,
  SceneSplashes, flashShape, rainBand, rainGust, rainLean, rainLit, sceneBolt,
} from './sceneEffectsRender';
import {
  MIST_HEIGHT, MIST_LAYERS, MIST_SHARE, MIST_WIDTH, mistBreath, mistShift, sceneMist,
} from './sceneFogMist';

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

  // Changed with the fog: it was soft blobs over a striped ground band,
  // which read as a flat grey background, so this pinned the band's
  // stripes and breath. The fog is now two streaming layers of seeded mist
  // (sceneFogMist.ts); the band and its stripes are gone.
  it('builds the desktop\'s fog mist number for number and streams it', () => {
    // The Dart twin (scene_effects_render_test.dart) pins the same numbers.
    const far = sceneMist(1234, 0);
    const near = sceneMist(1234, 1);
    const sum = (m: Float64Array) => m.reduce((a, v) => a + v, 0);
    expect(far).toHaveLength(MIST_WIDTH * MIST_HEIGHT);
    expect(Math.abs(sum(far) - 6247.899714727)).toBeLessThan(1e-6);
    expect(Math.abs(sum(near) - 6625.065326843)).toBeLessThan(1e-6);
    expect(far[5000]).toBeCloseTo(0.119596553, 9);
    expect(near[12345]).toBeCloseTo(0.221341582, 9);
    expect(far.filter((v) => v === 0).length).toBe(5018);
    expect(near.filter((v) => v === 0).length).toBe(3762);
    expect(sceneMist(99, 0)).not.toEqual(far);
    const row = 50 * MIST_WIDTH;
    expect(Math.abs(near[row] - near[row + MIST_WIDTH - 1])).toBeLessThan(0.05);
    expect(mistBreath(1, 7.5)).toBeCloseTo(0.698305943, 9);
    for (let t = 0; t < 60; t += 0.4) {
      for (let l = 0; l < MIST_LAYERS; l++) {
        expect(mistBreath(l, t)).toBeGreaterThanOrEqual(0.6);
        expect(mistBreath(l, t)).toBeLessThanOrEqual(1);
      }
    }
    expect(mistShift(1, 100, 1500)).toBeCloseTo(750, 9);
    expect(mistShift(0, 400, 1500)).toBeCloseTo(300, 9);
    expect(MIST_SHARE.reduce((a, v) => a + v, 0)).toBeLessThanOrEqual(0.5);
  });

  it('the gust swells slowly and the flash lights the rain', () => {
    for (let t = 0; t < 120; t += 0.3) {
      expect(rainGust(t)).toBeGreaterThanOrEqual(0.65);
      expect(rainGust(t)).toBeLessThanOrEqual(1.35);
    }
    expect(rainLit(0)).toBe(1);
    expect(rainLit(1)).toBeCloseTo(1.8, 9);
    expect(rainLean(0, 1)).toBeCloseTo(0, 12);
    expect(rainLean(0.42, 1)).toBeLessThan(0);
    expect(Math.abs(rainLean(0.42, 1.35))).toBeGreaterThan(Math.abs(rainLean(0.42, 1)));
  });

  it('a near drop that respawns leaves a splash where it last was', () => {
    const drops = [
      { x: 100, y: 590, v: 500, len: 12, drift: 0, a: 0.8 },
      { x: 200, y: 590, v: 500, len: 12, drift: 0, a: 0.4 },
    ];
    const splashes = new SceneSplashes();
    splashes.observe(drops, 0, 600);
    expect(splashes.live).toHaveLength(0);
    drops[0].x = 104; drops[0].y = 598; drops[1].y = 598;
    splashes.observe(drops, 0.03, 600);
    expect(splashes.live).toHaveLength(0);
    drops[0].x = 300; drops[0].y = -12; drops[1].x = 310; drops[1].y = -12;
    splashes.observe(drops, 0.06, 600);
    expect(splashes.live).toEqual([{ x: 104, at: 0.06 }]);
    expect(SceneSplashes.progress(splashes.live[0], 0.26)).toBeCloseTo(0.5, 9);
    expect(SceneSplashes.ringRadius(1)).toBe(12);
    expect(SceneSplashes.dropletLift(0.4)).toBeCloseTo(1.6, 9);
    splashes.observe(drops, 0.06 + SPLASH_LIFE + 0.01, 600);
    expect(splashes.live).toHaveLength(0);
  });
});

