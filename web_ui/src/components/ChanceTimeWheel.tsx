// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The phone's Chance Time wheel: a canvas driven by the shared spin sim
// (theme/chanceSpin.ts), the twin of the desktop's Flame wheel. Outcome
// first: the slot comes in as a prop and the spin is solved to land on
// it; nothing here can change it. The canvas dresses the spin (the
// pointer's clicks, bulbs, sparks, the landing and the reveal in the
// result's own key) and tells the modal when the wheel has landed and
// settled. Under reduce motion the wheel jumps to its stop and tells the
// modal at once.

import { useEffect, useRef } from 'react';

import { ChanceSpinSim, drawChanceSpinPlan, type ChanceRevealEffect } from '../theme/chanceSpin';
import { mulberry32 } from '../theme/sceneEffects';
import { freshDressing, landDressing, paintWheel, revealDressing, stepDressing } from './chanceWheelPaint';

export interface ChanceTimeWheelProps {
  seed: number;
  slot: number;
  effect: ChanceRevealEffect;
  /** True once the user has pressed Spin. */
  spinning: boolean;
  reduceMotion: boolean;
  onLanded: () => void;
  onSettled: () => void;
  /** The canvas's width in CSS pixels; its height is the same. */
  size?: number;
}

export function ChanceTimeWheel({
  seed,
  slot,
  effect,
  spinning,
  reduceMotion,
  onLanded,
  onSettled,
  size = 280,
}: ChanceTimeWheelProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const landedRef = useRef(onLanded);
  const settledRef = useRef(onSettled);
  landedRef.current = onLanded;
  settledRef.current = onSettled;

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    // A test DOM has no 2D context; the sim still runs so the modal's
    // beats are the same, only nothing is painted.
    const ctx = canvas.getContext('2d');
    const sim = spinning ? new ChanceSpinSim(drawChanceSpinPlan(seed, slot)) : null;
    const d = freshDressing();
    const rnd = mulberry32((seed ^ 0x9e3779b9) >>> 0);
    let revealFired = false;
    if (sim) {
      if (reduceMotion) {
        sim.jumpToEnd();
        revealFired = true;
        landedRef.current();
        settledRef.current();
      } else {
        sim.start();
      }
    }
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    canvas.width = Math.round(size * dpr);
    canvas.height = Math.round(size * dpr);
    const R = size * 0.4;
    let raf = 0;
    let last = performance.now();
    const frame = (now: number) => {
      const dt = Math.min(1, (now - last) / 1000);
      last = now;
      if (sim && !reduceMotion) {
        if (sim.step(dt)) {
          landDressing(d, sim);
          landedRef.current();
        }
        if (sim.settled && !revealFired) {
          revealFired = true;
          revealDressing(d, effect, rnd);
          settledRef.current();
        }
      }
      stepDressing(d, sim, dt, rnd);
      if (ctx) {
        ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
        paintWheel(ctx, size, size, size / 2, size / 2, R, sim, d);
      }
      // Keep going while something still moves; a still wheel costs nothing.
      const moving = (sim && !sim.settled) || d.parts.length > 0 || d.strobe > 0 || d.dread > 0 || d.shake > 0;
      if (moving || !sim) raf = requestAnimationFrame(frame);
    };
    raf = requestAnimationFrame(frame);
    return () => cancelAnimationFrame(raf);
  }, [seed, slot, effect, spinning, reduceMotion, size]);

  return (
    <canvas
      ref={canvasRef}
      className="chance-wheel"
      style={{ width: size, height: size }}
      role="img"
      aria-label={spinning ? 'The Chance Time wheel, spinning' : 'The Chance Time wheel'}
      data-testid="chance-wheel"
      data-slot={slot}
      data-effect={effect}
    />
  );
}
