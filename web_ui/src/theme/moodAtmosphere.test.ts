// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Mood on the character on the web: the label-to-tone table, strength by
// intensity and hold, a need in trouble (hygiene inverted for a character
// who enjoys it low), the ring's weight, the bond halo, and the chat
// state's look and paints. The numbers match mood_atmosphere.dart.

import { describe, expect, it } from 'vitest';
import {
  bondHalo, firstNeedInTrouble, intensityRank, moodAtmosphereOf, moodLookOf, moodPaintsOf, moodStrength, moodToneOf,
  moodVars, needTrouble, ringWeightForTrust,
} from './moodAtmosphere';

const paintsWire = {
  tones: { sour: '#ff5252', low: '#607d8b', anxious: '#7c4dff', lifted: '#ffc107', warm: '#ff4081', charged: '#ffab40' },
  dark: {
    needs: { hunger: '#ffab40', bladder: '#40c4ff', energy: '#ffd740', social: '#ff4081', fun: '#7c4dff', hygiene: '#18ffff', comfort: '#69f0ae' },
    haloWarm: '#ff4081', haloChill: '#448aff',
  },
  light: {
    needs: { hunger: '#a03c08', bladder: '#075985', energy: '#92400e', social: '#9d174d', fun: '#6d28d9', hygiene: '#155e75', comfort: '#1b5e20' },
    haloWarm: '#9d174d', haloChill: '#1d4ed8',
  },
};

describe('tones and strength', () => {
  it('maps the judge labels to the six tones and nothing else', () => {
    expect(moodToneOf('anger')).toBe('sour');
    expect(moodToneOf('Grief')).toBe('low');
    expect(moodToneOf('nervousness')).toBe('anxious');
    expect(moodToneOf('joy')).toBe('lifted');
    expect(moodToneOf('affection')).toBe('warm');
    expect(moodToneOf('curiosity')).toBe('charged');
    expect(moodToneOf('neutral')).toBeNull();
    expect(moodToneOf('')).toBeNull();
    expect(moodToneOf('bewilderment')).toBeNull();
  });

  it('ranks intensity words and treats a missing one as mild', () => {
    expect(intensityRank('strong')).toBe(3);
    expect(intensityRank('Medium')).toBe(2);
    expect(intensityRank('faint')).toBe(1);
    expect(intensityRank('')).toBe(0);
    expect(moodAtmosphereOf('joy', '', 0, 1).rank).toBe(1);
  });

  it('grows with intensity and drama, eases a little with hold, never below the floor', () => {
    expect(moodStrength('lifted', 1, 0, 1)).toBeCloseTo(0.3);
    expect(moodStrength('lifted', 2, 0, 1)).toBeCloseTo(0.55);
    expect(moodStrength('lifted', 3, 0, 1)).toBeCloseTo(0.85);
    expect(moodStrength('lifted', 3, 0, 1.6)).toBeCloseTo(1.2);
    expect(moodStrength('lifted', 3, 2, 1)).toBeCloseTo(0.85 / 1.16);
    expect(moodStrength('lifted', 3, 40, 1)).toBeCloseTo(0.85 * 0.6);
    expect(moodStrength(null, 3, 0, 1)).toBe(0);
    expect(moodAtmosphereOf('neutral', 'strong', 0, 1).strength).toBe(0);
  });
});

describe('needs, trust and bond', () => {
  it('a need under 25 throbs and under 10 hammers', () => {
    expect(needTrouble('energy', 30, false)).toEqual({ low: false, critical: false, inverted: false });
    expect(needTrouble('energy', 25, false)).toEqual({ low: true, critical: false, inverted: false });
    expect(needTrouble('energy', 9, false)).toEqual({ low: true, critical: true, inverted: false });
  });

  it('hygiene inverts for a character who enjoys it low', () => {
    expect(needTrouble('hygiene', 12, true)).toEqual({ low: false, critical: false, inverted: true });
    expect(needTrouble('hygiene', 75, true)).toEqual({ low: true, critical: false, inverted: true });
    expect(needTrouble('hygiene', 92, true)).toEqual({ low: true, critical: true, inverted: true });
    expect(needTrouble('hygiene', 12, false).low).toBe(true);
    expect(needTrouble('energy', 92, true).low).toBe(false);
  });

  it('names the first need in trouble', () => {
    expect(firstNeedInTrouble({ hunger: 80, energy: 12, social: 70 }, false)).toBe('energy');
    expect(firstNeedInTrouble({ hunger: 80, hygiene: 90 }, true)).toBe('hygiene');
    expect(firstNeedInTrouble({ hunger: 80, hygiene: 90 }, false)).toBeNull();
  });

  it('weights the ring by trust and the halo by bond', () => {
    expect(ringWeightForTrust(55)).toBe('heavy');
    expect(ringWeightForTrust(0)).toBe('settled');
    expect(ringWeightForTrust(-40)).toBe('broken');
    expect(bondHalo(40)).toEqual({ share: 0.4, warm: true });
    expect(bondHalo(-100)).toEqual({ share: 1, warm: false });
  });
});

describe('the chat state wire', () => {
  it('reads the look and falls back to off for an older desktop', () => {
    expect(moodLookOf({ moodOnCharacter: 'all', moodDrama: 1.3 })).toEqual({ level: 'all', drama: 1.3 });
    expect(moodLookOf({ moodOnCharacter: 'portrait', moodDrama: 9 })).toEqual({ level: 'portrait', drama: 1.6 });
    expect(moodLookOf({ moodOnCharacter: 'loud' })).toEqual({ level: 'off', drama: 1 });
    expect(moodLookOf(null)).toEqual({ level: 'off', drama: 1 });
  });

  it('accepts the paints for a mode and rejects a broken set', () => {
    const dark = moodPaintsOf(paintsWire, 'dark');
    expect(dark?.tones.lifted).toBe('#ffc107');
    expect(dark?.needs.energy).toBe('#ffd740');
    expect(dark?.haloChill).toBe('#448aff');
    expect(moodPaintsOf(paintsWire, 'light')?.needs.energy).toBe('#92400e');
    expect(moodPaintsOf(null, 'dark')).toBeNull();
    expect(moodPaintsOf({ ...paintsWire, tones: { ...paintsWire.tones, warm: 'pink' } }, 'dark')).toBeNull();
    expect(moodPaintsOf({ ...paintsWire, dark: { ...paintsWire.dark, haloWarm: 'url(x)' } }, 'dark')).toBeNull();
  });

  it('turns a mood into the custom properties the ring paints from', () => {
    const paints = moodPaintsOf(paintsWire, 'dark')!;
    const vars = moodVars(moodAtmosphereOf('joy', 'strong', 0, 1), paints, 40, 55, '#ffd740');
    expect(vars['--mood-hue']).toBe('#ffc107');
    expect(vars['--mood-a']).toBe('0.850');
    expect(vars['--mood-halo']).toBe('#ff4081');
    expect(vars['--mood-halo-share']).toBe('0.400');
    expect(vars['--mood-ring-w']).toBe('5px');
    expect(vars['--mood-need']).toBe('#ffd740');
    const chilled = moodVars(moodAtmosphereOf('neutral', '', 0, 1), paints, -30, -40, null);
    expect(chilled['--mood-hue']).toBe('transparent');
    expect(chilled['--mood-halo']).toBe('#448aff');
    expect(chilled['--mood-ring-w']).toBe('1.5px');
    expect('--mood-need' in chilled).toBe(false);
  });
});
