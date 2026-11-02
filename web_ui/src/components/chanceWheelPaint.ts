// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Painting for the phone's Chance Time wheel (ChanceTimeWheel.tsx): the
// wheel, its glow and bulbs, the pointer, and the particles the canvas
// drives from the shared spin sim. The palette is the wheel's own
// game-show identity, fixed in every theme like the desktop's
// chance_time_palette.dart; nothing here reads the app theme.

import type { ChanceRevealEffect, ChanceSpinSim } from '../theme/chanceSpin';
import { CHANCE_SLOT_ANGLE, CHANCE_WHEEL_SLOTS } from '../theme/chanceSpin';

/* theme-keep: Chance Time game identity, the desktop wheel's own palette */
export const WHEEL = {
  gold: '#FFD166', // theme-keep: Chance Time game identity
  goldPale: '#FFF9C4', // theme-keep: Chance Time game identity
  onGold: '#1A1200', // theme-keep: Chance Time game identity
  fortune: '#06D6A0', // theme-keep: Chance Time game identity
  misfortune: '#E63946', // theme-keep: Chance Time game identity
  wildCard: '#9B5DE5', // theme-keep: Chance Time game identity
  ash: '#5A5A5A', // theme-keep: Chance Time game identity
  ashEmber: '#7A2A30', // theme-keep: Chance Time game identity
  dread: '40, 0, 10', // theme-keep: Chance Time game identity (rgb parts)
  segments: ['#E63946', '#FF9F1C', '#2EC4B6', '#9B5DE5', '#06D6A0', '#FF6B9D', '#FFD166', '#118AB2'], // theme-keep: Chance Time game identity
  confetti: ['#06D6A0', '#FFD166', '#FF6B9D', '#9B5DE5', '#118AB2'], // theme-keep: Chance Time game identity
};

/** One emoji per slot, as the desktop wheel paints them. */
export const SLOT_EMOJIS = ['🎲', '⚡', '🎯', '🔮', '🎪', '💎', '🌈', '🎭'];

export interface Particle {
  kind: 'spark' | 'emoji' | 'confetti' | 'ash' | 'mote';
  x: number;
  y: number;
  vx: number;
  vy: number;
  life: number;
  age: number;
  col?: string;
  rot?: number;
  vr?: number;
  w?: number;
  h?: number;
  s?: number;
  seed?: number;
  a?: number;
  r?: number;
  va?: number;
  e?: string;
}

/** Everything the canvas needs beyond the sim: the dressing's own state. */
export interface WheelDressing {
  glow: number;
  bulb: number;
  shake: number;
  pop: number;
  flash: number;
  strobe: number;
  dread: number;
  parts: Particle[];
}

export function freshDressing(): WheelDressing {
  return { glow: 0.3, bulb: 0, shake: 0, pop: 0, flash: 0, strobe: 0, dread: 0, parts: [] };
}

/** Steps the dressing by `dt` (clamped for the integrators) from the sim's
 * speed; `rnd` feeds the sparks. */
export function stepDressing(d: WheelDressing, sim: ChanceSpinSim | null, dt: number, rnd: () => number): void {
  const ds = Math.min(dt, 0.1);
  const w = sim ? Math.abs(sim.omega) : 0;
  d.glow = 0.3 + Math.min(1, w / 22) * 0.7;
  d.bulb += w * ds * 1.6 + ds * 2;
  if (sim && !sim.landed && w > 7) {
    const n = Math.min(4, Math.floor(w / 6));
    for (let i = 0; i < n; i++) {
      const a = rnd() * Math.PI * 2;
      const spd = 0.9 + w * 0.045;
      const dir = Math.sign(sim.omega) || 1;
      d.parts.push({
        kind: 'spark',
        x: Math.cos(a),
        y: Math.sin(a),
        vx: -Math.sin(a) * spd * dir + Math.cos(a) * 0.5,
        vy: Math.cos(a) * spd * dir + Math.sin(a) * 0.5,
        life: 0.35 + rnd() * 0.25,
        age: 0,
        col: rnd() < 0.5 ? WHEEL.gold : WHEEL.goldPale,
      });
    }
  }
  d.shake = Math.max(0, d.shake - dt * 3.2);
  d.pop = Math.max(0, d.pop - dt * 2.2);
  d.flash = Math.max(0, d.flash - dt * 2.5);
  d.strobe = Math.max(0, d.strobe - dt);
  d.dread = Math.max(0, d.dread - dt * 0.22);
  for (const p of d.parts) {
    p.age += ds;
    if (p.kind === 'confetti') {
      p.vy += 3.2 * ds;
      p.vx *= 0.985;
      p.vy *= 0.985;
      p.rot = (p.rot ?? 0) + (p.vr ?? 0) * ds;
    } else if (p.kind === 'ash') {
      p.vy += 0.4 * ds;
      p.vx += Math.sin(p.age * 5 + (p.seed ?? 0)) * 0.6 * ds;
    } else if (p.kind === 'mote') {
      p.a = (p.a ?? 0) + (p.va ?? 0) * ds;
      p.r = (p.r ?? 1) + 0.35 * ds;
      p.x = Math.cos(p.a) * p.r;
      p.y = Math.sin(p.a) * p.r;
      continue;
    } else if (p.kind === 'emoji') {
      p.vy += 2.4 * ds;
      p.rot = (p.rot ?? 0) + (p.vr ?? 0) * ds;
    } else {
      p.vy += 1.2 * ds;
    }
    p.x += p.vx * ds;
    p.y += p.vy * ds;
  }
  d.parts = d.parts.filter((p) => p.age < p.life);
}

