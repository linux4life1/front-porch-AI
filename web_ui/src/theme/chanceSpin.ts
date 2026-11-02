// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Chance Time wheel's spin as plain maths: the twin of
// lib/services/chat/chaos/chance_spin.dart, same plan, same ease, same
// pointer spring and phases, pinned to the same vectors
// (test/fixtures/chaos/chance_spin_vectors.json). Outcome first: the slot
// is decided before anything moves and the plan solves the spin that
// lands on it; the canvas only dresses what this says.

import { mulberry32 } from './sceneEffects';

export const CHANCE_WHEEL_SLOTS = 8;
export const CHANCE_SLOT_ANGLE = (2 * Math.PI) / CHANCE_WHEEL_SLOTS;
export const CHANCE_SPIN_SECONDS = 4.2;
export const CHANCE_SETTLE_SECONDS = 0.55;
export const CHANCE_OVERSHOOT = 0.045;

export interface ChanceSpinPlan {
  seed: number;
  slot: number;
  turns: number;
  within: number;
  /** The whole rotation, in radians, from rest to the stop. */
  total: number;
}

/** Four to six full turns, then a stop in the middle half of the slot. */
export function drawChanceSpinPlan(seed: number, slot: number): ChanceSpinPlan {
  const rnd = mulberry32(seed);
  const turns = 4 + Math.floor(rnd() * 3);
  const within = 0.25 + rnd() * 0.5;
  const landIn = slot * CHANCE_SLOT_ANGLE + CHANCE_SLOT_ANGLE * within;
  return { seed, slot, turns, within, total: turns * 2 * Math.PI + (2 * Math.PI - landIn) };
}

/** The slot under the pointer at the top for a wheel turned by `angle`. */
export function chanceSlotUnderPointer(angle: number): number {
  const tau = 2 * Math.PI;
  const back = (tau - (angle % tau)) % tau;
  return Math.floor(back / CHANCE_SLOT_ANGLE) % CHANCE_WHEEL_SLOTS;
}

/** Ease-out with a 2.5 power: quick off the line, a tail that still moves. */
export function chanceEaseOut(t: number): number {
  return 1 - Math.pow(1 - t, 2.5);
}

/** The wheel's angle at `time` seconds: the eased spin, then the settle. */
export function chanceAngleAt(plan: ChanceSpinPlan, time: number): number {
  if (time <= CHANCE_SPIN_SECONDS) return plan.total * chanceEaseOut(time / CHANCE_SPIN_SECONDS);
  const s = time - CHANCE_SPIN_SECONDS;
  return plan.total + CHANCE_OVERSHOOT * Math.exp(-4.5 * s) * Math.sin(14 * s);
}

export type ChanceSpinPhase = 'idle' | 'windup' | 'fast' | 'slowing' | 'nearMiss' | 'landing' | 'reveal';

/** The spin stepped in time; deterministic for a plan and a step size. */
export class ChanceSpinSim {
  time = 0;
  angle = 0;
  omega = 0;
  pointer = 0;
  clicks = 0;
  started = false;
  private pointerV = 0;
  private landedFired = false;

  constructor(readonly plan: ChanceSpinPlan) {}

  get landed(): boolean {
    return this.started && this.time >= CHANCE_SPIN_SECONDS;
  }

  get settled(): boolean {
    return this.started && this.time >= CHANCE_SPIN_SECONDS + CHANCE_SETTLE_SECONDS;
  }

  get progress(): number {
    return Math.min(1, Math.max(0, this.time / CHANCE_SPIN_SECONDS));
  }

  get phase(): ChanceSpinPhase {
    if (!this.started) return 'idle';
    if (!this.landed) {
      if (this.progress < 0.08) return 'windup';
      if (Math.abs(this.omega) > 9) return 'fast';
      if (this.progress < 0.86) return 'slowing';
      return 'nearMiss';
    }
    if (this.settled) return 'reveal';
    return this.time - CHANCE_SPIN_SECONDS < 0.25 ? 'landing' : 'nearMiss';
  }

  start(): void {
    this.started = true;
  }

  /** Straight onto the slot, settled, nothing moved: reduce motion. */
  jumpToEnd(): void {
    this.started = true;
    this.time = CHANCE_SPIN_SECONDS + CHANCE_SETTLE_SECONDS;
    this.angle = this.plan.total;
    this.omega = 0;
    this.pointer = 0;
    this.pointerV = 0;
    this.landedFired = true;
  }

  /** Advances `dt` seconds; true on the one step that lands. */
  step(dt: number): boolean {
    if (!this.started || dt <= 0) return false;
    const prev = this.angle;
    this.time += dt;
    this.angle = chanceAngleAt(this.plan, this.time);
    this.omega = (this.angle - prev) / dt;

    const crossed = Math.floor(this.angle / CHANCE_SLOT_ANGLE) - Math.floor(prev / CHANCE_SLOT_ANGLE);
    if (crossed > 0) {
      this.pointer -= Math.min(0.95, Math.max(0.3, 0.25 + Math.abs(this.omega) * 0.045));
      this.clicks += crossed;
    }
    const k = 260;
    const c = 14;
    const ds = Math.min(dt, 0.1);
    this.pointerV += (-k * this.pointer - c * this.pointerV) * ds;
    this.pointer += this.pointerV * ds;
    this.pointer = Math.min(0.4, Math.max(-1.1, this.pointer));
    if (!this.landed && this.progress > 0.86) this.pointer += Math.sin(this.time * 90) * 0.01;

    if (this.landed && !this.landedFired) {
      this.landedFired = true;
      return true;
    }
    return false;
  }
}

/** FNV-1a 32-bit over the UTF-16 units, the twin of scene_rng.dart's. */
export function fnv1a32(s: string): number {
  let h = 2166136261;
  for (let i = 0; i < s.length; i++) {
    h = Math.imul(h ^ s.charCodeAt(i), 16777619) >>> 0;
  }
  return h >>> 0;
}

/** The reveal the wheel plays for a ChaosCategory name; the same fold the
 * desktop overlay makes. Unknown or missing kinds get Wild Card's. */
export type ChanceRevealEffect = 'fortune' | 'misfortune' | 'chaos' | 'wildCard';

export function chanceRevealEffectFor(kind: string | undefined): ChanceRevealEffect {
  switch (kind) {
    case 'fortune':
      return 'fortune';
    case 'misfortune':
    case 'slapstick':
    case 'needs':
      return 'misfortune';
    case 'chaos':
    case 'weather':
      return 'chaos';
    default:
      return 'wildCard';
  }
}
