// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The story-clock sky on the web: the parser takes the desktop's wire and
// nothing else, and the blend, the arcs, the stars, the horizon, the moon
// and a sweep reproduce the shared vectors the Dart side is pinned to
// (test/fixtures/ambient/scene_sky_vectors.json, from scene_sky.dart).

import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import {
  MOONRISE, MOONSET, STAR_COUNT, STAR_SEED, SUNRISE, SUNSET, SWEEP_SECONDS, SceneSkyMotion, horizonGlowAt,
  parseRgb, parseSceneSky, scatterStars, skyArcAt, skyWashAt, starTwinkle, starVisibilityAt, type SkyStop,
} from './sceneSky';

const vectors = JSON.parse(
  readFileSync(join(__dirname, '..', '..', '..', 'test', 'fixtures', 'ambient', 'scene_sky_vectors.json'), 'utf8'),
);

// The desktop's stops: kSceneDaypartWash at the clock's representative minutes.
const STOPS: SkyStop[] = [
  { at: 360, colour: [0xf2, 0xa0, 0x7b], alpha: 0.14 },
  { at: 540, colour: [0xff, 0xe9, 0xc4], alpha: 0.08 },
  { at: 690, colour: [0xff, 0xff, 0xff], alpha: 0 },
  { at: 870, colour: [0xff, 0xf3, 0xd6], alpha: 0.05 },
  { at: 1110, colour: [0xe8, 0x91, 0x3f], alpha: 0.14 },
  { at: 1350, colour: [0x12, 0x2a, 0x4a], alpha: 0.32 },
];

const paints = {
  scale: 1,
  stops: STOPS.map((s) => ({ at: s.at, colour: `#${s.colour.map((c) => c.toString(16).padStart(2, '0')).join('')}`, alpha: s.alpha })),
  sunHigh: '#fff0c8', sunLow: '#ffb06a', moon: '#e8ecf6', moonGlow: '#dce4ff', star: '#ecf0ff', dawn: '#f2a07b', dusk: '#e8913f',
};
const sky = { minute: 1380, moonPhase: 0.4, disc: 0.6, stars: 0.15, dark: paints, light: { ...paints, scale: 0.45, star: '#3c4664' } };
const wire = { level: 'effects', pauseWhileGenerating: true, sky, dark: {}, light: {} };

describe('sky wire', () => {
  it('accepts what the desktop sends, for the painted mode', () => {
    const dark = parseSceneSky(wire, 'dark');
    expect(dark).not.toBeNull();
    expect(dark?.minute).toBe(1380);
    expect(dark?.dark).toBe(true);
    expect(dark?.paints.stops[0]).toEqual(STOPS[0]);
    expect(dark?.paints.star).toEqual([0xec, 0xf0, 0xff]);
    const light = parseSceneSky(wire, 'light');
    expect(light?.dark).toBe(false);
    expect(light?.paints.scale).toBe(0.45);
    expect(light?.paints.star).toEqual([0x3c, 0x46, 0x64]);
  });

  it('rejects an older desktop and a broken sky', () => {
    expect(parseSceneSky(null, 'dark')).toBeNull();
    expect(parseSceneSky({ ...wire, sky: undefined }, 'dark')).toBeNull();
    expect(parseSceneSky({ ...wire, sky: { ...sky, minute: 1440 } }, 'dark')).toBeNull();
    expect(parseSceneSky({ ...wire, sky: { ...sky, minute: 10.5 } }, 'dark')).toBeNull();
    expect(parseSceneSky({ ...wire, sky: { ...sky, dark: { ...paints, moon: 'url(x)' } } }, 'dark')).toBeNull();
    expect(parseSceneSky({ ...wire, sky: { ...sky, dark: { ...paints, stops: [] } } }, 'dark')).toBeNull();
    // The colours live on the sky; a mode map's own `sky` is not read.
    expect(parseSceneSky({ ...wire, sky: { ...sky, dark: undefined }, dark: { sky: paints } }, 'dark')).toBeNull();
    expect(parseSceneSky({ ...wire, level: 'off' }, 'dark')).toBeNull();
  });

  it('reads both colour spellings', () => {
    expect(parseRgb('#f2a07b')).toEqual([0xf2, 0xa0, 0x7b]);
    expect(parseRgb('rgba(18, 42, 74, 0.32)')).toEqual([18, 42, 74]);
    expect(parseRgb('red')).toBeNull();
  });
});

describe('shared vectors', () => {
  it('wash, arcs, stars and horizon match the desktop', () => {
    for (const cell of vectors.minutes) {
      const m = cell.minute as number;
      const wash = skyWashAt(m, STOPS);
      expect(wash.colour[0]).toBeCloseTo(cell.wash.r, 6);
      expect(wash.colour[1]).toBeCloseTo(cell.wash.g, 6);
      expect(wash.colour[2]).toBeCloseTo(cell.wash.b, 6);
      expect(wash.alpha).toBeCloseTo(cell.wash.alpha, 9);
      for (const [name, rise, set] of [['sun', SUNRISE, SUNSET], ['moon', MOONRISE, MOONSET]] as const) {
        const arc = skyArcAt(m, rise, set);
        const want = cell[name];
        if (want === null) {
          expect(arc).toBeNull();
        } else {
          expect(arc?.p).toBeCloseTo(want.p, 9);
          expect(arc?.x).toBeCloseTo(want.x, 9);
          expect(arc?.y).toBeCloseTo(want.y, 9);
          expect(arc?.alt).toBeCloseTo(want.alt, 9);
        }
      }
      expect(starVisibilityAt(m)).toBeCloseTo(cell.stars, 9);
      const glow = horizonGlowAt(m);
      expect(glow.strength).toBeCloseTo(cell.horizon.strength, 9);
      expect(glow.dawn).toBe(cell.horizon.dawn);
    }
  });

  it('the star field, the twinkle and a sweep match the desktop', () => {
    const stars = scatterStars(STAR_SEED, 5);
    vectors.starField.forEach((want: Record<string, number>, i: number) => {
      expect(stars[i].x).toBeCloseTo(want.x, 12);
      expect(stars[i].y).toBeCloseTo(want.y, 12);
      expect(stars[i].size).toBeCloseTo(want.size, 12);
      expect(stars[i].alpha).toBeCloseTo(want.alpha, 12);
      expect(stars[i].phase).toBeCloseTo(want.phase, 12);
      expect(stars[i].speed).toBeCloseTo(want.speed, 12);
    });
    expect(starTwinkle(stars[0], 2.5)).toBeCloseTo(vectors.twinkle, 12);
    expect(scatterStars(STAR_SEED, STAR_COUNT)).toHaveLength(STAR_COUNT);
    const m = new SceneSkyMotion(vectors.sweep.from);
    m.retarget(vectors.sweep.to, true);
    for (const step of vectors.sweep.steps) {
      m.advance(step.after);
      expect(m.shown).toBeCloseTo(step.shown, 9);
      expect(m.sweeping).toBe(step.sweeping);
    }
  });
});

describe('motion', () => {
  it('snaps on a still stage and lands after a sweep', () => {
    const still = new SceneSkyMotion(870);
    still.retarget(360, false);
    expect(still.shown).toBe(360);
    expect(still.sweeping).toBe(false);
    const sweep = new SceneSkyMotion(870);
    sweep.retarget(360, true);
    sweep.advance(SWEEP_SECONDS);
    expect(sweep.shown).toBe(360);
    expect(sweep.sweeping).toBe(false);
  });
});
