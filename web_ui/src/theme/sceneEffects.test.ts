// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The web twin of the Ambient Stage's moving weather (docs/design/ambient-stage.md).
// It reproduces the shared vectors the Dart sim is pinned to as well
// (test/fixtures/ambient/scene_effects_vectors.json, generated from the
// design prototype's own code): the generator, the scatter, the steps and the
// storm's flash schedule. The parser takes what the desktop sends and nothing
// else.

import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import {
  FOG_BLOBS, PARTICLE_CAP, SceneEffectsSim, hasEffects, mulberry32, parseSceneEffects, particlesFor,
  type EffectSpec, type Flash,
} from './sceneEffects';

interface VectorCase {
  condition: string;
  seed: number;
  width: number;
  height: number;
  spec: EffectSpec;
  count: number;
  initial: { drops: number[][]; clouds: number[][]; fogBlobs: number[][]; nextFlashAt: number };
  after: { steps: number; dt: number; drops: number[][]; clouds: number[]; fogBlobs: number[]; flashes: number[][]; flash: number };
}

const vectors = JSON.parse(
  readFileSync(join(__dirname, '..', '..', '..', 'test', 'fixtures', 'ambient', 'scene_effects_vectors.json'), 'utf8'),
) as {
  particleCap: number;
  fogBlobs: number;
  specs: Record<string, EffectSpec>;
  mulberry32: Record<string, number[]>;
  cases: VectorCase[];
};

const wire = {
  level: 'effects',
  seed: 3682408742,
  pauseWhileGenerating: true,
  effects: {
    kind: 'rain',
    density: 0.00035,
    clouds: 6,
    fog: false,
    lightning: false,
    wind: 0.18,
    paints: {
      rain: 'rgba(200, 215, 235, 0.549)',
      snow: 'rgba(255, 255, 255, 0.902)',
      cloud: 'rgba(140, 150, 162, 0.4)',
      fog: 'rgba(169, 177, 187, 0.702)',
      fogClear: 'rgba(169, 177, 187, 0.0)',
      flash: 'rgba(240, 244, 255, 0.6)',
    },
  },
};

describe('scene effects sim', () => {
  it('mulberry32 matches the prototype bit for bit', () => {
    const seeds = Object.keys(vectors.mulberry32);
    expect(seeds.length).toBeGreaterThan(0);
    for (const seed of seeds) {
      const r = mulberry32(Number(seed));
      expect([r(), r(), r(), r(), r()]).toEqual(vectors.mulberry32[seed]);
    }
  });

  it('budgets match the desktop: scale with area, cap at 400', () => {
    expect(PARTICLE_CAP).toBe(vectors.particleCap);
    expect(FOG_BLOBS).toBe(vectors.fogBlobs);
    const { rain, storm, snow } = vectors.specs;
    expect([rain.density, storm.density, snow.density]).toEqual([0.00035, 0.00065, 0.00022]);
    expect([rain.clouds, storm.clouds, snow.clouds, vectors.specs.cloudy.clouds, vectors.specs.overcast.clouds]).toEqual([6, 9, 5, 5, 9]);
    expect(vectors.specs.fog.fog).toBe(true);
    expect(storm.lightning).toBe(true);
    expect(particlesFor(rain.density, 800, 600)).toBe(168);
    expect(particlesFor(rain.density, 1600, 600)).toBe(336);
    for (const s of [rain, storm, snow]) expect(particlesFor(s.density, 3840, 2160)).toBe(PARTICLE_CAP);
  });

  it('a seed scatters the same first frame as the desktop', () => {
    for (const c of vectors.cases) {
      const sim = new SceneEffectsSim(c.spec, c.seed, c.width, c.height);
      expect(sim.drops.length).toBe(c.count);
      c.initial.drops.forEach((d, i) => {
        const p = sim.drops[i];
        expect([p.x, p.y, p.v, p.len, p.drift, p.a]).toEqual(d);
      });
      c.initial.clouds.forEach((d, i) => {
        const k = sim.clouds[i];
        expect([k.x, k.y, k.w, k.h, k.v, k.a, k.puffs, k.seed]).toEqual(d);
      });
      c.initial.fogBlobs.forEach((d, i) => {
        const f = sim.fogBlobs[i];
        expect([f.x, f.y, f.r, f.v, f.a]).toEqual(d);
      });
      expect(sim.nextFlashAt).toBe(c.initial.nextFlashAt);
    }
  });

  it('steps the weather and fires the storm exactly as the desktop does', () => {
    for (const c of vectors.cases) {
      const sim = new SceneEffectsSim(c.spec, c.seed, c.width, c.height);
      const flashes: Flash[] = [];
      sim.onFlash = (f) => flashes.push(f);
      for (let i = 0; i < c.after.steps; i++) sim.advance(c.after.dt);
      c.after.drops.forEach((d, i) => {
        expect(sim.drops[i].x).toBeCloseTo(d[0], 9);
        expect(sim.drops[i].y).toBeCloseTo(d[1], 9);
      });
      expect(sim.clouds.slice(0, 2).map((k) => k.x)).toEqual(c.after.clouds);
      expect(sim.fogBlobs.slice(0, 2).map((f) => f.x)).toEqual(c.after.fogBlobs);
      expect(flashes.map((f) => [f.at, f.rumbleDelay])).toEqual(c.after.flashes);
      expect(sim.flash).toBe(c.after.flash);
    }
    expect(vectors.cases.some((c) => c.after.flashes.length > 0)).toBe(true);
  });
});

describe('scene effects wire', () => {
  it('accepts what the desktop sends', () => {
    const parsed = parseSceneEffects(wire);
    expect(parsed).toEqual(wire);
    expect(hasEffects(parsed)).toBe(true);
    expect(hasEffects(parseSceneEffects({ ...wire, level: 'tint' }))).toBe(false);
    const clear = { ...wire, effects: { ...wire.effects, kind: 'none', density: 0, clouds: 0 } };
    expect(hasEffects(parseSceneEffects(clear))).toBe(false);
    // An older desktop's scene has no effects at all.
    expect(parseSceneEffects({ daypart: 'night', condition: 'rain', temp: 'cold', layers: [], haze: 0 })).toBeNull();
  });

  it('rejects anything that is not one', () => {
    const bad: unknown[] = [
      null,
      'rain',
      { ...wire, level: 'loud' },
      { ...wire, seed: -1 },
      { ...wire, seed: 1.5 },
      { ...wire, seed: 2 ** 33 },
      { ...wire, effects: null },
      { ...wire, effects: { ...wire.effects, kind: 'hail' } },
      { ...wire, effects: { ...wire.effects, density: 'lots' } },
      { ...wire, effects: { ...wire.effects, density: Number.NaN } },
      { ...wire, effects: { ...wire.effects, clouds: 2.5 } },
      { ...wire, effects: { ...wire.effects, clouds: 1e6 } },
      { ...wire, effects: { ...wire.effects, fog: 'yes' } },
      { ...wire, effects: { ...wire.effects, paints: { ...wire.effects.paints, rain: 'url(x)' } } },
      { ...wire, effects: { ...wire.effects, paints: { ...wire.effects.paints, fogClear: undefined } } },
    ];
    for (const b of bad) expect(parseSceneEffects(b)).toBeNull();
  });

  it('pauses while generating unless the desktop says not to', () => {
    expect(parseSceneEffects({ ...wire, pauseWhileGenerating: false })?.pauseWhileGenerating).toBe(false);
    const { pauseWhileGenerating: _omit, ...older } = wire;
    void _omit;
    expect(parseSceneEffects(older)?.pauseWhileGenerating).toBe(true);
  });
});