/** The landing: shake, pop, flash and the slot's emoji thrown out. */
export function landDressing(d: WheelDressing, sim: ChanceSpinSim): void {
  d.shake = 1;
  d.pop = 1;
  d.flash = 1;
  const a = sim.plan.slot * CHANCE_SLOT_ANGLE + CHANCE_SLOT_ANGLE / 2 - Math.PI / 2 + sim.angle;
  d.parts.push({
    kind: 'emoji',
    x: Math.cos(a) * 0.62,
    y: Math.sin(a) * 0.62,
    vx: 0,
    vy: -2.6,
    rot: 0,
    vr: 3,
    life: 1.1,
    age: 0,
    e: SLOT_EMOJIS[sim.plan.slot % SLOT_EMOJIS.length],
  });
}

/** The reveal in the result's own key. A bad result never gets anything
 * festive: Misfortune is a red dim and grey ash, nothing else. */
export function revealDressing(d: WheelDressing, effect: ChanceRevealEffect, rnd: () => number): void {
  if (effect === 'fortune') {
    for (let i = 0; i < 140; i++) {
      const a = -Math.PI / 2 + (rnd() - 0.5) * 1.6;
      const s = 2 + rnd() * 3.5;
      d.parts.push({
        kind: 'confetti',
        x: 0,
        y: 1.3,
        vx: Math.cos(a) * s,
        vy: Math.sin(a) * s,
        rot: rnd() * Math.PI * 2,
        vr: (rnd() - 0.5) * 16,
        w: 0.05 + rnd() * 0.05,
        h: 0.03,
        life: 2.2 + rnd(),
        age: 0,
        col: WHEEL.confetti[i % WHEEL.confetti.length],
      });
    }
  } else if (effect === 'misfortune') {
    d.dread = 1;
    for (let i = 0; i < 50; i++) {
      d.parts.push({
        kind: 'ash',
        x: (rnd() - 0.5) * 3.2,
        y: -1.8 + rnd() * 0.4,
        vx: 0,
        vy: 0.25 + rnd() * 0.4,
        life: 3 + rnd() * 1.5,
        age: 0,
        seed: rnd() * 9,
        col: rnd() < 0.2 ? WHEEL.ashEmber : WHEEL.ash,
        s: 0.015 + rnd() * 0.025,
      });
    }
  } else if (effect === 'chaos') {
    d.strobe = 1.2;
    for (let i = 0; i < 60; i++) {
      const a = rnd() * Math.PI * 2;
      const s = 2.5 + rnd() * 4;
      d.parts.push({ kind: 'spark', x: 0, y: 0, vx: Math.cos(a) * s, vy: Math.sin(a) * s, life: 0.5 + rnd() * 0.5, age: 0, col: i % 3 ? WHEEL.gold : WHEEL.goldPale });
    }
  } else {
    for (let i = 0; i < 36; i++) {
      const a = rnd() * Math.PI * 2;
      d.parts.push({ kind: 'mote', a, r: 1.05 + rnd() * 0.3, va: 1.2 + rnd() * 1.4, x: 0, y: 0, vx: 0, vy: 0, life: 2.4 + rnd(), age: 0, s: 0.02 + rnd() * 0.03 });
    }
  }
}

function roundedSlice(ctx: CanvasRenderingContext2D, r: number, start: number): void {
  ctx.beginPath();
  ctx.moveTo(0, 0);
  ctx.arc(0, 0, r, start, start + CHANCE_SLOT_ANGLE);
  ctx.closePath();
}

