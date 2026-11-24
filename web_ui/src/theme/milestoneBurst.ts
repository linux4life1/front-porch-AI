// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The milestone celebration, as plain maths — the web twin of
// lib/services/chat/milestone_burst.dart (docs/design/boons-and-bogies.md
// §7, ruling 12 as amended). Both are pinned to
// test/fixtures/growth/milestone_burst_vectors.json; a canvas paints this on
// web, Flame paints the Dart one on desktop.
//
// Keep it a line-for-line twin: every random draw happens in the Dart
// file's order (including zero-width ranges, which still draw), motion is
// fixed 1/60 s steps of + − × ÷ only, units are card widths with the origin
// at the card's centre and y down.

import { fnv1a32 } from './chanceSpin';
import { mulberry32 } from './sceneEffects';

export const BURST_DT = 1 / 60;
export const BURST_BADGE_AT = 0.35;

export type BurstKind = 'newBoon' | 'newBogey' | 'masterBoon' | 'masterBogey' | 'overcome';
export type BurstShape = 'glow' | 'spark' | 'confetti' | 'smoke' | 'shard' | 'ember';

export function burstKindForWire(wire: string): BurstKind | null {
  switch (wire) {
    case 'new_boon':
      return 'newBoon';
    case 'new_bogey':
      return 'newBogey';
    case 'master_boon':
      return 'masterBoon';
    case 'master_bogey':
      return 'masterBogey';
    case 'overcome':
      return 'overcome';
    default:
      return null;
  }
}

/** Palette slots, in milestone_palette.dart order. */
export const BurstColor = {
  gold: 0,
  goldDeep: 1,
  violet: 2,
  smoke: 3,
  overcome: 4,
  pink: 5,
  blue: 6,
  white: 7,
} as const;

interface ShapeRule {
  drag: number;
  gravity: number;
  peak: number;
  fadeIn: number;
}

const RULES: Record<BurstShape, ShapeRule> = {
  glow: { drag: 0.98, gravity: -0.06, peak: 0.6, fadeIn: 0.18 },
  spark: { drag: 0.94, gravity: 0.6, peak: 1.0, fadeIn: 0.04 },
  confetti: { drag: 0.985, gravity: 1.4, peak: 1.0, fadeIn: 0.05 },
  smoke: { drag: 0.97, gravity: -0.05, peak: 0.45, fadeIn: 0.2 },
  shard: { drag: 0.95, gravity: 0.9, peak: 0.9, fadeIn: 0.04 },
  ember: { drag: 0.96, gravity: -0.2, peak: 0.85, fadeIn: 0.08 },
};

export interface BurstParticle {
  shape: BurstShape;
  color: number;
  x: number;
  y: number;
  vx: number;
  vy: number;
  size: number;
  rot: number;
  grow: number;
  vrot: number;
  delay: number;
  life: number;
  age: number;
  alpha: number;
}

export interface MilestoneBurst {
  kind: BurstKind;
  seed: number;
  particles: BurstParticle[];
  duration: number;
  frame: number;
}

interface Init {
  shape: BurstShape;
  color: number;
  x: number;
  y: number;
  vx: number;
  vy: number;
  size: number;
  grow?: number;
  rot?: number;
  vrot?: number;
  delay: number;
  life: number;
}

function particle(i: Init): BurstParticle {
  return {
    shape: i.shape,
    color: i.color,
    x: i.x,
    y: i.y,
    vx: i.vx,
    vy: i.vy,
    size: i.size,
    grow: i.grow ?? 0,
    rot: i.rot ?? 0,
    vrot: i.vrot ?? 0,
    delay: i.delay,
    life: i.life,
    age: -i.delay,
    alpha: 0,
  };
}

const GOLD = [BurstColor.gold, BurstColor.goldDeep, BurstColor.white];
const CONFETTI = [
  BurstColor.overcome,
  BurstColor.gold,
  BurstColor.pink,
  BurstColor.violet,
  BurstColor.blue,
];
const BOGEY = [BurstColor.smoke, BurstColor.violet];

interface RadialOpts {
  speedLo: number;
  speedHi: number;
  radius?: number;
  sizeLo?: number;
  sizeHi?: number;
  lifeLo?: number;
  lifeHi?: number;
  delayLo?: number;
  delayHi?: number;
  grow?: number;
  spin?: number;
}

