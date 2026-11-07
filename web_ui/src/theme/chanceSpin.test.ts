// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Chance Time spin's web twin reproduces the shared vectors the Dart
// side is pinned to (test/fixtures/chaos/chance_spin_vectors.json), lands
// on the slot it was given for every seed, and jumps clean under reduce
// motion.

import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

import {
  CHANCE_SPIN_SECONDS,
  CHANCE_WHEEL_SLOTS,
  ChanceSpinSim,
  chanceSlotUnderPointer,
  drawChanceSpinPlan,
} from './chanceSpin';

const vectors = JSON.parse(
  readFileSync(join(__dirname, '..', '..', '..', 'test', 'fixtures', 'chaos', 'chance_spin_vectors.json'), 'utf8'),
) as {
  dt: number;
  plans: { seed: number; slot: number; turns: number; within: number; total: number; slotUnderPointer: number }[];
  samples: { time: number; steps: number; angle: number; omega: number; pointer: number; clicks: number; phase: string }[];
  landedStep: number;
  lastClickStep: number;
  finalSlot: number;
};

describe('outcome first', () => {
  it('every plan lands on the slot it was given', () => {
    for (let seed = 1; seed <= 200; seed++) {
      for (let slot = 0; slot < CHANCE_WHEEL_SLOTS; slot++) {
        const plan = drawChanceSpinPlan(seed * 7919, slot);
        expect(chanceSlotUnderPointer(plan.total)).toBe(slot);
        expect(plan.turns).toBeGreaterThanOrEqual(4);
        expect(plan.turns).toBeLessThanOrEqual(6);
      }
    }
  });
});

describe('shared vectors', () => {
  it('the plans draw the recorded turns, stop and total', () => {
    for (const v of vectors.plans) {
      const plan = drawChanceSpinPlan(v.seed, v.slot);
      expect(plan.turns).toBe(v.turns);
      expect(plan.within).toBeCloseTo(v.within, 9);
      expect(plan.total).toBeCloseTo(v.total, 9);
      expect(chanceSlotUnderPointer(plan.total)).toBe(v.slotUnderPointer);
    }
  });

  it('the stepped sim reproduces every sample', () => {
    const first = vectors.plans[0];
    const sim = new ChanceSpinSim(drawChanceSpinPlan(first.seed, first.slot));
    sim.start();
    let steps = 0;
    let landedStep = -1;
    let lastClickStep = 0;
    let clicks = 0;
    for (const s of vectors.samples) {
      while (steps < s.steps) {
        if (sim.step(vectors.dt)) landedStep = steps;
        steps++;
        if (sim.clicks !== clicks) {
          clicks = sim.clicks;
          lastClickStep = steps;
        }
      }
      expect(sim.angle).toBeCloseTo(s.angle, 9);
      expect(sim.omega).toBeCloseTo(s.omega, 9);
      expect(sim.pointer).toBeCloseTo(s.pointer, 9);
      expect(sim.clicks).toBe(s.clicks);
      expect(sim.phase).toBe(s.phase);
    }
    expect(landedStep).toBe(vectors.landedStep);
    expect(lastClickStep).toBe(vectors.lastClickStep);
    expect(chanceSlotUnderPointer(sim.angle)).toBe(vectors.finalSlot);
  });

  it('the last peg passes in the final second', () => {
    const lastClick = vectors.lastClickStep * vectors.dt;
    expect(lastClick).toBeGreaterThan(CHANCE_SPIN_SECONDS - 1);
    expect(lastClick).toBeLessThan(CHANCE_SPIN_SECONDS);
  });
});

describe('reduce motion', () => {
  it('jumps to the settled stop with nothing swung and never re-lands', () => {
    const plan = drawChanceSpinPlan(99, 6);
    const sim = new ChanceSpinSim(plan);
    sim.jumpToEnd();
    expect(sim.landed).toBe(true);
    expect(sim.settled).toBe(true);
    expect(sim.phase).toBe('reveal');
    expect(sim.angle).toBe(plan.total);
    expect(sim.pointer).toBe(0);
    expect(chanceSlotUnderPointer(sim.angle)).toBe(6);
    expect(sim.step(1 / 60)).toBe(false);
  });
});