/** Paints one frame. `R` is the wheel's radius in CSS pixels, the wheel is
 * centred on (cx, cy), and the canvas is `w` by `h`. */
export function paintWheel(
  ctx: CanvasRenderingContext2D,
  w: number,
  h: number,
  cx: number,
  cy: number,
  R: number,
  sim: ChanceSpinSim | null,
  d: WheelDressing,
): void {
  ctx.clearRect(0, 0, w, h);
  const angle = sim?.angle ?? 0;
  if (d.dread > 0) {
    const v = ctx.createRadialGradient(cx, cy, R * 0.6, cx, cy, Math.max(w, h) * 0.8);
    v.addColorStop(0, `rgba(${WHEEL.dread},0)`); // theme-keep: Chance Time game identity
    v.addColorStop(1, `rgba(${WHEEL.dread},${d.dread * 0.75})`); // theme-keep: Chance Time game identity
    ctx.fillStyle = v;
    ctx.fillRect(0, 0, w, h);
  }
  const sx = (Math.random() - 0.5) * d.shake * R * 0.06;
  const sy = (Math.random() - 0.5) * d.shake * R * 0.06;
  ctx.save();
  ctx.translate(cx + sx, cy + sy);

  // Glow: breathes with speed, red and dim under a Misfortune.
  const glowA = (0.18 + d.glow * 0.45) * (1 - d.dread * 0.6);
  const gc = `${Math.round(255 - d.dread * 25)},${Math.round(209 - d.dread * 152)},${Math.round(102 - d.dread * 32)}`;
  const gr = ctx.createRadialGradient(0, 0, R * 0.85, 0, 0, R * (1.22 + d.glow * 0.12));
  gr.addColorStop(0, `rgba(${gc},0)`); // theme-keep: Chance Time game identity
  gr.addColorStop(0.7, `rgba(${gc},${glowA})`); // theme-keep: Chance Time game identity
  gr.addColorStop(1, `rgba(${gc},0)`); // theme-keep: Chance Time game identity
  ctx.fillStyle = gr;
  ctx.beginPath();
  ctx.arc(0, 0, R * 1.35, 0, Math.PI * 2);
  ctx.fill();

  // Bulbs chase at wheel speed; they die under a Misfortune.
  const nb = 24;
  const step = (Math.PI * 2) / nb;
  const lit = Math.floor(d.bulb / step);
  for (let i = 0; i < nb; i++) {
    const on = (((i - lit) % 3) + 3) % 3 === 0 && d.dread < 0.6;
    const a = i * step - Math.PI / 2;
    ctx.beginPath();
    ctx.arc(Math.cos(a) * R * 1.085, Math.sin(a) * R * 1.085, R * 0.028, 0, Math.PI * 2);
    ctx.fillStyle = on ? WHEEL.goldPale : `rgba(255,209,102,0.25)`; // theme-keep: Chance Time game identity
    ctx.shadowColor = WHEEL.gold;
    ctx.shadowBlur = on ? R * 0.08 : 0;
    ctx.fill();
  }
  ctx.shadowBlur = 0;

  // The wheel, turned.
  ctx.save();
  ctx.rotate(angle);
  for (let i = 0; i < CHANCE_WHEEL_SLOTS; i++) {
    const a0 = i * CHANCE_SLOT_ANGLE - Math.PI / 2;
    roundedSlice(ctx, R * 0.96, a0);
    ctx.fillStyle = WHEEL.segments[i % WHEEL.segments.length];
    ctx.fill();
    ctx.strokeStyle = 'rgba(0,0,0,0.45)'; // theme-keep: Chance Time game identity, the wheel's ink edges
    ctx.lineWidth = Math.max(1, R * 0.012);
    ctx.stroke();
  }
  ctx.font = `${Math.round(R * 0.2)}px sans-serif`;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  for (let i = 0; i < CHANCE_WHEEL_SLOTS; i++) {
    const a = i * CHANCE_SLOT_ANGLE - Math.PI / 2 + CHANCE_SLOT_ANGLE / 2;
    ctx.fillText(SLOT_EMOJIS[i % SLOT_EMOJIS.length], Math.cos(a) * R * 0.6, Math.sin(a) * R * 0.6 + R * 0.01);
  }
  // The landed slot pops and flashes.
  if (sim && sim.landed && (d.pop > 0 || d.flash > 0)) {
    roundedSlice(ctx, R * 0.96 * (1 + d.pop * 0.06), sim.plan.slot * CHANCE_SLOT_ANGLE - Math.PI / 2);
    ctx.globalAlpha = d.pop * 0.9;
    ctx.fillStyle = WHEEL.segments[sim.plan.slot % WHEEL.segments.length];
    ctx.fill();
    ctx.globalAlpha = d.flash * 0.7;
    ctx.fillStyle = WHEEL.goldPale;
    ctx.fill();
    ctx.globalAlpha = 1;
  }
  ctx.restore();

  // Rim and hub.
  ctx.beginPath();
  ctx.arc(0, 0, R * 0.98, 0, Math.PI * 2);
  ctx.strokeStyle = WHEEL.gold;
  ctx.lineWidth = R * 0.04;
  ctx.stroke();
  const hub = ctx.createRadialGradient(0, 0, 0, 0, 0, R * 0.1);
  hub.addColorStop(0, WHEEL.goldPale);
  hub.addColorStop(1, WHEEL.gold);
  ctx.beginPath();
  ctx.arc(0, 0, R * 0.1, 0, Math.PI * 2);
  ctx.fillStyle = hub;
  ctx.fill();
  ctx.strokeStyle = 'rgba(0,0,0,0.4)'; // theme-keep: Chance Time game identity, the wheel's ink edges
  ctx.lineWidth = R * 0.015;
  ctx.stroke();

  // The pointer pivots at its top and bends back against the spin.
  ctx.save();
  ctx.translate(0, -R * 1.07);
  if (sim) ctx.rotate(sim.pointer * (sim.omega < 0 ? -1 : 1));
  ctx.beginPath();
  ctx.moveTo(-R * 0.08, 0);
  ctx.lineTo(R * 0.08, 0);
  ctx.lineTo(0, R * 0.2);
  ctx.closePath();
  ctx.fillStyle = WHEEL.gold;
  ctx.fill();
  ctx.strokeStyle = 'rgba(0,0,0,0.55)'; // theme-keep: Chance Time game identity, the wheel's ink edges
  ctx.lineWidth = R * 0.012;
  ctx.stroke();
  ctx.restore();

  // Particles, in wheel units.
  for (const p of d.parts) {
    const fade = 1 - p.age / p.life;
    if (p.kind === 'spark') {
      ctx.globalAlpha = fade;
      ctx.fillStyle = p.col ?? WHEEL.gold;
      ctx.beginPath();
      ctx.arc(p.x * R, p.y * R, R * 0.018, 0, Math.PI * 2);
      ctx.fill();
    } else if (p.kind === 'mote') {
      ctx.globalAlpha = fade * 0.9;
      ctx.fillStyle = WHEEL.wildCard;
      ctx.shadowColor = WHEEL.wildCard;
      ctx.shadowBlur = R * 0.06;
      ctx.beginPath();
      ctx.arc(p.x * R, p.y * R, (p.s ?? 0.02) * R * 1.4, 0, Math.PI * 2);
      ctx.fill();
      ctx.shadowBlur = 0;
    } else if (p.kind === 'emoji') {
      ctx.save();
      ctx.translate(p.x * R, p.y * R);
      ctx.rotate(p.rot ?? 0);
      ctx.globalAlpha = fade;
      ctx.font = `${Math.round(R * 0.32)}px sans-serif`;
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText(p.e ?? '', 0, 0);
      ctx.restore();
    } else if (p.kind === 'ash') {
      ctx.globalAlpha = fade * 0.85;
      ctx.fillStyle = p.col ?? WHEEL.ash;
      ctx.beginPath();
      ctx.arc(p.x * R, p.y * R, (p.s ?? 0.02) * R, 0, Math.PI * 2);
      ctx.fill();
    } else {
      ctx.save();
      ctx.translate(p.x * R, p.y * R);
      ctx.rotate(p.rot ?? 0);
      ctx.globalAlpha = Math.min(1, fade * 2);
      ctx.fillStyle = p.col ?? WHEEL.gold;
      const ww = (p.w ?? 0.05) * R;
      const hh = (p.h ?? 0.03) * R * (0.4 + Math.abs(Math.sin((p.rot ?? 0) * 2)) * 0.6);
      ctx.fillRect(-ww / 2, -hh / 2, ww, hh);
      ctx.restore();
    }
    ctx.globalAlpha = 1;
  }
  ctx.restore();

  if (d.strobe > 0) {
    const a = (Math.sin(d.strobe * Math.PI * 6) * 0.5 + 0.5) * Math.min(1, d.strobe) * 0.35;
    ctx.fillStyle = `rgba(255,209,102,${a})`; // theme-keep: Chance Time game identity
    ctx.fillRect(0, 0, w, h);
  }
}