/** Plan every particle for `kind` from `seed` (MilestoneBurst.plan). */
export function planMilestoneBurst(kind: BurstKind, seed: number): MilestoneBurst {
  const next = mulberry32(seed);
  const r = (lo: number, hi: number) => lo + (hi - lo) * next();
  const pick = (colors: readonly number[]) => colors[Math.floor(next() * colors.length)];
  const ps: BurstParticle[] = [];

  const glow = (color: number, vy: number) =>
    ps.push(
      particle({ shape: 'glow', color, x: 0, y: 0, vx: 0, vy, size: 0.5, grow: 0.4, delay: 0, life: 1.4 }),
    );

  const radial = (shape: BurstShape, count: number, colors: readonly number[], o: RadialOpts) => {
    const radius = o.radius ?? 0;
    const spin = o.spin ?? 0;
    for (let i = 0; i < count; i++) {
      const a = r(0, 2 * Math.PI);
      const speed = r(o.speedLo, o.speedHi);
      const c = Math.cos(a);
      const s = Math.sin(a);
      // Dart's named-argument order: color, size, rot, vrot, delay, life.
      const color = pick(colors);
      const size = r(o.sizeLo ?? 0.012, o.sizeHi ?? 0.022);
      const rot = r(0, 2 * Math.PI);
      const vrot = r(-spin, spin);
      const delay = r(o.delayLo ?? 0, o.delayHi ?? 0);
      const life = r(o.lifeLo ?? 0.7, o.lifeHi ?? 1.2);
      ps.push(
        particle({
          shape,
          color,
          x: c * radius,
          y: s * radius,
          vx: c * speed,
          vy: s * speed,
          size,
          grow: o.grow ?? 0,
          rot,
          vrot,
          delay,
          life,
        }),
      );
    }
  };

  const fountain = (count: number, colors: readonly number[], delayLo: number, delayHi: number) => {
    for (let i = 0; i < count; i++) {
      const color = pick(colors);
      const x = r(-0.5, 0.5);
      const vx = r(-0.6, 0.6);
      const vy = r(-2.4, -1.4);
      const size = r(0.018, 0.03);
      const rot = r(0, 2 * Math.PI);
      const vrot = r(-12, 12);
      const delay = r(delayLo, delayHi);
      const life = r(1.6, 2.4);
      ps.push(particle({ shape: 'confetti', color, x, y: 0.55, vx, vy, size, rot, vrot, delay, life }));
    }
  };

  const orbit = (count: number, colors: readonly number[]) => {
    for (let i = 0; i < count; i++) {
      const a = r(0, 2 * Math.PI);
      const radius = r(0.45, 0.65);
      const speed = r(0.25, 0.45);
      const c = Math.cos(a);
      const s = Math.sin(a);
      const color = pick(colors);
      const size = r(0.12, 0.22);
      const delay = r(0, 0.3);
      const life = r(1.4, 2.2);
      ps.push(
        particle({
          shape: 'smoke',
          color,
          x: c * radius,
          y: s * radius,
          vx: -s * speed,
          vy: c * speed,
          size,
          grow: 0.12,
          delay,
          life,
        }),
      );
    }
  };

  switch (kind) {
    case 'newBoon':
      glow(BurstColor.gold, -0.08);
      radial('spark', 48, GOLD, { speedLo: 0.9, speedHi: 1.8 });
      break;
    case 'newBogey':
      radial('smoke', 16, BOGEY, {
        speedLo: 0.1,
        speedHi: 0.35,
        radius: 0.25,
        sizeLo: 0.12,
        sizeHi: 0.22,
        lifeLo: 1.4,
        lifeHi: 2.2,
        grow: 0.12,
      });
      radial('shard', 14, [BurstColor.white, BurstColor.violet], {
        speedLo: 0.8,
        speedHi: 1.4,
        sizeLo: 0.02,
        sizeHi: 0.04,
        lifeLo: 0.8,
        lifeHi: 1.3,
        spin: 8,
      });
      break;
    case 'masterBoon':
      glow(BurstColor.gold, -0.08);
      fountain(84, CONFETTI, 0, 0.25);
      radial('spark', 20, GOLD, { speedLo: 0.9, speedHi: 1.6 });
      break;
    case 'masterBogey':
      orbit(26, BOGEY);
      radial('ember', 18, [BurstColor.violet, BurstColor.white], {
        speedLo: 0.2,
        speedHi: 0.6,
        radius: 0.3,
        sizeLo: 0.008,
        sizeHi: 0.014,
        lifeLo: 1.0,
        lifeHi: 1.8,
      });
      break;
    case 'overcome':
      radial('smoke', 18, BOGEY, {
        speedLo: 0.1,
        speedHi: 0.3,
        radius: 0.3,
        sizeLo: 0.12,
        sizeHi: 0.22,
        lifeLo: 0.8,
        lifeHi: 1.1,
        grow: 0.16,
      });
      radial('ember', 10, [BurstColor.gold], {
        speedLo: 0.2,
        speedHi: 0.5,
        radius: 0.3,
        sizeLo: 0.008,
        sizeHi: 0.014,
        lifeLo: 0.7,
        lifeHi: 0.9,
      });
      fountain(72, [BurstColor.overcome, BurstColor.gold, BurstColor.pink], 0.55, 0.85);
      break;
  }
  let duration = 0;
  for (const p of ps) duration = Math.max(duration, p.delay + p.life);
  return { kind, seed, particles: ps, duration, frame: 0 };
}

/** Advance one BURST_DT step (MilestoneBurst.step). */
export function stepBurst(b: MilestoneBurst): void {
  b.frame++;
  for (const p of b.particles) {
    p.age += BURST_DT;
    if (p.age < 0) continue;
    if (p.age > p.life) {
      p.alpha = 0;
      continue;
    }
    const rule = RULES[p.shape];
    p.vx *= rule.drag;
    p.vy = p.vy * rule.drag + rule.gravity * BURST_DT;
    p.x += p.vx * BURST_DT;
    p.y += p.vy * BURST_DT;
    p.rot += p.vrot * BURST_DT;
    p.size += p.grow * BURST_DT;
    const fadeOutFrom = p.life * 0.65;
    const inA = p.age < rule.fadeIn ? p.age / rule.fadeIn : 1.0;
    const outA = p.age > fadeOutFrom ? 1 - (p.age - fadeOutFrom) / (p.life - fadeOutFrom) : 1.0;
    p.alpha = rule.peak * Math.min(inA, outA);
  }
}

export function stepBurstTo(b: MilestoneBurst, targetFrame: number): void {
  while (b.frame < targetFrame) stepBurst(b);
}

export function burstDone(b: MilestoneBurst): boolean {
  return b.frame * BURST_DT > b.duration;
}

/** The seed a moment's celebration draws from (burstSeedFor). */
export function burstSeedFor(momentId: string): number {
  return fnv1a32(`milestone|${momentId}`);
}
