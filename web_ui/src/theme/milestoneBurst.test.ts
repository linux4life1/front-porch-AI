// The milestone celebration's web twin reproduces the shared vectors the Dart
// sim is pinned to (test/fixtures/growth/milestone_burst_vectors.json), so
// the canvas and Flame paint the same particles frame for frame.

import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

import {
  burstDone,
  burstKindForWire,
  burstSeedFor,
  planMilestoneBurst,
  stepBurstTo,
  type BurstKind,
} from './milestoneBurst';

interface VParticle {
  shape: string;
  color: number;
  x: number;
  y: number;
  size: number;
  rot: number;
  alpha: number;
}
interface VFrame {
  frame: number;
  alphaSum: number;
  particles: VParticle[];
}
interface VRun {
  kind: BurstKind;
  seed: number;
  count: number;
  duration: number;
  frames: VFrame[];
}

const vectors = JSON.parse(
  readFileSync(
    join(__dirname, '..', '..', '..', 'test', 'fixtures', 'growth', 'milestone_burst_vectors.json'),
    'utf8',
  ),
) as { momentId: string; momentSeed: number; runs: VRun[] };

const near = (got: number, want: number, why: string) =>
  expect(Math.abs(got - want), why).toBeLessThan(1e-9);

describe('shared vectors', () => {
  it('hashes a moment id to the same seed as Dart', () => {
    expect(burstSeedFor(vectors.momentId)).toBe(vectors.momentSeed);
  });

  for (const run of vectors.runs) {
    it(`${run.kind} seed ${run.seed} matches frame for frame`, () => {
      const burst = planMilestoneBurst(run.kind, run.seed);
      expect(burst.particles.length).toBe(run.count);
      near(burst.duration, run.duration, 'duration');
      for (const f of run.frames) {
        stepBurstTo(burst, f.frame);
        near(
          burst.particles.reduce((s, p) => s + p.alpha, 0),
          f.alphaSum,
          `frame ${f.frame} alphaSum`,
        );
        f.particles.forEach((want, i) => {
          const p = burst.particles[i];
          const at = `frame ${f.frame} #${i}`;
          expect(p.shape, at).toBe(want.shape);
          expect(p.color, at).toBe(want.color);
          near(p.x, want.x, `${at} x`);
          near(p.y, want.y, `${at} y`);
          near(p.size, want.size, `${at} size`);
          near(p.rot, want.rot, `${at} rot`);
          near(p.alpha, want.alpha, `${at} alpha`);
        });
      }
    });
  }
});

describe('the sim', () => {
  it('ends dark for every kind', () => {
    for (const kind of ['newBoon', 'newBogey', 'masterBoon', 'masterBogey', 'overcome'] as BurstKind[]) {
      const b = planMilestoneBurst(kind, 4242);
      stepBurstTo(b, Math.ceil(b.duration * 60) + 1);
      expect(burstDone(b)).toBe(true);
      expect(b.particles.every((p) => p.alpha === 0)).toBe(true);
    }
  });

  it('maps every wire kind', () => {
    for (const w of ['new_boon', 'new_bogey', 'master_boon', 'master_bogey', 'overcome']) {
      expect(burstKindForWire(w)).not.toBeNull();
    }
  });
});
